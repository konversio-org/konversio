require 'rails_helper'

RSpec.describe Pilot::UpdateEmbeddingJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:response) { create(:pilot_assistant_response, assistant: assistant, account: account, question: 'Q?', answer: 'A.') }

  describe '#perform' do
    # Embedding column is vector(3584); pull the canonical dimension from the
    # service so the test follows the default-model change rather than the
    # raw width.
    let(:vector_dim) do
      Custom::Pilot::EmbeddingService::MODEL_DIMENSIONS.fetch(
        Custom::Pilot::EmbeddingService::DEFAULT_EMBEDDING_MODEL
      )
    end

    it 'calls EmbeddingService with the combined question and answer text' do
      embedding = Array.new(vector_dim) { 0.001 }
      fake_service = instance_double(Custom::Pilot::EmbeddingService, embed: embedding)
      expect(Custom::Pilot::EmbeddingService).to receive(:new).with(account: account).and_return(fake_service)
      expect(fake_service).to receive(:embed).with("Q?\n\nA.").and_return(embedding)

      described_class.perform_now(response.id)
      response.reload
      expect(response.embedding.to_a.length).to eq(vector_dim)
    end

    it 'does nothing when embedding service returns nil' do
      fake_service = instance_double(Custom::Pilot::EmbeddingService, embed: nil)
      allow(Custom::Pilot::EmbeddingService).to receive(:new).and_return(fake_service)

      described_class.perform_now(response.id)
      response.reload
      expect(response.embedding).to be_nil
    end

    it 'no-ops when the record was deleted' do
      response.destroy!
      expect { described_class.perform_now(response.id) }.not_to raise_error
    end
  end
end
