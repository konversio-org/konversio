require 'rails_helper'

RSpec.describe AuditLog do
  include ActiveJob::TestHelper

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }

  before do
    described_class.delete_all
    clear_enqueued_jobs
  end

  def create_entry(**attrs)
    described_class.create!({ auditable: inbox, associated: account, action: 'update' }.merge(attrs))
  end

  describe 'scopes' do
    let(:user) { create(:user, account: account, name: 'Jane Agent', email: 'jane@example.com') }

    it 'filters by auditable type' do
      entry = create_entry
      create_entry(auditable: create(:team, account: account))

      expect(described_class.with_auditable_types(['Inbox'])).to contain_exactly(entry)
    end

    it 'filters by created-at window' do
      old_entry = create_entry(created_at: 3.days.ago)
      recent_entry = create_entry(created_at: 1.hour.ago)

      results = described_class.created_after(2.days.ago).created_before(Time.zone.now)
      expect(results).to contain_exactly(recent_entry)
      expect(results).not_to include(old_entry)
    end

    it 'matches the recorded username or the linked user name and email' do
      by_email = create_entry(user: user)
      create_entry

      expect(described_class.search_by_user('jane@exa')).to include(by_email)
      expect(described_class.search_by_user('jane agent')).to include(by_email)
      expect(described_class.search_by_user('nobody')).to be_empty
    end

    it 'treats LIKE metacharacters in the term literally' do
      literal = create_entry(user: create(:user, account: account, email: '100%_sure@example.com'))
      looks_like_a_pattern = create_entry(user: create(:user, account: account, email: '10023sure@example.com'))

      results = described_class.search_by_user('100%_')
      expect(results).to include(literal)
      expect(results).not_to include(looks_like_a_pattern)
    end
  end

  describe '#location' do
    it 'joins the city and country' do
      expect(described_class.new(city: 'Berlin', country: 'Germany').location).to eq('Berlin, Germany')
    end

    it 'drops blank parts without leaving a separator' do
      expect(described_class.new(country: 'Germany').location).to eq('Germany')
      expect(described_class.new(city: 'London', country: '').location).to eq('London')
      expect(described_class.new(city: '', country: '').location).to be_nil
    end
  end

  describe '#masked_remote_address' do
    it 'replaces the last octet of an IPv4 address' do
      expect(described_class.new(remote_address: '203.0.113.42').masked_remote_address).to eq('203.0.113.x')
    end

    it 'expands an IPv6 address and keeps only the first four hextets' do
      expect(described_class.new(remote_address: '2001:db8:85a3:8d3:1319:8a2e:370:7348').masked_remote_address)
        .to eq('2001:0db8:85a3:08d3::')
    end

    it 'does not leak host bits from a compressed IPv6 address' do
      masked = described_class.new(remote_address: '2001:db8::1').masked_remote_address
      expect(masked).to eq('2001:0db8:0000:0000::')
      expect(masked).not_to include('::1')
    end

    it 'returns nil for blank or unparseable addresses' do
      expect(described_class.new(remote_address: nil).masked_remote_address).to be_nil
      expect(described_class.new(remote_address: 'not-an-ip').masked_remote_address).to be_nil
    end
  end

  describe 'geolocation gating' do
    it 'enqueues a lookup after creation when the account has ip_lookup enabled' do
      account.enable_features!(:ip_lookup)

      expect { create_entry(remote_address: '8.8.8.8') }.to have_enqueued_job(AuditLogIpLookupJob)
    end

    it 'does not enqueue a lookup when the address is blank' do
      account.enable_features!(:ip_lookup)

      expect { create_entry }.not_to have_enqueued_job(AuditLogIpLookupJob)
    end

    it 'does not enqueue a lookup when the account has not enabled ip_lookup' do
      expect { create_entry(remote_address: '8.8.8.8') }.not_to have_enqueued_job(AuditLogIpLookupJob)
    end
  end

  describe '#resolve_ip_location!' do
    let(:geo_result) { Struct.new(:city, :country, :country_code).new('Berlin', 'Germany', 'DE') }
    let(:lookup) { instance_double(IpLookupService) }

    before { allow(IpLookupService).to receive(:new).and_return(lookup) }

    it 'writes the resolved location' do
      account.enable_features!(:ip_lookup)
      entry = create_entry(remote_address: '8.8.8.8')
      allow(lookup).to receive(:perform).with('8.8.8.8').and_return(geo_result)

      entry.resolve_ip_location!

      expect(entry.reload.city).to eq('Berlin')
      expect(entry.country).to eq('Germany')
      expect(entry.country_code).to eq('DE')
    end

    it 'does nothing when ip_lookup is disabled' do
      entry = create_entry(remote_address: '8.8.8.8')

      entry.resolve_ip_location!

      expect(IpLookupService).not_to have_received(:new)
      expect(entry.reload.city).to be_nil
    end
  end
end
