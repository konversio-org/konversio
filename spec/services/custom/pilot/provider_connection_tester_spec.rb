require 'rails_helper'

RSpec.describe Custom::Pilot::ProviderConnectionTester do
  let(:account) { create(:account) }

  def slot_config(api_key:, model:)
    {
      provider: 'openai',
      api_key: api_key,
      endpoint: 'https://api.example.com',
      model: model,
      openai_compatible: false
    }
  end

  def stub_slots(chat_key: 'sk-test', embedding_key: 'sk-test')
    allow(Llm::Config).to receive(:for_slot).with(:chat).and_return(
      slot_config(api_key: chat_key, model: 'gpt-4')
    )
    allow(Llm::Config).to receive(:for_slot).with(:embedding).and_return(
      slot_config(api_key: embedding_key, model: 'text-embedding-3-small')
    )
  end

  def stub_successful_chat
    fake_context = instance_double(RubyLLM::Context)
    fake_chat = instance_double(
      RubyLLM::Chat,
      ask: instance_double(RubyLLM::Message, content: 'pong')
    )
    allow(Llm::Config).to receive(:with_api_key).and_yield(fake_context)
    allow(fake_context).to receive(:chat).and_return(fake_chat)
  end

  def stub_embedding_client(behavior: :success)
    client = instance_double(OpenAI::Client)
    allow(OpenAI::Client).to receive(:new).and_return(client)
    case behavior
    when :success
      allow(client).to receive(:embeddings).and_return('data' => [{ 'embedding' => [0.0] * 1536 }])
    when :raise
      allow(client).to receive(:embeddings).and_raise(StandardError, 'dimension mismatch')
    end
  end

  describe '.call' do
    context 'when both slots are blank' do
      before { stub_slots(chat_key: nil, embedding_key: nil) }

      it 'surfaces missing-credential errors for both slots' do
        result = described_class.call(account: account)

        expect(result.success?).to be(false)
        expect(result.chat[:error_class]).to eq('MissingCredentialError')
        expect(result.embedding[:error_class]).to eq('MissingCredentialError')
      end
    end

    context 'when both slots respond successfully' do
      before do
        stub_slots
        stub_successful_chat
        stub_embedding_client(behavior: :success)
      end

      it 'returns success on both slots' do
        result = described_class.call(account: account)

        expect(result.success?).to be(true)
        expect(result.chat[:ok]).to be(true)
        expect(result.embedding[:ok]).to be(true)
      end
    end

    context 'when chat fails authentication' do
      before do
        stub_slots(chat_key: 'sk-bad')
        allow(Llm::Config).to receive(:with_api_key).and_raise(StandardError, 'Unauthorized')
        stub_embedding_client(behavior: :success)
      end

      it 'reports the chat failure but still records embedding success' do
        result = described_class.call(account: account)

        expect(result.success?).to be(false)
        expect(result.chat[:ok]).to be(false)
        expect(result.chat[:message]).to eq('Unauthorized')
        expect(result.embedding[:ok]).to be(true)
      end
    end

    context 'when the embedding slot raises' do
      before do
        stub_slots
        stub_successful_chat
        stub_embedding_client(behavior: :raise)
      end

      it 'records the embedding error in the result' do
        result = described_class.call(account: account)

        expect(result.success?).to be(false)
        expect(result.embedding[:ok]).to be(false)
        expect(result.embedding[:message]).to eq('dimension mismatch')
      end
    end
  end
end
