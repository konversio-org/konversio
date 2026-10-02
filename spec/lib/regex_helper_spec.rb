require 'rails_helper'

RSpec.describe RegexHelper do
  describe 'WHATSAPP_BSUID_REGEX' do
    it 'accepts a country-scoped BSUID' do
      expect('IN.2081978709342942').to match(described_class::WHATSAPP_BSUID_REGEX)
    end

    it 'accepts a parent BSUID with the ENT infix' do
      expect('US.ENT.AB12CD34').to match(described_class::WHATSAPP_BSUID_REGEX)
    end

    it 'rejects a plain phone number' do
      expect('919745786257').not_to match(described_class::WHATSAPP_BSUID_REGEX)
    end

    it 'rejects a lowercase country prefix' do
      expect('in.2081978709342942').not_to match(described_class::WHATSAPP_BSUID_REGEX)
    end
  end

  describe 'WHATSAPP_CHANNEL_REGEX' do
    it 'accepts E.164 digits' do
      expect('14155551234').to match(described_class::WHATSAPP_CHANNEL_REGEX)
    end

    it 'accepts a BSUID' do
      expect('IN.2081978709342942').to match(described_class::WHATSAPP_CHANNEL_REGEX)
    end

    it 'rejects a value that is neither' do
      expect('not-a-number').not_to match(described_class::WHATSAPP_CHANNEL_REGEX)
    end
  end

  describe 'TWILIO_CHANNEL_WHATSAPP_REGEX' do
    it 'accepts a prefixed phone number' do
      expect('whatsapp:+14155551234').to match(described_class::TWILIO_CHANNEL_WHATSAPP_REGEX)
    end

    it 'accepts a prefixed BSUID' do
      expect('whatsapp:IN.2081978709342942').to match(described_class::TWILIO_CHANNEL_WHATSAPP_REGEX)
    end
  end

  describe 'WHATSAPP_WAMID_TOKEN_REGEX' do
    it 'extracts a 32-character hex token' do
      expect('1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d').to match(described_class::WHATSAPP_WAMID_TOKEN_REGEX)
    end

    it 'extracts a 20-character hex token' do
      expect('1a2b3c4d5e6f7a8b9c0d').to match(described_class::WHATSAPP_WAMID_TOKEN_REGEX)
    end

    it 'does not match a partial token embedded in longer hex' do
      expect('f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d').not_to match(/\A#{described_class::WHATSAPP_WAMID_TOKEN_REGEX}\z/o)
    end
  end
end
