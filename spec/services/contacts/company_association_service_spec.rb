# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Contacts::CompanyAssociationService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new }

  describe '#associate_company_from_email' do
    context 'when a contact has a business email and no company' do
      it 'creates a company, links the contact, and seeds activity' do
        contact = create(:contact, email: nil, account: account, last_activity_at: 1.hour.ago)
        # rubocop:disable Rails/SkipsModelValidations
        contact.update_column(:email, 'john@acme.com')
        # rubocop:enable Rails/SkipsModelValidations

        expect { service.associate_company_from_email(contact) }.to change(Company, :count).by(1)

        contact.reload
        expect(contact.company).to be_present
        expect(contact.company.domain).to eq('acme.com')
        expect(contact.company.name).to eq('Acme')
        expect(contact.additional_attributes['company_name']).to eq('Acme')
        expect(contact.company.last_activity_at).to be_within(1.second).of(contact.last_activity_at)
      end

      it 'reuses an existing company with the same domain' do
        existing_company = create(:company, domain: 'acme.com', account: account)
        contact = create(:contact, email: 'john@acme.com', account: account, company_id: nil)
        # rubocop:disable Rails/SkipsModelValidations
        contact.update_column(:company_id, nil)
        # rubocop:enable Rails/SkipsModelValidations

        expect { service.associate_company_from_email(contact) }.not_to change(Company, :count)
        expect(contact.reload.company).to eq(existing_company)
      end

      it 'increments the company contacts counter' do
        contact = create(:contact, email: nil, account: account)
        # rubocop:disable Rails/SkipsModelValidations
        contact.update_column(:email, 'jane@techcorp.com')
        # rubocop:enable Rails/SkipsModelValidations

        service.associate_company_from_email(contact)

        expect(contact.reload.company.contacts_count).to eq(1)
      end
    end

    context 'when a contact already has a company' do
      it 'skips association' do
        existing_company = create(:company, account: account)
        contact = create(:contact, email: 'john@acme.com', account: account, company_id: existing_company.id)

        expect(service.associate_company_from_email(contact)).to be_nil
        expect(contact.reload.company).to eq(existing_company)
      end
    end

    context 'when a contact has a free-mail email' do
      it 'does not create a company' do
        contact = create(:contact, email: 'john@gmail.com', account: account, company_id: nil)
        # rubocop:disable Rails/SkipsModelValidations
        contact.update_column(:company_id, nil)
        # rubocop:enable Rails/SkipsModelValidations

        expect { service.associate_company_from_email(contact) }.not_to change(Company, :count)
        expect(contact.reload.company).to be_nil
      end
    end

    context 'when a contact has no email' do
      it 'skips association' do
        contact = create(:contact, email: nil, account: account)

        expect(service.associate_company_from_email(contact)).to be_nil
        expect(contact.reload.company).to be_nil
      end
    end
  end
end
