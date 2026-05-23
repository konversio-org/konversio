# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Tools::UrlGuard do
  describe '.resolve' do
    %w[
      10.0.0.5
      172.16.0.5
      192.168.1.5
      169.254.169.254
      127.0.0.1
      ::1
      fc00::1
      fe80::1
    ].each do |address|
      it "marks #{address} as denied" do
        allow(Resolv).to receive(:getaddresses).with('host.example').and_return([address])
        result = described_class.resolve('host.example')
        expect(result).to be_denied
        expect(result.ip).to eq(address)
      end
    end

    it 'allows a public address' do
      allow(Resolv).to receive(:getaddresses).with('public.example').and_return(['93.184.216.34'])
      result = described_class.resolve('public.example')
      expect(result).not_to be_denied
      expect(result.ip).to eq('93.184.216.34')
    end

    it 'returns denied when the host cannot be resolved' do
      allow(Resolv).to receive(:getaddresses).with('nope.invalid').and_return([])
      result = described_class.resolve('nope.invalid')
      expect(result).to be_denied
      expect(result.ip).to be_nil
    end
  end
end
