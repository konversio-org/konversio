require 'rails_helper'

RSpec.describe Pilot::Inbox do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  it 'allows an inbox to be detached from an assistant' do
    pilot_inbox = described_class.create!(assistant: assistant, inbox: inbox)

    expect { pilot_inbox.destroy! }.to change(described_class, :count).by(-1)
  end

  it 'rejects connecting the same inbox to a different assistant' do
    described_class.create!(assistant: assistant, inbox: inbox)
    duplicate = described_class.new(
      assistant: create(:pilot_assistant, account: account),
      inbox: inbox
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:inbox_id]).to include('is already connected to another assistant')
  end
end
