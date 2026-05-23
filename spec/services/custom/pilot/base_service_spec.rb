require 'rails_helper'

RSpec.describe Custom::Pilot::BaseService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#logbook_context_for' do
    context 'when the logbook feature flag is off' do
      it 'returns nil even if entries exist' do
        account.enable_features!(:pilot)
        account.disable_features!(:pilot_logbook)
        create(:pilot_logbook_entry, contact: contact, account: account, content: 'Prefers email')

        expect(service.logbook_context_for(contact)).to be_nil
      end
    end

    context 'when the contact is blank' do
      it 'returns nil' do
        account.enable_features!(:pilot, :pilot_logbook)

        expect(service.logbook_context_for(nil)).to be_nil
      end
    end

    context 'when the feature is on but the contact has zero entries' do
      it 'returns nil so no system message is added to the prompt' do
        account.enable_features!(:pilot, :pilot_logbook)

        expect(service.logbook_context_for(contact)).to be_nil
      end
    end

    context 'when the contact has entries' do
      before { account.enable_features!(:pilot, :pilot_logbook) }

      it 'renders a fixed header followed by a bulleted list of contents' do
        travel_to(2.days.ago) { create(:pilot_logbook_entry, contact: contact, account: account, content: 'Prefers email') }
        travel_to(1.day.ago)  { create(:pilot_logbook_entry, contact: contact, account: account, content: 'Has corporate account') }

        expect(service.logbook_context_for(contact)).to eq(
          "Known facts about this contact:\n- Has corporate account\n- Prefers email"
        )
      end

      it 'lists entries in reverse-chronological order (newest first)' do
        older = travel_to(3.days.ago) { create(:pilot_logbook_entry, contact: contact, account: account, content: 'Older fact') }
        newer = travel_to(1.day.ago)  { create(:pilot_logbook_entry, contact: contact, account: account, content: 'Newer fact') }

        rendered = service.logbook_context_for(contact)
        expect(rendered.index('Newer fact')).to be < rendered.index('Older fact')
        expect(newer.created_at).to be > older.created_at
      end

      it 'omits entry ids, source-message ids and timestamps from the rendered text' do
        entry = create(:pilot_logbook_entry, contact: contact, account: account, content: 'Lives in Amsterdam')

        rendered = service.logbook_context_for(contact)

        expect(rendered).not_to include(entry.id.to_s)
        expect(rendered).not_to match(/\d{4}-\d{2}-\d{2}/) # no ISO dates
        expect(rendered).not_to include(entry.created_at.to_s)
        expect(rendered).to eq("Known facts about this contact:\n- Lives in Amsterdam")
      end
    end
  end
end
