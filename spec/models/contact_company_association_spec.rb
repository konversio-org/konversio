# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Contact, type: :model do
  describe 'company auto-association' do
    let(:account) { create(:account) }

    context 'when creating a new contact with a business email' do
      it 'creates and associates a company' do
        expect do
          create(:contact, email: 'john@acme.com', account: account)
        end.to change(Company, :count).by(1)

        contact = described_class.last
        expect(contact.company).to be_present
        expect(contact.company.domain).to eq('acme.com')
        expect(contact.reload.additional_attributes['company_name']).to eq('Acme')
      end

      it 'does not create a company for free-mail providers' do
        expect do
          create(:contact, email: 'john@gmail.com', account: account)
        end.not_to change(Company, :count)

        expect(described_class.last.company).to be_nil
      end
    end

    context 'when updating a contact to add an email for the first time' do
      it 'creates and associates a company' do
        contact = create(:contact, email: nil, account: account)

        expect do
          contact.update(email: 'john@acme.com')
        end.to change(Company, :count).by(1)

        expect(contact.reload.company.domain).to eq('acme.com')
      end
    end

    context 'when the contact already has a company' do
      it 'preserves the existing company when the email changes' do
        existing_company = create(:company, domain: 'oldcompany.com', account: account)
        contact = create(:contact, email: 'john@oldcompany.com', company: existing_company, account: account)

        expect do
          contact.update(email: 'john@newcompany.com')
        end.not_to change(Company, :count)

        expect(contact.reload.company).to eq(existing_company)
      end

      it 'rolls contact activity up to the company' do
        company = create(:company, account: account)
        contact = create(:contact, account: account, company: company)

        contact.update!(last_activity_at: Time.zone.now)

        expect(company.reload.last_activity_at).to be_within(1.second).of(contact.last_activity_at)
      end
    end

    context 'when multiple contacts share a domain' do
      it 'associates all of them with the same company' do
        %w[john@acme.com jane@acme.com bob@acme.com].each do |email|
          create(:contact, email: email, account: account)
        end

        expect(Company.where(domain: 'acme.com', account: account).count).to eq(1)
        expect(Company.find_by(domain: 'acme.com', account: account).contacts.count).to eq(3)
      end
    end

    context 'when association fails' do
      it 'still saves the contact and logs the error' do
        allow(Contacts::CompanyAssociationService).to receive(:new).and_raise(StandardError, 'boom')

        expect { create(:contact, email: 'john@acme.com', account: account) }.not_to raise_error
      end
    end
  end

  describe '#push_event_data' do
    let(:account) { create(:account) }
    let(:company) { create(:company, account: account) }
    let(:contact) { create(:contact, account: account, company: company) }

    it 'includes company_id' do
      expect(contact.push_event_data[:company_id]).to eq(company.id)
    end
  end
end
