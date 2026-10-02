# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Companies::DeleteJob, type: :job do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:company) { create(:company, account: account, name: 'Acme') }

    it 'detaches members, clears their company name, and destroys the company' do
      contact = create(:contact, account: account, company: company,
                                 additional_attributes: { 'company_name' => 'Acme', 'city' => 'Berlin' })
      other_contact = create(:contact, account: account, additional_attributes: { 'company_name' => 'Acme' })

      described_class.perform_now(company_id: company.id)

      expect { company.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(contact.reload.company_id).to be_nil
      expect(contact.additional_attributes).to eq('city' => 'Berlin')
      expect(other_contact.reload.additional_attributes).to eq('company_name' => 'Acme')
    end

    it 'detaches members without dispatching contact automations or webhooks' do
      contact = create(:contact, account: account, company: company,
                                 additional_attributes: { 'company_name' => 'Acme' })
      original_updated_at = contact.reload.updated_at

      described_class.perform_now(company_id: company.id)

      expect(contact.reload.updated_at).to eq(original_updated_at)
    end

    it 'is a no-op when the company no longer exists' do
      expect { described_class.perform_now(company_id: -1) }.not_to raise_error
    end
  end
end
