# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Companies::BusinessEmailDetectorService, type: :service do
  describe '#perform' do
    context 'with a business domain' do
      it 'returns true' do
        expect(described_class.new('user@acme.com').perform).to be(true)
      end
    end

    context 'with a known free-mail provider' do
      it 'returns false' do
        expect(described_class.new('user@gmail.com').perform).to be(false)
      end
    end

    context 'with a disposable domain' do
      it 'returns false' do
        address = instance_double(ValidEmail2::Address, valid?: true, disposable_domain?: true)
        allow(ValidEmail2::Address).to receive(:new).with('user@mailinator.com').and_return(address)

        expect(described_class.new('user@mailinator.com').perform).to be(false)
      end
    end

    context 'with an invalid email' do
      it 'returns false' do
        expect(described_class.new('not-an-email').perform).to be(false)
      end
    end

    context 'with a reserved documentation domain' do
      it 'returns false' do
        expect(described_class.new('user@example.com').perform).to be(false)
      end
    end

    context 'with a blank email' do
      it 'returns false for nil' do
        expect(described_class.new(nil).perform).to be(false)
      end

      it 'returns false for an empty string' do
        expect(described_class.new('').perform).to be(false)
      end
    end

    context 'with an uppercase free-mail domain' do
      it 'returns false' do
        expect(described_class.new('user@GMAIL.COM').perform).to be(false)
      end
    end
  end
end
