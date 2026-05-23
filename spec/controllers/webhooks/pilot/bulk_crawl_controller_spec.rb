# frozen_string_literal: true

require 'rails_helper'

# Per pilot-telemetry "Inbound webhook for bulk content ingestion"
# (17.20–17.23): unauthenticated inbound endpoint that the external
# bulk-crawl service POSTs page payloads to. Token is SHA-256 of
# (last_four_of_api_key + assistant_id + account_id) and compared
# constant-time. Valid token creates / updates a `Pilot::Document`;
# invalid token returns 403; unknown assistant returns 404.
RSpec.describe Webhooks::Pilot::BulkCrawlController, type: :request do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:api_key) { 'sk-test-abcdefXXXX' }

  before do
    allow(Llm::Config).to receive(:api_key).and_return(api_key)
  end

  def token_for(assistant_id, account_id, key: api_key)
    Digest::SHA256.hexdigest("#{key.to_s.last(4)}#{assistant_id}#{account_id}")
  end

  describe 'POST /webhooks/pilot/bulk_crawl/:assistant_id/:token' do
    let(:valid_token) { token_for(assistant.id, account.id) }
    let(:payload) do
      {
        external_link: 'https://docs.example.com/articles/refunds',
        content: 'How to request a refund...',
        name: 'Refunds'
      }
    end

    context 'with a valid token' do
      it 'creates a Pilot::Document on first call' do
        expect do
          post "/webhooks/pilot/bulk_crawl/#{assistant.id}/#{valid_token}", params: payload
        end.to change(Pilot::Document, :count).by(1)

        expect(response).to have_http_status(:ok)
        document = Pilot::Document.last
        expect(document.assistant_id).to eq(assistant.id)
        expect(document.account_id).to eq(account.id)
        expect(document.external_link).to eq(payload[:external_link])
        expect(document.content).to eq(payload[:content])
      end

      it 'updates an existing document on subsequent calls for the same external_link' do
        existing = create(:pilot_document, assistant: assistant, external_link: payload[:external_link], content: 'old')

        expect do
          post "/webhooks/pilot/bulk_crawl/#{assistant.id}/#{valid_token}", params: payload
        end.not_to change(Pilot::Document, :count)

        expect(response).to have_http_status(:ok)
        expect(existing.reload.content).to eq(payload[:content])
      end
    end

    context 'with an invalid token' do
      it 'returns 403 and does not create a document' do
        expect do
          post "/webhooks/pilot/bulk_crawl/#{assistant.id}/wrongtoken", params: payload
        end.not_to change(Pilot::Document, :count)

        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 when token is computed against a different api_key tail' do
        bogus = token_for(assistant.id, account.id, key: 'sk-other-abcdYYYY')
        expect do
          post "/webhooks/pilot/bulk_crawl/#{assistant.id}/#{bogus}", params: payload
        end.not_to change(Pilot::Document, :count)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with an unknown assistant' do
      it 'returns 404' do
        # Token shape is irrelevant when the assistant lookup fails first.
        unknown_id = assistant.id + 99_999
        post "/webhooks/pilot/bulk_crawl/#{unknown_id}/anytoken", params: payload
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
