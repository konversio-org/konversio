require 'rails_helper'

RSpec.describe RegexHelper do
  describe 'WHATSAPP_BSUID_REGEX' do
    it 'accepts a country-scoped BSUID' do
      expect(described_class::WHATSAPP_BSUID_REGEX).to match('IN.2081978709342942')
    end

    it 'accepts a parent BSUID with the ENT infix' do
      expect(described_class::WHATSAPP_BSUID_REGEX).to match('US.ENT.AB12CD34')
    end

    it 'rejects a plain phone number' do
      expect(described_class::WHATSAPP_BSUID_REGEX).not_to match('919745786257')
    end

    it 'rejects a lowercase country prefix' do
      expect(described_class::WHATSAPP_BSUID_REGEX).not_to match('in.2081978709342942')
    end
  end

  describe 'WHATSAPP_CHANNEL_REGEX' do
    it 'accepts E.164 digits' do
      expect(described_class::WHATSAPP_CHANNEL_REGEX).to match('14155551234')
    end

    it 'accepts a BSUID' do
      expect(described_class::WHATSAPP_CHANNEL_REGEX).to match('IN.2081978709342942')
    end

    it 'rejects a value that is neither' do
      expect(described_class::WHATSAPP_CHANNEL_REGEX).not_to match('not-a-number')
    end
  end

  describe 'TWILIO_CHANNEL_WHATSAPP_REGEX' do
    it 'accepts a prefixed phone number' do
      expect(described_class::TWILIO_CHANNEL_WHATSAPP_REGEX).to match('whatsapp:+14155551234')
    end

    it 'accepts a prefixed BSUID' do
      expect(described_class::TWILIO_CHANNEL_WHATSAPP_REGEX).to match('whatsapp:IN.2081978709342942')
    end
  end

  describe 'WHATSAPP_WAMID_TOKEN_REGEX' do
    it 'extracts a 32-character hex token' do
      expect(described_class::WHATSAPP_WAMID_TOKEN_REGEX).to match('1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d')
    end

    it 'extracts a 20-character hex token' do
      expect(described_class::WHATSAPP_WAMID_TOKEN_REGEX).to match('1a2b3c4d5e6f7a8b9c0d')
    end

    it 'does not match a partial token embedded in longer hex' do
      expect(/\A#{described_class::WHATSAPP_WAMID_TOKEN_REGEX}\z/o).not_to match('f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d')
    end
  end
end
