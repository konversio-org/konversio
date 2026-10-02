# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Company, type: :model do
  context 'with validations' do
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:description).is_at_most(1000) }

    describe 'domain validation' do
      it { is_expected.to allow_value('example.com').for(:domain) }
      it { is_expected.to allow_value('sub.example.com').for(:domain) }
      it { is_expected.to allow_value('').for(:domain) }
      it { is_expected.to allow_value(nil).for(:domain) }
      it { is_expected.not_to allow_value('invalid-domain').for(:domain) }
      it { is_expected.not_to allow_value('.example.com').for(:domain) }
      it { is_expected.not_to allow_value('https://example.com').for(:domain) }
      it { is_expected.not_to allow_value('example com').for(:domain) }
    end

    describe 'domain uniqueness per account' do
      let(:account) { create(:account) }

      it 'rejects a duplicate domain in the same account' do
        create(:company, account: account, domain: 'acme.com')
        duplicate = build(:company, account: account, domain: 'acme.com')

        expect(duplicate).not_to be_valid
      end

      it 'allows the same domain in another account' do
        create(:company, account: account, domain: 'acme.com')
        other = build(:company, account: create(:account), domain: 'acme.com')

        expect(other).to be_valid
      end
    end

    describe 'attribute bags' do
      it 'defaults to empty maps when not supplied' do
        company = create(:company)

        expect(company.additional_attributes).to eq({})
        expect(company.custom_attributes).to eq({})
      end
    end
  end

  context 'with associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:contacts).dependent(:nullify) }
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let!(:company_b) { create(:company, name: 'B Company', account: account) }
    let!(:company_a) { create(:company, name: 'A Company', account: account) }
    let!(:company_c) { create(:company, name: 'C Company', account: account) }

    describe '.ordered_by_name' do
      it 'orders companies by name alphabetically' do
        companies = described_class.where(account: account).ordered_by_name
        expect(companies.map(&:name)).to eq([company_a.name, company_b.name, company_c.name])
      end
    end

    describe '.search_by_name_or_domain' do
      it 'matches case-insensitively on partial name or domain' do
        expect(described_class.search_by_name_or_domain('a company').pluck(:id)).to eq([company_a.id])
        expect(described_class.search_by_name_or_domain('COMPANY').pluck(:id)).to contain_exactly(company_a.id, company_b.id, company_c.id)
      end
    end
  end

  describe '#record_activity_at!' do
    it 'does not move company activity backwards' do
      company = create(:company, last_activity_at: Time.zone.now)
      original_activity_at = company.last_activity_at

      company.record_activity_at!(1.hour.ago)

      expect(company.reload.last_activity_at).to be_within(1.second).of(original_activity_at)
    end

    it 'throttles writes inside the rollup window' do
      company = create(:company, last_activity_at: 1.minute.ago)
      original_activity_at = company.last_activity_at

      expect { company.record_activity_at!(Time.zone.now) }.not_to(change { company.reload.updated_at })
      expect(company.reload.last_activity_at).to be_within(1.second).of(original_activity_at)
    end

    it 'advances activity outside the rollup window' do
      company = create(:company, last_activity_at: 1.hour.ago)

      company.record_activity_at!(Time.zone.now)

      expect(company.reload.last_activity_at).to be_within(1.second).of(Time.zone.now)
    end
  end

  describe 'contact company name sync' do
    let(:account) { create(:account) }
    let(:company) { create(:company, account: account, name: 'Acme') }

    it 'enqueues contact company name sync when the company name changes' do
      expect do
        company.update!(name: 'Acme Labs')
      end.to have_enqueued_job(Companies::SyncContactNamesJob).with(company_id: company.id)
    end
  end
end
