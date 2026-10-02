require 'rails_helper'

RSpec.describe Imap::Authentication do
  describe '.validate_user_configurable!' do
    it 'returns the default mechanism when none is given' do
      expect(described_class.validate_user_configurable!(nil)).to eq('plain')
      expect(described_class.validate_user_configurable!('')).to eq('plain')
    end

    it 'accepts the supported mechanisms' do
      expect(described_class.validate_user_configurable!('plain')).to eq('plain')
      expect(described_class.validate_user_configurable!('login')).to eq('login')
      expect(described_class.validate_user_configurable!('cram-md5')).to eq('cram-md5')
    end

    it 'rejects unsupported mechanisms' do
      expect { described_class.validate_user_configurable!('oauth2') }
        .to raise_error(StandardError, /Invalid IMAP authentication mechanism/)
    end
  end

  describe '.authenticate!' do
    let(:imap) { instance_double(Net::IMAP) }

    it 'uses the IMAP LOGIN command for the login mechanism' do
      allow(imap).to receive(:login)

      described_class.authenticate!(imap, 'login', 'user', 'pass')

      expect(imap).to have_received(:login).with('user', 'pass')
    end

    it 'uses CRAM-MD5 for the cram-md5 mechanism' do
      allow(imap).to receive(:authenticate)

      described_class.authenticate!(imap, 'cram-md5', 'user', 'pass')

      expect(imap).to have_received(:authenticate).with('CRAM-MD5', 'user', 'pass')
    end

    it 'uses the given SASL mechanism otherwise' do
      allow(imap).to receive(:authenticate)

      described_class.authenticate!(imap, 'plain', 'user', 'pass')

      expect(imap).to have_received(:authenticate).with('plain', 'user', 'pass')
    end
  end
end
