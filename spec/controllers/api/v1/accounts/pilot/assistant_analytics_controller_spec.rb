# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::AssistantAnalytics', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:analytics_url) { "/api/v1/accounts/#{account.id}/pilot/assistants/#{assistant.id}/analytics" }
  let(:drilldown_url) { "/api/v1/accounts/#{account.id}/pilot/assistants/#{assistant.id}/drilldown" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
    Redis::Alfred.delete(Pilot::OutcomeTrackingHistory::CACHE_KEY)
  end

  def episode(overrides = {})
    create(:pilot_conversation_outcome, account: account, assistant: assistant, inbox: inbox,
                                        conversation: create(:conversation, account: account, inbox: inbox), **overrides)
  end

  describe 'GET /analytics/overview' do
    before { travel_to(Time.zone.parse('2026-10-02 12:00:00')) }

    it 'returns packed metrics and the tracking start for any account user' do
      episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))

      get "#{analytics_url}/overview", params: { range: '7', timezone_offset: '0' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['tracking_started_at']).to be_present
      expect(body['metrics']['conversations_involved']).to include('current' => 1, 'previous' => 0, 'trend' => 0)
      expect(body['metrics'].keys).to include('autonomous_resolution_rate', 'handoff_rate', 'estimated_hours_saved',
                                              'reopen_after_resolution_rate', 'conversation_depth', 'durable_resolution_rate',
                                              'autonomous_csat', 'assisted_csat', 'human_only_csat', 'median_resolution_seconds')
    end

    it 'returns 403 when the pilot_autopilot feature is disabled' do
      account.disable_features!(:pilot_autopilot)

      get "#{analytics_url}/overview", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /analytics/resolution_flow' do
    before { travel_to(Time.zone.parse('2026-10-02 12:00:00')) }

    it 'returns balanced nodes, links, and reason distribution' do
      episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))

      get "#{analytics_url}/resolution_flow", params: { range: '7', timezone_offset: '0' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['nodes']).to include(include('id' => 'involved', 'value' => 1))
      expect(body['links']).to include(include('source' => 'involved', 'target' => 'autonomous', 'value' => 1))
      expect(body['handoff_reasons']).to eq([])
    end
  end

  describe 'GET /analytics/resolution_trend' do
    before { travel_to(Time.zone.parse('2026-10-02 12:00:00')) }

    it 'returns a bucketed series with comparison entries' do
      episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))

      get "#{analytics_url}/resolution_trend", params: { range: '7', timezone_offset: '0' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['granularity']).to eq('day')
      expect(body['buckets'].size).to eq(7)
      bucket = body['buckets'].find { |entry| entry['start_date'] == '2026-09-27' }
      expect(bucket).to include('involved' => 1, 'autonomous' => 1, 'resolution_rate' => 1.0)
      expect(bucket['comparison']).to include('start_date', 'end_date', 'resolution_rate')
    end
  end

  describe 'GET /analytics/overview_summary' do
    before { travel_to(Time.zone.parse('2026-10-02 12:00:00')) }

    it 'rejects an invalid timezone offset with 422' do
      get "#{analytics_url}/overview_summary", params: { range: '7', timezone_offset: 'bogus' },
                                               headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns an empty point list without an LLM call when there is no activity' do
      allow(Pilot::Analytics::OverviewSummaryGenerator).to receive(:new).and_wrap_original do |original, **kwargs|
        instance = original.call(**kwargs)
        allow(instance).to receive(:make_api_call).and_raise('should not call the LLM')
        instance
      end

      get "#{analytics_url}/overview_summary", params: { range: '7', timezone_offset: '0' },
                                               headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['points']).to eq([])
    end

    context 'with activity in the window' do
      let(:generator) { instance_double(Pilot::Analytics::OverviewSummaryGenerator) }

      before do
        episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
        episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
                resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))
        allow(Pilot::Analytics::OverviewSummaryGenerator).to receive(:new).and_return(generator)
      end

      it 'caches successful summaries and serves repeats without regenerating' do
        allow(generator).to receive(:perform).and_return({ points: ['One observation.'] })

        get "#{analytics_url}/overview_summary", params: { range: '7', timezone_offset: '0' },
                                                 headers: admin.create_new_auth_token, as: :json
        expect(response.parsed_body['points']).to eq(['One observation.'])

        get "#{analytics_url}/overview_summary", params: { range: '7', timezone_offset: '0' },
                                                 headers: admin.create_new_auth_token, as: :json
        expect(response.parsed_body['points']).to eq(['One observation.'])
        expect(generator).to have_received(:perform).once
      end

      it 'varies the cache key with the requested range' do
        allow(generator).to receive(:perform).and_return({ points: ['One observation.'] })

        get "#{analytics_url}/overview_summary", params: { range: '7', timezone_offset: '0' },
                                                 headers: admin.create_new_auth_token, as: :json
        get "#{analytics_url}/overview_summary", params: { range: '30', timezone_offset: '0' },
                                                 headers: admin.create_new_auth_token, as: :json

        expect(generator).to have_received(:perform).twice
      end

      it 'never caches failures and surfaces 422 with an error payload' do
        allow(generator).to receive(:perform).and_return({ error: 'rate limited' })

        2.times do
          get "#{analytics_url}/overview_summary", params: { range: '7', timezone_offset: '0' },
                                                   headers: admin.create_new_auth_token, as: :json
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('rate limited')
        end
        expect(generator).to have_received(:perform).twice
      end
    end
  end

  describe 'GET /drilldown' do
    before { travel_to(Time.zone.parse('2026-10-02 12:00:00')) }

    it 'is forbidden for non-administrators' do
      get drilldown_url, params: { metric: 'conversations_involved', range: '7', timezone_offset: '0' },
                         headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects unsupported metrics with 422' do
      get drilldown_url, params: { metric: 'autonomous_csat', range: '7', timezone_offset: '0' },
                         headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns serialized conversations with meta for administrators' do
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, private: false, sender: assistant,
                       created_at: Time.zone.parse('2026-09-27 10:00'))

      get drilldown_url, params: { metric: 'conversations_involved', range: '7', timezone_offset: '0', per_page: 500 },
                         headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['meta']).to include('metric' => 'conversations_involved', 'total_count' => 1, 'per_page' => 100,
                                      'since' => Time.zone.parse('2026-09-26 00:00:00').to_i)
      expect(body['payload'].first['record_type']).to eq('conversation')
      expect(body['payload'].first['conversation']['id']).to eq(conversation.id)
    end
  end
end
