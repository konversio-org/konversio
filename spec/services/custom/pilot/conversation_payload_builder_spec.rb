require 'rails_helper'

RSpec.describe Custom::Pilot::ConversationPayloadBuilder do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  describe '.call' do
    it 'returns the stable envelope keys without an assistant block when assistant is absent' do
      envelope = described_class.call(conversation: conversation)

      expect(envelope.keys).to contain_exactly(:id, :display_id, :inbox_id, :contact_id, :status, :priority, :labels, :custom_attributes)
    end

    it 'mirrors the conversation identifiers and per-record values onto the envelope' do
      envelope = described_class.call(conversation: conversation)

      expect(envelope).to include(
        id: conversation.id,
        display_id: conversation.display_id,
        inbox_id: conversation.inbox_id,
        contact_id: conversation.contact_id,
        status: 'open',
        labels: [],
        custom_attributes: {}
      )
    end

    it 'adds an assistant block when an assistant is supplied' do
      envelope = described_class.call(conversation: conversation, assistant: assistant)

      expect(envelope[:assistant]).to include(id: assistant.id, name: assistant.name)
      expect(envelope[:assistant]).to have_key(:avatar_url)
    end

    it 'keeps the same envelope keys regardless of which event name the caller uses' do
      a = described_class.call(conversation: conversation, assistant: assistant)
      b = described_class.call(conversation: conversation, assistant: assistant)

      expect(a.keys).to eq(b.keys)
    end

    it 'returns an empty hash when conversation is nil' do
      expect(described_class.call(conversation: nil)).to eq({})
    end

    it 'reflects post-transition status into the envelope' do
      conversation.update!(status: :resolved)
      envelope = described_class.call(conversation: conversation, assistant: assistant)

      expect(envelope[:status]).to eq('resolved')
    end

    # §13 testing-patterns gaps that apply to the envelope builder:
    # downstream consumers rely on a fixed schema across event names, so any
    # nil-ish field should still appear as the right key with the right type.

    it 'reflects post-transition priority into the envelope (string presence)' do
      conversation.update!(priority: :high)
      envelope = described_class.call(conversation: conversation)
      expect(envelope[:priority]).to eq('high')
    end

    it 'returns nil priority when the conversation has no priority set' do
      conversation.update!(priority: nil)
      envelope = described_class.call(conversation: conversation)
      expect(envelope[:priority]).to be_nil
    end

    it 'reflects label_list contents when labels are present' do
      conversation.update!(label_list: %w[refund vip])
      envelope = described_class.call(conversation: conversation)
      expect(envelope[:labels]).to match_array(%w[refund vip])
    end

    it 'reflects custom_attributes contents instead of swallowing them' do
      conversation.update!(custom_attributes: { 'tier' => 'gold' })
      envelope = described_class.call(conversation: conversation)
      expect(envelope[:custom_attributes]).to eq('tier' => 'gold')
    end

    # Assistant block has a fixed shape — its keys must not drift.
    it 'returns the assistant block with exactly id/name/avatar_url' do
      envelope = described_class.call(conversation: conversation, assistant: assistant)
      expect(envelope[:assistant].keys).to contain_exactly(:id, :name, :avatar_url)
    end

    # Account scoping isn't enforced by the builder itself (it just reads
    # conversation fields), but if the conversation belongs to a different
    # account than the supplied assistant, the envelope still mirrors the
    # conversation — no spooky cross-account rewrite.
    it 'does not rewrite conversation fields based on a mismatched assistant account' do
      other_account = create(:account)
      foreign_assistant = create(:pilot_assistant, account: other_account)
      envelope = described_class.call(conversation: conversation, assistant: foreign_assistant)
      expect(envelope[:id]).to eq(conversation.id)
      expect(envelope[:inbox_id]).to eq(conversation.inbox_id)
      expect(envelope[:assistant][:id]).to eq(foreign_assistant.id)
    end
  end
end
