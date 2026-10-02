# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::ConversationOutcome do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def build_outcome(**attrs)
    build(
      :pilot_conversation_outcome,
      account: account,
      assistant: assistant,
      inbox: inbox,
      conversation: conversation,
      **attrs
    )
  end

  describe 'validations' do
    it 'is valid when every association belongs to the account' do
      expect(build_outcome).to be_valid
    end

    it 'requires a start timestamp' do
      expect(build_outcome(started_at: nil)).not_to be_valid
    end

    it 'rejects an unknown episode trigger' do
      expect(build_outcome(episode_trigger: 'assignment')).not_to be_valid
    end

    it 'allows the handoff reason category to be empty until a handoff occurs' do
      expect(build_outcome(handoff_reason_category: nil)).to be_valid
    end

    it 'rejects an unknown handoff reason category' do
      expect(build_outcome(handoff_reason_category: 'made_up_reason')).not_to be_valid
    end

    it 'includes a category denoting quota exhaustion' do
      expect(described_class::HANDOFF_REASON_CATEGORIES).to include('quota_exhausted')
    end

    it 'is invalid when the assistant belongs to another account' do
      expect(build_outcome(assistant: create(:pilot_assistant))).not_to be_valid
    end

    it 'is invalid when the conversation belongs to another account' do
      expect(build_outcome(conversation: create(:conversation))).not_to be_valid
    end

    it 'is invalid when the inbox belongs to another account' do
      expect(build_outcome(inbox: create(:inbox))).not_to be_valid
    end
  end

  describe '.covering' do
    let(:start) { Time.zone.parse('2026-01-01 10:00:00') }

    def create_episode(started_at:, ended_at: nil)
      create(
        :pilot_conversation_outcome,
        account: account,
        assistant: assistant,
        inbox: inbox,
        conversation: conversation,
        started_at: started_at,
        ended_at: ended_at
      )
    end

    it 'covers the start instant and every later instant for an open episode' do
      episode = create_episode(started_at: start)

      expect(described_class.covering(start)).to include(episode)
      expect(described_class.covering(start + 1.day)).to include(episode)
    end

    it 'treats the window as half-open [started_at, ended_at)' do
      episode = create_episode(started_at: start, ended_at: start + 1.hour)

      expect(described_class.covering(start)).to include(episode)
      expect(described_class.covering(start + 59.minutes)).to include(episode)
      expect(described_class.covering(start + 1.hour)).not_to include(episode)
    end

    it 'excludes instants before the window' do
      create_episode(started_at: start, ended_at: start + 1.hour)

      expect(described_class.covering(start - 1.second)).to be_empty
    end
  end

  describe 'partial unique indexes' do
    def create_episode(started_at:, episode_trigger: 'initial', ended_at: nil)
      create(
        :pilot_conversation_outcome,
        account: account,
        assistant: assistant,
        inbox: inbox,
        conversation: conversation,
        episode_trigger: episode_trigger,
        started_at: started_at,
        ended_at: ended_at
      )
    end

    it 'rejects a second open episode for the same conversation' do
      create_episode(started_at: 2.hours.ago)

      expect { create_episode(started_at: 1.hour.ago) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'rejects a second initial episode for the same conversation' do
      create_episode(started_at: 2.hours.ago, ended_at: 1.hour.ago)

      expect { create_episode(started_at: 30.minutes.ago) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows a reopen episode alongside the initial episode' do
      create_episode(started_at: 2.hours.ago, ended_at: 1.hour.ago)

      expect { create_episode(started_at: 1.hour.ago, episode_trigger: 'reopen') }.not_to raise_error
    end
  end
end
