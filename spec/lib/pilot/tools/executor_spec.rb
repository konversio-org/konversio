# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Tools::Executor do
  let(:account) { create(:account) }
  let(:public_ip) { '93.184.216.34' }

  def build_tool(**overrides)
    create(:pilot_custom_tool, account: account, **overrides)
  end

  def stub_resolved(host, ip)
    allow(Resolv).to receive(:getaddresses).with(host).and_return([ip])
  end

  # The executor connects to the resolved IP (DNS rebinding mitigation), so
  # WebMock sees the IP-addressed URL, not the hostname URL.
  def stub_http(method, ip, path, **)
    stub_request(method, "https://#{ip}#{path}").to_return(**)
  end

  describe 'argument type checking' do
    it 'returns parse_error on type mismatch' do
      tool = build_tool(param_schema: [{ 'name' => 'quantity', 'type' => 'integer', 'required' => true }])
      result = described_class.new(tool).call('quantity' => 'three')
      expect(result).to eq(error: 'tool.parse_error', message: "Argument 'quantity' must be integer")
    end

    it 'does not raise on type mismatch' do
      tool = build_tool(param_schema: [{ 'name' => 'quantity', 'type' => 'integer', 'required' => true }])
      expect { described_class.new(tool).call('quantity' => 'three') }.not_to raise_error
    end

    it 'accepts each declared param type' do
      values = {
        'string' => 'a', 'number' => 1.5, 'integer' => 2,
        'boolean' => true, 'array' => [1], 'object' => { 'k' => 1 }
      }
      Pilot::CustomTool::ALLOWED_PARAM_TYPES.each do |type|
        tool = build_tool(
          endpoint_url: 'https://api.example.com/x',
          param_schema: [{ 'name' => 'v', 'type' => type, 'required' => true }]
        )
        stub_resolved('api.example.com', public_ip)
        stub_http(:get, public_ip, '/x', status: 200, body: 'ok')
        result = described_class.new(tool).call('v' => values[type])
        expect(result).not_to be_a(Hash), "type #{type} should not return a structured error, got #{result.inspect}"
      end
    end

    it 'skips optional params when absent' do
      tool = build_tool(
        endpoint_url: 'https://api.example.com/x',
        param_schema: [{ 'name' => 'q', 'type' => 'string', 'required' => false }]
      )
      stub_resolved('api.example.com', public_ip)
      stub_http(:get, public_ip, '/x', status: 200, body: 'ok')
      expect(described_class.new(tool).call({})).to eq('ok')
    end
  end

  describe 'Liquid request template rendering' do
    it 'renders declared parameters into the POST body' do
      tool = build_tool(
        http_method: 'POST',
        endpoint_url: 'https://api.example.com/o',
        request_template: '{"order_id":"{{ order_id }}"}',
        param_schema: [{ 'name' => 'order_id', 'type' => 'string', 'required' => true }]
      )
      stub_resolved('api.example.com', public_ip)
      stub_request(:post, "https://#{public_ip}/o")
        .with(body: '{"order_id":"ABC"}')
        .to_return(status: 200, body: 'done')

      expect(described_class.new(tool).call('order_id' => 'ABC')).to eq('done')
    end
  end

  describe 'Liquid response template rendering' do
    it 'extracts a field from a JSON body via response.<field>' do
      tool = build_tool(
        endpoint_url: 'https://api.example.com/c',
        response_template: '{{ response.customer.name }}'
      )
      stub_resolved('api.example.com', public_ip)
      stub_http(:get, public_ip, '/c', status: 200, body: { customer: { name: 'Jane' } }.to_json)

      expect(described_class.new(tool).call).to eq('Jane')
    end

    it 'supports the `r` alias' do
      tool = build_tool(
        endpoint_url: 'https://api.example.com/s',
        response_template: '{{ r.status }}'
      )
      stub_resolved('api.example.com', public_ip)
      stub_http(:get, public_ip, '/s', status: 200, body: { status: 'ok' }.to_json)

      expect(described_class.new(tool).call).to eq('ok')
    end

    it 'returns parse_error on a Liquid render error' do
      tool = build_tool(
        endpoint_url: 'https://api.example.com/x',
        response_template: '{{ response | divided_by: 0 }}'
      )
      stub_resolved('api.example.com', public_ip)
      stub_http(:get, public_ip, '/x', status: 200, body: '1')

      result = described_class.new(tool).call
      expect(result).to include(error: 'tool.parse_error')
    end
  end

  describe 'SSRF CIDR denylist' do
    %w[10.0.0.5 172.16.0.5 192.168.1.5 169.254.169.254 127.0.0.1].each do |denied|
      it "rejects calls resolving to #{denied}" do
        tool = build_tool(endpoint_url: 'https://internal.example/x')
        stub_resolved('internal.example', denied)
        result = described_class.new(tool).call
        expect(result).to eq(error: 'tool.private_ip_denied', message: 'Resolved address is in a denied range')
      end
    end

    %w[::1 fc00::1 fe80::1].each do |denied|
      it "rejects calls resolving to IPv6 #{denied}" do
        tool = build_tool(endpoint_url: 'https://internal.example/x')
        stub_resolved('internal.example', denied)
        result = described_class.new(tool).call
        expect(result[:error]).to eq('tool.private_ip_denied')
      end
    end

    it 'mitigates DNS rebinding by resolving the host exactly once per call' do
      tool = build_tool(endpoint_url: 'https://internal.example/x')
      expect(Resolv).to receive(:getaddresses).with('internal.example').once.and_return([public_ip])
      stub_http(:get, public_ip, '/x', status: 200, body: 'safe')

      expect(described_class.new(tool).call).to eq('safe')
    end
  end

  describe 'disabled tool' do
    it 'returns tool.disabled when enabled = false' do
      tool = build_tool(enabled: false)
      expect(described_class.new(tool).call).to eq(error: 'tool.disabled', message: 'Tool is not enabled')
    end
  end

  describe 'HTTP timeout handling' do
    it 'returns structured tool.timeout on read timeout' do
      tool = build_tool(endpoint_url: 'https://api.example.com/slow')
      stub_resolved('api.example.com', public_ip)
      stub_request(:get, "https://#{public_ip}/slow").to_timeout

      result = described_class.new(tool).call

      expect(result).to eq(
        error: 'tool.timeout',
        message: "Tool exceeded #{described_class::HTTP_READ_TIMEOUT}s timeout"
      )
    end

    it 'does not raise when the upstream times out' do
      tool = build_tool(endpoint_url: 'https://api.example.com/slow')
      stub_resolved('api.example.com', public_ip)
      stub_request(:get, "https://#{public_ip}/slow").to_timeout

      expect { described_class.new(tool).call }.not_to raise_error
    end
  end
end
