# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Pilot::FaqSuggestionMatcher do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:matcher) { described_class.new(assistant: assistant, account: account) }
  let(:candidate_vector) { [1.0] + Array.new(1535, 0.0) }
  let(:other_vector) { [0.0, 1.0] + Array.new(1534, 0.0) }

  before do
    allow(Pilot::UpdateFaqSuggestionEmbeddingJob).to receive(:perform_later)
    allow(Pilot::UpdateEmbeddingJob).to receive(:perform_later)
    allow_any_instance_of(Custom::Pilot::EmbeddingService).to receive(:embed).and_return(candidate_vector)
  end

  def store_embedding(record, vector)
    record.update_column(:embedding, vector) # rubocop:disable Rails/SkipsModelValidations
  end

  def match(language: 'en')
    matcher.match(question: 'How do I cancel?', answer: 'From Settings > Billing.', language: language)
  end

  context 'when nothing is stored' do
    it 'routes to create' do
      expect(match.route).to eq(:create)
    end
  end

  context 'with an approved knowledge entry near the candidate' do
    let!(:response) do
      create(:pilot_assistant_response, assistant: assistant, status: :approved).tap { |r| store_embedding(r, candidate_vector) }
    end

    it 'routes to knowledge when the judgment confirms' do
      allow(matcher).to receive(:invoke_judgment).and_return('true')

      result = match
      expect(result.route).to eq(:knowledge)
      expect(result.record).to eq(response)
    end

    it 'treats the candidate as unmatched when the judgment returns false' do
      allow(matcher).to receive(:invoke_judgment).and_return('false')

      expect(match.route).to eq(:create)
    end
  end

  context 'with a dismissed suggestion near the candidate' do
    let!(:suggestion) do
      create(:pilot_faq_suggestion, assistant: assistant, status: :dismissed, language: 'en').tap { |s| store_embedding(s, candidate_vector) }
    end

    it 'routes to dismissed when the judgment confirms' do
      allow(matcher).to receive(:invoke_judgment).and_return('true')

      result = match
      expect(result.route).to eq(:dismissed)
      expect(result.record).to eq(suggestion)
    end

    it 'ignores dismissed suggestions in another language' do
      suggestion.update!(language: 'de')
      allow(matcher).to receive(:invoke_judgment).and_return('true')

      expect(match(language: 'en').route).to eq(:create)
    end
  end

  context 'with an open suggestion near the candidate' do
    let!(:suggestion) do
      create(:pilot_faq_suggestion, assistant: assistant, status: :open, language: 'en').tap { |s| store_embedding(s, candidate_vector) }
    end

    it 'routes to attach when the judgment confirms' do
      allow(matcher).to receive(:invoke_judgment).and_return('true')

      result = match
      expect(result.route).to eq(:attach)
      expect(result.record).to eq(suggestion)
    end

    it 'ignores open suggestions in another language' do
      suggestion.update!(language: 'de')
      allow(matcher).to receive(:invoke_judgment).and_return('true')

      expect(match(language: 'en').route).to eq(:create)
    end
  end

  context 'when both approved knowledge and an open suggestion match' do
    it 'prefers the approved knowledge pool' do
      create(:pilot_assistant_response, assistant: assistant, status: :approved).tap { |r| store_embedding(r, candidate_vector) }
      create(:pilot_faq_suggestion, assistant: assistant, status: :open).tap { |s| store_embedding(s, candidate_vector) }
      allow(matcher).to receive(:invoke_judgment).and_return('true')

      expect(match.route).to eq(:knowledge)
    end
  end

  context 'with a record beyond the distance threshold' do
    it 'does not shortlist it' do
      create(:pilot_assistant_response, assistant: assistant, status: :approved).tap { |r| store_embedding(r, other_vector) }
      expect(matcher).not_to receive(:invoke_judgment)

      expect(match.route).to eq(:create)
    end
  end

  context 'when the equivalence judgment fails' do
    before do
      create(:pilot_assistant_response, assistant: assistant, status: :approved).tap { |r| store_embedding(r, candidate_vector) }
    end

    it 'raises on an unparseable verdict' do
      allow(matcher).to receive(:invoke_judgment).and_return('I think so')

      expect { match }.to raise_error(described_class::JudgmentError)
    end

    it 'raises on an LLM error' do
      allow(matcher).to receive(:invoke_judgment).and_raise(StandardError, 'provider down')

      expect { match }.to raise_error(described_class::JudgmentError)
    end
  end

  context 'when two near-identical candidates are matched in the same run' do
    it 'routes the second to duplicate' do
      expect(match.route).to eq(:create)
      expect(match.route).to eq(:duplicate)
    end
  end

  context 'when embedding the candidate fails' do
    it 'routes to create' do
      allow_any_instance_of(Custom::Pilot::EmbeddingService).to receive(:embed).and_raise(StandardError, 'boom')

      expect(match.route).to eq(:create)
    end
  end
end
