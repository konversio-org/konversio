require 'rails_helper'

RSpec.describe AuditLogIpLocationBackfillJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account).tap { |record| record.enable_features!(:ip_lookup) } }
  let(:inbox) { create(:inbox, account: account) }
  let(:lookup) { instance_double(IpLookupService, perform: nil) }

  before { allow(IpLookupService).to receive(:new).and_return(lookup) }

  def create_entry(**attrs)
    AuditLog.create!(auditable: inbox, action: 'update', associated: account, **attrs)
  end

  it 'bounds each batch to the configured size' do
    expect(described_class.send(:new).send(:pending_audits, 0).limit_value).to eq(described_class::BATCH_SIZE)
  end

  it 'reschedules itself from the last processed id' do
    create_entry(remote_address: '1.1.1.1')
    last = create_entry(remote_address: '2.2.2.2')
    clear_enqueued_jobs

    described_class.perform_now(0)

    expect(described_class).to have_been_enqueued.with(last.id)
  end

  it 'keeps the chain going when a row fails to resolve' do
    create_entry(remote_address: '1.1.1.1')
    last = create_entry(remote_address: '2.2.2.2')
    allow(lookup).to receive(:perform).with('1.1.1.1').and_raise(StandardError.new('boom'))
    clear_enqueued_jobs

    described_class.perform_now(0)

    expect(described_class).to have_been_enqueued.with(last.id)
  end

  it 'skips entries whose account has not enabled ip_lookup' do
    opted_out = create(:account)
    AuditLog.create!(auditable: create(:inbox, account: opted_out), action: 'update',
                     associated: opted_out, remote_address: '3.3.3.3')
    clear_enqueued_jobs

    described_class.perform_now(0)

    expect(described_class).not_to have_been_enqueued
  end

  it 'stops when no rows remain' do
    create_entry(remote_address: '1.1.1.1')
    clear_enqueued_jobs

    described_class.perform_now(AuditLog.maximum(:id))

    expect(described_class).not_to have_been_enqueued
  end
end
