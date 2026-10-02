# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::FaqSuggestion do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  before do
    allow(Pilot::UpdateFaqSuggestionEmbeddingJob).to receive(:perform_later)
  end

  describe 'validations' do
    it 'requires question, answer, and language' do
      suggestion = build(:pilot_faq_suggestion, assistant: assistant, question: nil, answer: nil, language: nil)
      expect(suggestion).not_to be_valid
      expect(suggestion.errors.attribute_names).to include(:question, :answer, :language)
    end

    it 'derives the account from the assistant' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant, account: nil)
      expect(suggestion.account).to eq(account)
    end
  end

  describe 'status enum' do
    it 'defaults to open and exposes the lifecycle states' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant)
      expect(suggestion.status).to eq('open')
      expect(described_class.statuses.keys).to contain_exactly('open', 'approved', 'dismissed')
    end
  end

  describe 'embedding refresh' do
    it 'schedules a refresh on create while open' do
      create(:pilot_faq_suggestion, assistant: assistant)
      expect(Pilot::UpdateFaqSuggestionEmbeddingJob).to have_received(:perform_later).once
    end

    it 'schedules a refresh when question or answer changes while open' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant)
      suggestion.update!(question: 'A reworded question?')
      expect(Pilot::UpdateFaqSuggestionEmbeddingJob).to have_received(:perform_later).with(suggestion.id).twice
    end

    it 'does not schedule a refresh for unrelated updates' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant, embedding: Array.new(1536, 0.01))
      suggestion.update!(source_count: suggestion.source_count + 1)
      expect(Pilot::UpdateFaqSuggestionEmbeddingJob).to have_received(:perform_later).once
    end

    it 'does not schedule further refreshes once no longer open' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant)
      suggestion.update!(status: :dismissed)
      suggestion.update!(question: 'Late edit?')
      # create + dismiss-edit attempts: only the create refresh fires
      expect(Pilot::UpdateFaqSuggestionEmbeddingJob).to have_received(:perform_later).once
    end
  end

  describe 'scopes' do
    it 'orders by descending source count then most recently updated' do
      low = create(:pilot_faq_suggestion, assistant: assistant, source_count: 1)
      high = create(:pilot_faq_suggestion, assistant: assistant, source_count: 5)
      mid = create(:pilot_faq_suggestion, assistant: assistant, source_count: 3)
      expect(described_class.where(id: [low.id, high.id, mid.id]).ordered).to eq([high, mid, low])
    end

    it 'filters by language' do
      en = create(:pilot_faq_suggestion, assistant: assistant, language: 'en')
      create(:pilot_faq_suggestion, assistant: assistant, language: 'de')
      expect(described_class.by_language('en')).to eq([en])
    end
  end

  describe '.normalize_language' do
    it 'collapses hyphen and underscore variants to the primary subtag' do
      expect(described_class.normalize_language('pt-BR')).to eq('pt')
      expect(described_class.normalize_language('PT_br')).to eq('pt')
      expect(described_class.normalize_language('EN')).to eq('en')
    end

    it 'falls back to the default locale when blank' do
      expect(described_class.normalize_language(nil)).to eq(I18n.default_locale.to_s)
    end
  end

  describe '.language_for' do
    it 'derives the normalized language from the account locale' do
      conversation = create(:conversation, account: account)
      expect(described_class.language_for(conversation)).to eq('en')
    end
  end

  describe '#embeddable_text' do
    it 'is the question/answer pair joined by a colon' do
      suggestion = build(:pilot_faq_suggestion, question: 'Q?', answer: 'A.')
      expect(suggestion.embeddable_text).to eq('Q?: A.')
    end
  end
end
