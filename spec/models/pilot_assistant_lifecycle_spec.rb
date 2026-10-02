# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PilotAssistantLifecycle do
  let(:account) { create(:account) }

  describe 'auto-resolve mode' do
    it 'inherits the account mode when unset' do
      account.update!(settings: { pilot_auto_resolve_mode: 'legacy' })
      assistant = build(:pilot_assistant, account: account, config: {})

      expect(assistant.auto_resolve_mode).to eq('legacy')
    end

    it 'is stamped with the account value at creation' do
      account.update!(settings: { pilot_auto_resolve_mode: 'disabled' })
      assistant = create(:pilot_assistant, account: account, config: {})

      expect(assistant.reload.config['auto_resolve_mode']).to eq('disabled')
    end

    it 'prefers the assistant value over the account value' do
      account.update!(settings: { pilot_auto_resolve_mode: 'legacy' })
      assistant = create(:pilot_assistant, account: account, config: { 'auto_resolve_mode' => 'evaluated' })

      expect(assistant.auto_resolve_mode).to eq('evaluated')
    end

    it 'rejects an unknown mode' do
      assistant = build(:pilot_assistant, account: account, config: { 'auto_resolve_mode' => 'sometimes' })

      expect(assistant).not_to be_valid
      expect(assistant.errors[:auto_resolve_mode]).to be_present
    end
  end

  describe 'inactivity threshold' do
    it 'defaults to 60 minutes when unset' do
      assistant = build(:pilot_assistant, account: account, config: {})

      expect(assistant.inactivity_threshold_minutes).to eq(60)
    end

    it 'falls back to the installation-level override when unset' do
      with_modified_env PILOT_AUTORESOLVE_IDLE_MINUTES: '90' do
        assistant = build(:pilot_assistant, account: account, config: {})

        expect(assistant.inactivity_threshold_minutes).to eq(90)
      end
    end

    it 'prefers the assistant value over the installation override' do
      with_modified_env PILOT_AUTORESOLVE_IDLE_MINUTES: '90' do
        assistant = build(:pilot_assistant, account: account, config: { 'auto_resolve_after' => 30 })

        expect(assistant.inactivity_threshold_minutes).to eq(30)
      end
    end

    it 'normalizes to the nearest five-minute step on save' do
      assistant = create(:pilot_assistant, account: account, config: { 'auto_resolve_after' => 47 })

      expect(assistant.reload.config['auto_resolve_after']).to eq(45)
    end

    it 'rejects values below the minimum' do
      assistant = build(:pilot_assistant, account: account, config: { 'auto_resolve_after' => 3 })

      expect(assistant).not_to be_valid
      expect(assistant.errors[:auto_resolve_after]).to be_present
    end

    it 'rejects values above 24 hours' do
      assistant = build(:pilot_assistant, account: account, config: { 'auto_resolve_after' => 1445 })

      expect(assistant).not_to be_valid
      expect(assistant.errors[:auto_resolve_after]).to be_present
    end

    it 'accepts the boundary values' do
      expect(build(:pilot_assistant, account: account, config: { 'auto_resolve_after' => 5 })).to be_valid
      expect(build(:pilot_assistant, account: account, config: { 'auto_resolve_after' => 1440 })).to be_valid
    end
  end

  describe 'response window' do
    it 'allows blank and the three supported values' do
      expect(build(:pilot_assistant, account: account, config: {})).to be_valid
      %w[always business_hours outside_business_hours].each do |window|
        expect(build(:pilot_assistant, account: account, config: { 'response_window' => window })).to be_valid
      end
    end

    it 'rejects an unrecognized value' do
      assistant = build(:pilot_assistant, account: account, config: { 'response_window' => 'weekends' })

      expect(assistant).not_to be_valid
      expect(assistant.errors[:response_window]).to be_present
    end
  end

  describe 'resolution message toggle' do
    it 'defaults to true' do
      expect(build(:pilot_assistant, account: account, config: {}).send_inactivity_resolution_message).to be(true)
    end

    it 'rejects a non-boolean value' do
      assistant = build(:pilot_assistant, account: account, config: { 'send_inactivity_resolution_message' => 'maybe' })

      expect(assistant).not_to be_valid
      expect(assistant.errors[:config]).to be_present
    end
  end

  describe '#engages?' do
    let(:contact) { create(:contact, account: account, email: 'vip@example.com') }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { build(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'engages everyone when no audience and no window are configured' do
      assistant = build(:pilot_assistant, account: account, config: {})

      expect(assistant.engages?(contact, conversation)).to be(true)
    end

    it 'does not engage when the audience does not match' do
      assistant = build(:pilot_assistant, account: account, config: {
                          'audience' => {
                            'combinator' => 'and',
                            'conditions' => [{ 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['@other.com'] }]
                          }
                        })

      expect(assistant.engages?(contact, conversation)).to be(false)
    end

    it 'engages when the audience matches and the window is open' do
      assistant = build(:pilot_assistant, account: account, config: {
                          'audience' => {
                            'combinator' => 'and',
                            'conditions' => [{ 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['@example.com'] }]
                          }
                        })

      expect(assistant.engages?(contact, conversation)).to be(true)
    end
  end

  describe '#response_window_available?' do
    let(:inbox) { create(:inbox, account: account, working_hours_enabled: true) }

    it 'passes for blank and always windows regardless of hours' do
      allow(inbox).to receive(:out_of_office?).and_return(true)

      expect(build(:pilot_assistant, account: account, config: {}).response_window_available?(inbox)).to be(true)
      expect(
        build(:pilot_assistant, account: account, config: { 'response_window' => 'always' }).response_window_available?(inbox)
      ).to be(true)
    end

    it 'business-hours window passes inside working hours and fails outside' do
      assistant = build(:pilot_assistant, account: account, config: { 'response_window' => 'business_hours' })

      allow(inbox).to receive(:out_of_office?).and_return(false)
      expect(assistant.response_window_available?(inbox)).to be(true)

      allow(inbox).to receive(:out_of_office?).and_return(true)
      expect(assistant.response_window_available?(inbox)).to be(false)
    end

    it 'outside-hours window passes outside working hours and fails inside' do
      assistant = build(:pilot_assistant, account: account, config: { 'response_window' => 'outside_business_hours' })

      allow(inbox).to receive(:out_of_office?).and_return(true)
      expect(assistant.response_window_available?(inbox)).to be(true)

      allow(inbox).to receive(:out_of_office?).and_return(false)
      expect(assistant.response_window_available?(inbox)).to be(false)
    end

    it 'passes for any window when the inbox has no working hours configured' do
      inbox.update!(working_hours_enabled: false)
      assistant = build(:pilot_assistant, account: account, config: { 'response_window' => 'business_hours' })

      expect(assistant.response_window_available?(inbox)).to be(true)
    end
  end
end
