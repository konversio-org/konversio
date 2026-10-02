require 'rails_helper'

RSpec.describe Rack::Attack do
  def discriminator(throttle_name, env)
    throttle = described_class.throttles.fetch(throttle_name) { raise "throttle #{throttle_name} is not defined" }
    throttle.block.call(Rack::Attack::Request.new(env))
  end

  def env_for(path, method: :get, remote_addr: '1.2.3.4', params: nil, headers: {})
    env = Rack::MockRequest.env_for(path, { :method => method, :params => params, 'REMOTE_ADDR' => remote_addr })
    headers.each { |key, value| env[key] = value }
    env
  end

  describe 'path_without_extensions normalization' do
    it 'strips extensions and trailing slashes' do
      request = Rack::Attack::Request.new(Rack::MockRequest.env_for('/auth/sign_in.json/'))

      expect(request.path_without_extensions).to eq('/auth/sign_in')
    end

    it 'keeps the root path intact' do
      request = Rack::Attack::Request.new(Rack::MockRequest.env_for('/'))

      expect(request.path_without_extensions).to eq('/')
    end
  end

  describe 'widget conversation and message throttles' do
    it 'keys conversation creation on IP and website token' do
      key = discriminator('api/v1/widget/conversations',
                          env_for('/api/v1/widget/conversations?website_token=tok1', method: :post))

      expect(key).to eq('1.2.3.4:tok1')
    end

    it 'lets the query token win over the body token so buckets cannot be forked' do
      key = discriminator('api/v1/widget/conversations',
                          env_for('/api/v1/widget/conversations?website_token=querytok', method: :post,
                                                                                         params: { website_token: 'bodytok' }))

      expect(key).to eq('1.2.3.4:querytok')
    end

    it 'keys message creation on IP and website token' do
      key = discriminator('api/v1/widget/messages',
                          env_for('/api/v1/widget/messages?website_token=tok1', method: :post))

      expect(key).to eq('1.2.3.4:tok1')
    end

    it 'returns nil for other widget conversation verbs' do
      key = discriminator('api/v1/widget/conversations',
                          env_for('/api/v1/widget/conversations?website_token=tok1', method: :get))

      expect(key).to be_nil
    end

    it 'uses upstream default limits' do
      expect(described_class.throttles['api/v1/widget/conversations'].limit).to eq(30)
      expect(described_class.throttles['api/v1/widget/messages'].limit).to eq(60)
    end
  end

  describe 'widget contact, load, and transcript throttles' do
    it 'throttles widget contact updates per IP' do
      key = discriminator('api/v1/widget/contact', env_for('/api/v1/widget/contact', method: :patch))

      expect(key).to eq('1.2.3.4')
    end

    it 'throttles widget loads without an existing conversation token' do
      key = discriminator('widget?website_token={website_token}&cw_conversation={x-auth-token}',
                          env_for('/widget?website_token=tok1', method: :get))

      expect(key).to eq('1.2.3.4')
    end

    it 'skips widget loads resuming an existing conversation' do
      key = discriminator('widget?website_token={website_token}&cw_conversation={x-auth-token}',
                          env_for('/widget?website_token=tok1&cw_conversation=abc', method: :get))

      expect(key).to be_nil
    end

    it 'throttles transcript requests per IP' do
      key = discriminator('api/v1/widget/conversations/transcript',
                          env_for('/api/v1/widget/conversations/transcript', method: :post))

      expect(key).to eq('1.2.3.4')
    end
  end

  describe 'per-account destructive endpoint throttles' do
    it 'keys conversation deletes on the account id' do
      key = discriminator('/api/v1/accounts/:account_id/conversations/:id DELETE',
                          env_for('/api/v1/accounts/42/conversations/7', method: :delete))

      expect(key).to eq('42')
    end

    it 'matches paths with extensions or trailing slashes' do
      key = discriminator('/api/v1/accounts/:account_id/conversations/:id DELETE',
                          env_for('/api/v1/accounts/42/conversations/7.json', method: :delete))

      expect(key).to eq('42')
    end

    it 'keys agent creation on the account id, including bulk_create' do
      expect(discriminator('/api/v1/accounts/:account_id/agents POST',
                           env_for('/api/v1/accounts/42/agents', method: :post))).to eq('42')
      expect(discriminator('/api/v1/accounts/:account_id/agents POST',
                           env_for('/api/v1/accounts/42/agents/bulk_create', method: :post))).to eq('42')
    end

    it 'keys agent deletion on the account id' do
      key = discriminator('/api/v1/accounts/:account_id/agents/:id DELETE',
                          env_for('/api/v1/accounts/42/agents/9', method: :delete))

      expect(key).to eq('42')
    end

    it 'does not throttle agent endpoints for other verbs' do
      key = discriminator('/api/v1/accounts/:account_id/agents POST',
                          env_for('/api/v1/accounts/42/agents', method: :get))

      expect(key).to be_nil
    end
  end

  describe 'reports drilldown throttle' do
    it 'keys on the uid header combined with the account id' do
      key = discriminator('/api/v2/accounts/:account_id/reports/drilldown/user',
                          env_for('/api/v2/accounts/42/reports/drilldown', method: :get,
                                                                           headers: { 'HTTP_UID' => 'agent@example.com' }))

      expect(key).to eq('agent@example.com:42')
    end

    it 'falls back to the api access token when uid is absent' do
      key = discriminator('/api/v2/accounts/:account_id/reports/drilldown/user',
                          env_for('/api/v2/accounts/42/reports/drilldown', method: :get,
                                                                           headers: { 'HTTP_API_ACCESS_TOKEN' => 'token123' }))

      expect(key).to eq('token123:42')
    end

    it 'defaults to one tenth of the reports user-level limit' do
      expect(described_class.throttles['/api/v2/accounts/:account_id/reports/drilldown/user'].limit).to eq(10)
    end
  end
end
