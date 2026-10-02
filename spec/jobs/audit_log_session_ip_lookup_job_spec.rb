require 'rails_helper'

RSpec.describe AuditLogSessionIpLookupJob do
  let(:account) { create(:account).tap { |record| record.enable_features!(:ip_lookup) } }
  let(:other_account) { create(:account).tap { |record| record.enable_features!(:ip_lookup) } }
  let(:user) { create(:user, account: account) }
  let(:geo) { Struct.new(:city, :country, :country_code).new('Berlin', 'Germany', 'DE') }
  let(:lookup) { instance_double(IpLookupService) }

  before { allow(IpLookupService).to receive(:new).and_return(lookup) }

  def create_session_entry(account)
    AuditLog.create!(
      auditable: user, action: 'sign_in', associated: account,
      user: user, remote_address: '8.8.8.8', request_uuid: SecureRandom.uuid
    )
  end

  it 'resolves the address once and applies it to the whole batch' do
    entries = [create_session_entry(account), create_session_entry(other_account)]
    allow(lookup).to receive(:perform).with('8.8.8.8').and_return(geo)

    described_class.perform_now(entries.map(&:id), '8.8.8.8')

    expect(lookup).to have_received(:perform).once
    entries.each do |entry|
      expect(entry.reload.slice(:city, :country, :country_code).symbolize_keys)
        .to eq(city: 'Berlin', country: 'Germany', country_code: 'DE')
    end
  end

  it 'leaves entries outside the batch untouched' do
    entry = create_session_entry(account)
    untouched = create_session_entry(account)
    allow(lookup).to receive(:perform).and_return(geo)

    described_class.perform_now([entry.id], '8.8.8.8')

    expect(untouched.reload.city).to be_nil
  end

  it 'updates only entries whose account has ip_lookup enabled' do
    eligible = create_session_entry(account)
    ineligible = create_session_entry(create(:account))
    allow(lookup).to receive(:perform).and_return(geo)

    described_class.perform_now([eligible.id, ineligible.id], '8.8.8.8')

    expect(eligible.reload.city).to eq('Berlin')
    expect(ineligible.reload.city).to be_nil
  end

  it 'does no work when no account in the batch has ip_lookup enabled' do
    entry = create_session_entry(create(:account))

    described_class.perform_now([entry.id], '8.8.8.8')

    expect(IpLookupService).not_to have_received(:new)
  end

  it 'does no work for an empty batch or blank address' do
    described_class.perform_now([], '8.8.8.8')
    described_class.perform_now([1], '')

    expect(IpLookupService).not_to have_received(:new)
  end

  it 'swallows lookup errors' do
    entry = create_session_entry(account)
    allow(lookup).to receive(:perform).and_raise(StandardError.new('boom'))

    expect { described_class.perform_now([entry.id], '8.8.8.8') }.not_to raise_error
  end
end
