# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::LogbookEntry do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:contact_id) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:contact) }
  end

  describe 'factory' do
    it 'creates valid logbook entry object' do
      logbook_entry = create(:pilot_logbook_entry)
      expect(logbook_entry).to be_valid
    end
  end

  describe 'ensure_account_id' do
    it 'sets account_id from contact if missing' do
      contact = create(:contact)
      logbook_entry = described_class.new(content: 'test', contact: contact)
      logbook_entry.valid?
      expect(logbook_entry.account_id).to eq(contact.account_id)
    end
  end
end
