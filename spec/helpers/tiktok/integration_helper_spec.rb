require 'rails_helper'

RSpec.describe Tiktok::IntegrationHelper do
  include described_class

  let(:account_id) { 1 }
  let(:client_secret) { 'test_secret' }

  before do
    allow(GlobalConfigService).to receive(:load).with('TIKTOK_APP_SECRET', nil).and_return(client_secret)
  end

  describe '#generate_tiktok_token' do
    it 'encodes the account id and no return hint by default' do
      token = generate_tiktok_token(account_id)
      decoded = JWT.decode(token, client_secret, true, algorithm: 'HS256').first

      expect(decoded['sub']).to eq(account_id)
      expect(decoded).not_to have_key('return_to')
    end

    it 'encodes the onboarding return hint when present' do
      token = generate_tiktok_token(account_id, 'onboarding')

      expect(verify_tiktok_token(token)).to eq(account_id)
      expect(tiktok_token_return_to(token)).to eq('onboarding')
    end

    it 'omits the hint when absent' do
      token = generate_tiktok_token(account_id)

      expect(tiktok_token_return_to(token)).to be_nil
    end
  end

  describe '#verify_tiktok_token' do
    it 'returns the account id from a valid token' do
      token = JWT.encode({ sub: account_id, iat: Time.current.to_i }, client_secret, 'HS256')

      expect(verify_tiktok_token(token)).to eq(account_id)
    end

    it 'returns nil for an invalid token' do
      expect(verify_tiktok_token('invalid')).to be_nil
    end
  end
end
