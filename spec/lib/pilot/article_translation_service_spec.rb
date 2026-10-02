require 'rails_helper'

RSpec.describe Pilot::ArticleTranslationService do
  let(:account) { create(:account) }

  def build_service(type:, target_language: 'nl', text: 'Hello')
    described_class.new(account: account, text: text, target_language: target_language, type: type)
  end

  describe '#perform' do
    it 'rejects an unsupported type' do
      expect { build_service(type: :summary).perform }.to raise_error(ArgumentError, /Unsupported translation type/)
    end

    it 'returns the stripped translation from the LLM response' do
      service = build_service(type: :title)
      allow(service).to receive(:make_api_call).and_return({ message: "  Hallo wereld  \n" })

      expect(service.perform[:message]).to eq('Hallo wereld')
    end

    it 'passes the error response straight through' do
      service = build_service(type: :content)
      allow(service).to receive(:make_api_call).and_return({ error: 'nope' })

      expect(service.perform).to eq({ error: 'nope' })
    end

    it 'uses the LLM model resolved for the default slot' do
      service = build_service(type: :title)
      allow(service).to receive(:make_api_call).and_return({ message: 'Hallo' })
      allow(Llm::Config).to receive(:model_for).with(:default).and_return('test-model')

      service.perform

      expect(service).to have_received(:make_api_call).with(hash_including(model: 'test-model'))
    end
  end

  describe 'target language resolution' do
    it 'resolves a known locale code to its language name' do
      expect(build_service(type: :title, target_language: 'nl').send(:resolved_language)).to eq('Dutch')
    end

    it 'falls back to the raw code when the locale is not mapped' do
      expect(build_service(type: :title, target_language: 'xx_YY').send(:resolved_language)).to eq('xx_YY')
    end

    it 'includes the resolved language in the model instructions' do
      service = build_service(type: :title, target_language: 'nl')
      captured = nil
      allow(service).to receive(:make_api_call) do |args|
        captured = args[:messages].first[:content]
        { message: 'Hallo' }
      end

      service.perform

      expect(captured).to include('Dutch')
    end
  end
end
