# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Companies::SyncContactNamesJob, type: :job do
  let(:account) { create(:account) }
  let(:company) { create(:company, account: account, name: 'Acme') }

  describe '#perform' do
    it 'rewrites the denormalized company name on member contacts' do
      contact = create(:contact, account: account, company: company,
                                 additional_attributes: { 'company_name' => 'Acme', 'city' => 'Berlin' })

      company.update!(name: 'Acme Labs')
      described_class.perform_now(company_id: company.id)

      expect(contact.reload.additional_attributes).to eq('company_name' => 'Acme Labs', 'city' => 'Berlin')
    end

    it 'uses the current company name even for a stale rename job' do
      contact = create(:contact, account: account, company: company,
                                 additional_attributes: { 'company_name' => 'Acme' })

      company.update!(name: 'Acme Labs')
      described_class.perform_now(company_id: company.id)

      expect(contact.reload.additional_attributes).to eq('company_name' => 'Acme Labs')
    end

    it 'does not touch contact callbacks or timestamps' do
      contact = create(:contact, account: account, company: company,
                                 additional_attributes: { 'company_name' => 'Acme' })
      original_updated_at = contact.reload.updated_at

      company.update!(name: 'Acme Labs')
      described_class.perform_now(company_id: company.id)

      expect(contact.reload.updated_at).to eq(original_updated_at)
    end

    it 'is a no-op when the company no longer exists' do
      expect { described_class.perform_now(company_id: -1) }.not_to raise_error
    end
  end
end
