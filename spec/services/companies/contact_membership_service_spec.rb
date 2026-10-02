# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Companies::ContactMembershipService, type: :service do
  let(:account) { create(:account) }
  let(:company) { create(:company, account: account) }
  let(:service) { described_class.new(company: company) }

  describe '#assign' do
    it 'links the contact, writes the denormalized name, and seeds activity' do
      contact = create(:contact, account: account, last_activity_at: 1.hour.ago)

      service.assign(contact: contact)

      contact.reload
      expect(contact.company).to eq(company)
      expect(contact.additional_attributes['company_name']).to eq(company.name)
      expect(company.reload.last_activity_at).to be_within(1.second).of(contact.last_activity_at)
    end

    it 'moves a contact from another company' do
      other_company = create(:company, account: account)
      contact = create(:contact, account: account, company: other_company)

      service.assign(contact: contact)

      expect(contact.reload.company).to eq(company)
      expect(contact.additional_attributes['company_name']).to eq(company.name)
    end
  end

  describe '#remove' do
    it 'clears the linkage and the denormalized name' do
      contact = create(:contact, account: account, company: company, additional_attributes: { 'city' => 'Berlin' })

      service.remove(contact: contact)

      contact.reload
      expect(contact.company).to be_nil
      expect(contact.additional_attributes).to eq('city' => 'Berlin')
    end
  end
end
