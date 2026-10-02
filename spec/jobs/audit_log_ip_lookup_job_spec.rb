require 'rails_helper'

RSpec.describe AuditLogIpLookupJob do
  let(:account) { create(:account).tap { |record| record.enable_features!(:ip_lookup) } }
  let(:inbox) { create(:inbox, account: account) }
  let(:audit) { AuditLog.create!(auditable: inbox, action: 'update', associated: account, remote_address: '8.8.8.8') }
  let(:geo) { Struct.new(:city, :country, :country_code).new('Berlin', 'Germany', 'DE') }
  let(:lookup) { instance_double(IpLookupService) }

  before { allow(IpLookupService).to receive(:new).and_return(lookup) }

  it 'writes the resolved location onto the entry' do
    allow(lookup).to receive(:perform).with('8.8.8.8').and_return(geo)

    described_class.perform_now(audit)

    expect(audit.reload.slice(:city, :country, :country_code).symbolize_keys)
      .to eq(city: 'Berlin', country: 'Germany', country_code: 'DE')
  end

  it 'is a no-op when the address is blank' do
    audit.update_columns(remote_address: nil) # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now(audit)

    expect(IpLookupService).not_to have_received(:new)
  end

  it 'leaves the entry untouched when the lookup returns nothing' do
    allow(lookup).to receive(:perform).and_return(nil)

    described_class.perform_now(audit)

    expect(audit.reload.city).to be_nil
  end

  it 'swallows lookup errors' do
    allow(lookup).to receive(:perform).and_raise(StandardError.new('boom'))

    expect { described_class.perform_now(audit) }.not_to raise_error
  end
end
