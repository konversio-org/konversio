# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Account do
  it { is_expected.to have_many(:users).through(:account_users) }
  it { is_expected.to have_many(:account_users) }
  it { is_expected.to have_many(:inboxes).dependent(:destroy_async) }
  it { is_expected.to have_many(:conversations).dependent(:destroy_async) }
  it { is_expected.to have_many(:contacts).dependent(:destroy_async) }
  it { is_expected.to have_many(:canned_responses).dependent(:destroy_async) }
  it { is_expected.to have_many(:facebook_pages).class_name('::Channel::FacebookPage').dependent(:destroy_async) }
  it { is_expected.to have_many(:web_widgets).class_name('::Channel::WebWidget').dependent(:destroy_async) }
  it { is_expected.to have_many(:webhooks).dependent(:destroy_async) }
  it { is_expected.to have_many(:notification_settings).dependent(:destroy_async) }
  it { is_expected.to have_many(:reporting_events) }
  it { is_expected.to have_many(:portals).dependent(:destroy_async) }
  it { is_expected.to have_many(:categories).dependent(:destroy_async) }
  it { is_expected.to have_many(:teams).dependent(:destroy_async) }

  # This validation happens in ApplicationRecord
  describe 'length validations' do
    let(:account) { create(:account) }

    it 'validates name presence' do
      account.name = ''
      account.valid?
      expect(account.errors[:name]).to include("can't be blank")
    end

    it 'validates name length' do
      account.name = 'a' * 256
      account.valid?
      expect(account.errors[:name]).to include('is too long (maximum is 255 characters)')
    end

    it 'validates domain length' do
      account.domain = 'a' * 150
      account.valid?
      expect(account.errors[:domain]).to include('is too long (maximum is 100 characters)')
    end
  end

  describe 'usage_limits' do
    let(:account) { create(:account) }

    it 'returns KonversioApp.max limits' do
      expect(account.usage_limits[:agents]).to eq(KonversioApp.max_limit)
      expect(account.usage_limits[:inboxes]).to eq(KonversioApp.max_limit)
    end
  end

  describe 'inbound_email_domain' do
    let(:account) { create(:account) }

    it 'returns the domain from inbox if inbox value is present' do
      account.update(domain: 'test.com')
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test2.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end

    it 'returns the domain from ENV if inbox value is nil' do
      account.update(domain: nil)
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end

    it 'returns the domain from ENV if inbox value is empty string' do
      account.update(domain: '')
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end
  end

  describe 'support_email' do
    let(:account) { create(:account) }

    it 'returns the support email from inbox if inbox value is present' do
      account.update(support_email: 'support@chatwoot.com')
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('support@chatwoot.com')
      end
    end

    it 'returns the support email from ENV if inbox value is nil' do
      account.update(support_email: nil)
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('hello@chatwoot.com')
      end
    end

    it 'returns the support email from ENV if inbox value is empty string' do
      account.update(support_email: '')
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('hello@chatwoot.com')
      end
    end
  end

  context 'when after_destroy is called' do
    it 'conv_dpid_seq and camp_dpid_seq_ are deleted' do
      account = create(:account)
      query = "select * from information_schema.sequences where sequence_name in  ('camp_dpid_seq_#{account.id}', 'conv_dpid_seq_#{account.id}');"
      expect(ActiveRecord::Base.connection.execute(query).count).to eq(2)
      expect(account.locale).to eq('en')
      account.destroy
      expect(ActiveRecord::Base.connection.execute(query).count).to eq(0)
    end
  end

  describe 'locale' do
    it 'returns correct language if the value is set' do
      account = create(:account, locale: 'fr')
      expect(account.locale).to eq('fr')
      expect(account.locale_english_name).to eq('french')
    end

    it 'returns english if the value is not set' do
      account = create(:account, locale: nil)
      expect(account.locale).to be_nil
      expect(account.locale_english_name).to eq('english')
    end

    it 'returns english if the value is empty string' do
      account = create(:account, locale: '')
      expect(account.locale).to be_nil
      expect(account.locale_english_name).to eq('english')
    end

    it 'returns correct language if the value has country code' do
      account = create(:account, locale: 'pt_BR')
      expect(account.locale).to eq('pt_BR')
      expect(account.locale_english_name).to eq('portuguese')
    end
  end

  describe 'settings' do
    let(:account) { create(:account) }

    context 'when auto_resolve_after' do
      it 'validates minimum value' do
        account.settings = { auto_resolve_after: 4 }
        expect(account).to be_invalid
        expect(account.errors.messages).to eq({ auto_resolve_after: ['must be greater than or equal to 10'] })
      end

      it 'validates maximum value' do
        account.settings = { auto_resolve_after: 1_439_857 }
        expect(account).to be_invalid
        expect(account.errors.messages).to eq({ auto_resolve_after: ['must be less than or equal to 1439856'] })
      end

      it 'allows valid values' do
        account.settings = { auto_resolve_after: 15 }
        expect(account).to be_valid

        account.settings = { auto_resolve_after: 1_439_856 }
        expect(account).to be_valid
      end

      it 'allows null values' do
        account.settings = { auto_resolve_after: nil }
        expect(account).to be_valid
      end
    end

    context 'when auto_resolve_message' do
      it 'allows string values' do
        account.settings = { auto_resolve_message: 'This conversation has been resolved automatically.' }
        expect(account).to be_valid
      end

      it 'allows empty string' do
        account.settings = { auto_resolve_message: '' }
        expect(account).to be_valid
      end

      it 'allows nil values' do
        account.settings = { auto_resolve_message: nil }
        expect(account).to be_valid
      end
    end

    context 'when using store_accessor' do
      it 'correctly gets and sets auto_resolve_after' do
        account.auto_resolve_after = 30
        expect(account.auto_resolve_after).to eq(30)
        expect(account.settings['auto_resolve_after']).to eq(30)
      end

      it 'correctly gets and sets auto_resolve_message' do
        message = 'This conversation was automatically resolved'
        account.auto_resolve_message = message
        expect(account.auto_resolve_message).to eq(message)
        expect(account.settings['auto_resolve_message']).to eq(message)
      end

      it 'defaults pilot_auto_resolve_mode to legacy' do
        expect(account.pilot_auto_resolve_mode).to eq('legacy')
        expect(account).to be_pilot_auto_resolve_legacy
      end

      it 'treats the removed evaluated mode as legacy' do
        account.settings = { 'pilot_auto_resolve_mode' => 'evaluated' }

        expect(account.pilot_auto_resolve_mode).to eq('legacy')
        expect(account).to be_pilot_auto_resolve_legacy
      end

      it 'correctly gets and sets pilot_auto_resolve_mode' do
        account.pilot_auto_resolve_mode = 'legacy'

        expect(account.pilot_auto_resolve_mode).to eq('legacy')
        expect(account.settings['pilot_auto_resolve_mode']).to eq('legacy')
        expect(account).to be_pilot_auto_resolve_legacy
      end

      it 'allows clearing pilot_auto_resolve_mode to fall back to feature defaults' do
        account.pilot_auto_resolve_mode = nil

        expect(account).to be_valid
        expect(account.pilot_auto_resolve_mode).to eq('legacy')
        expect(account.settings['pilot_auto_resolve_mode']).to be_nil
      end

      it 'falls back to disabled mode from legacy settings key' do
        account.settings = { 'pilot_disable_auto_resolve' => true }

        expect(account.pilot_auto_resolve_mode).to eq('disabled')
        expect(account).to be_pilot_auto_resolve_disabled
      end

      it 'handles nil values correctly' do
        account.auto_resolve_after = nil
        account.auto_resolve_message = nil
        expect(account.auto_resolve_after).to be_nil
        expect(account.auto_resolve_message).to be_nil
      end
    end

    context 'when using with_auto_resolve scope' do
      it 'finds accounts with auto_resolve_after set' do
        account.update(auto_resolve_after: 40 * 24 * 60)
        expect(described_class.with_auto_resolve.pluck(:id)).to include(account.id)
      end

      it 'does not find accounts without auto_resolve_after' do
        account.update(auto_resolve_after: nil)
        expect(described_class.with_auto_resolve.pluck(:id)).not_to include(account.id)
      end
    end

    context 'when support_email is set' do
      it 'allows a plain email address' do
        account.support_email = 'support@example.com'
        expect(account).to be_valid
      end

      it 'allows display-name format' do
        account.support_email = 'Support Team <support@example.com>'
        expect(account).to be_valid
      end

      it 'allows blank values' do
        account.support_email = ''
        expect(account).to be_valid
      end

      it 'rejects malformed strings with no email part' do
        account.support_email = 'Smith Smith'
        expect(account).not_to be_valid
        expect(account.errors[:support_email]).to include(I18n.t('errors.account.support_email.invalid'))
      end
    end

    context 'when reporting_timezone is set' do
      it 'allows valid timezone names' do
        account.reporting_timezone = 'America/New_York'

        expect(account).to be_valid
      end

      it 'rejects invalid timezone names' do
        account.reporting_timezone = 'Invalid/Timezone'

        expect(account).not_to be_valid
        expect(account.errors[:reporting_timezone]).to include(I18n.t('errors.account.reporting_timezone.invalid'))
      end
    end
  end

  describe 'pilot_preferences' do
    let(:account) { create(:account) }

    describe 'with no saved preferences' do
      it 'returns defaults from llm.yml' do
        prefs = account.pilot_preferences

        expect(prefs[:features].values).to all(be false)

        Llm::Models.feature_keys.each do |feature|
          expect(prefs[:models][feature]).to eq(Llm::Models.default_model_for(feature))
        end
      end
    end

    describe 'with saved model preferences' do
      it 'returns saved preferences merged with defaults' do
        account.update!(pilot_models: { 'editor' => 'gpt-4.1-mini', 'assistant' => 'gpt-5.2' })

        prefs = account.pilot_preferences

        expect(prefs[:models]['editor']).to eq('gpt-4.1-mini')
        expect(prefs[:models]['assistant']).to eq('gpt-5.2')
        expect(prefs[:models]['copilot']).to eq(Llm::Models.default_model_for('copilot'))
      end
    end

    describe 'with saved feature preferences' do
      it 'returns saved feature states' do
        account.update!(pilot_features: { 'editor' => true, 'assistant' => true })

        prefs = account.pilot_preferences

        expect(prefs[:features]['editor']).to be true
        expect(prefs[:features]['assistant']).to be true
        expect(prefs[:features]['copilot']).to be false
      end
    end

    describe 'validation' do
      it 'rejects invalid model for a feature' do
        account.pilot_models = { 'label_suggestion' => 'gpt-5.1' }

        expect(account).not_to be_valid
        expect(account.errors[:pilot_models].first).to include('not a valid model for label_suggestion')
      end

      it 'accepts valid model for a feature' do
        account.pilot_models = { 'editor' => 'gpt-4.1-mini', 'label_suggestion' => 'gpt-4.1-nano' }

        expect(account).to be_valid
      end
    end
  end

  describe 'Featurable concern (Unified JSONB Feature Flags)' do
    let(:account) { create(:account) }

    describe 'default values' do
      it 'defaults pilot features to true' do
        expect(account.feature_enabled?('pilot')).to be true
        expect(account.feature_enabled?('pilot_briefing')).to be true
        expect(account.pilot_enabled).to be true
        expect(account.pilot_briefing_enabled).to be true
      end

      it 'returns false for non-existent or default-false keys' do
        expect(account.feature_enabled?('non_existent_feature_flag')).to be false
      end
    end

    describe 'getters and setters' do
      it 'allows setting and getting individual features dynamically' do
        account.feature_pilot = false
        expect(account.feature_pilot).to be false
        expect(account.feature_pilot?).to be false
        expect(account.pilot_enabled).to be false
        expect(account.pilot_enabled?).to be false

        account.feature_pilot = true
        expect(account.feature_pilot).to be true
        expect(account.feature_pilot?).to be true
        expect(account.pilot_enabled).to be true
      end

      it 'casts stringy or boolean-ish values to true/false correctly' do
        account.feature_pilot = '0'
        expect(account.feature_pilot).to be false

        account.feature_pilot = '1'
        expect(account.feature_pilot).to be true

        account.feature_pilot = 'false'
        expect(account.feature_pilot).to be false

        account.feature_pilot = 'true'
        expect(account.feature_pilot).to be true
      end
    end

    describe 'bulk enabling and disabling' do
      it 'enables and disables features in bulk' do
        account.disable_features('pilot', 'pilot_briefing')
        expect(account.pilot_enabled).to be false
        expect(account.pilot_briefing_enabled).to be false

        account.enable_features('pilot', 'pilot_briefing')
        expect(account.pilot_enabled).to be true
        expect(account.pilot_briefing_enabled).to be true
      end

      it 'saves state to database on bang methods' do
        account.disable_features!('pilot')
        expect(account.reload.pilot_enabled).to be false

        account.enable_features!('pilot')
        expect(account.reload.pilot_enabled).to be true
      end
    end

    describe 'selected_feature_flags checkbox plumbing' do
      it 'returns active features list as symbols' do
        expect(account.selected_feature_flags).to include(:pilot, :pilot_briefing)
      end

      it 'correctly handles unchecked checkbox states via sentinel' do
        account.selected_feature_flags = ['__sentinel__']
        expect(account.feature_flags.values).to all(be false)
        expect(account.pilot_enabled).to be false
        expect(account.pilot_briefing_enabled).to be false
      end

      it 'overrides active features based on checkboxes' do
        account.selected_feature_flags = %w[pilot pilot_briefing]
        expect(account.pilot_enabled).to be true
        expect(account.pilot_briefing_enabled).to be true
        expect(account.feature_enabled?('pilot_copilot')).to be false
      end
    end

    describe 'database dynamic scopes' do
      before do
        account.update!(feature_flags: { 'pilot' => false, 'pilot_briefing' => true })
      end

      it 'filters by negative default-true scope (pilot=false)' do
        expect(described_class.not_feature_pilot).to include(account)
        expect(described_class.feature_pilot).not_to include(account)
      end

      it 'filters by positive default-true scope (pilot_briefing=true)' do
        expect(described_class.feature_pilot_briefing).to include(account)
        expect(described_class.not_feature_pilot_briefing).not_to include(account)
      end
    end
  end
end
