# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::FaqObservation do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:suggestion) { create(:pilot_faq_suggestion, assistant: assistant) }

  before do
    allow(Pilot::UpdateFaqSuggestionEmbeddingJob).to receive(:perform_later)
  end

  describe 'validations' do
    it 'requires generated question, answer, and language' do
      observation = build(:pilot_faq_observation, conversation: conversation,
                                                  generated_question: nil, generated_answer: nil, language: nil)
      expect(observation).not_to be_valid
      expect(observation.errors.attribute_names).to include(:generated_question, :generated_answer, :language)
    end

    it 'derives the account from the conversation' do
      observation = create(:pilot_faq_observation, conversation: conversation, account: nil)
      expect(observation.account).to eq(account)
    end

    it 'requires a suggestion when attached' do
      observation = build(:pilot_faq_observation, conversation: conversation, status: :attached, faq_suggestion: nil)
      expect(observation).not_to be_valid
      expect(observation.errors.attribute_names).to include(:faq_suggestion)
    end

    it 'requires the attached suggestion to be in the same account' do
      other_suggestion = create(:pilot_faq_suggestion)
      observation = build(:pilot_faq_observation, conversation: conversation, status: :attached,
                                                  faq_suggestion: other_suggestion)
      expect(observation).not_to be_valid
      expect(observation.errors.attribute_names).to include(:faq_suggestion)
    end

    it 'allows discarded observations without a suggestion' do
      observation = build(:pilot_faq_observation, conversation: conversation, status: :discarded, faq_suggestion: nil)
      expect(observation).to be_valid
    end
  end

  describe 'unique sighting per conversation and suggestion' do
    it 'rejects a second attached observation for the same conversation and suggestion' do
      create(:pilot_faq_observation, conversation: conversation, status: :attached, faq_suggestion: suggestion)

      duplicate = build(:pilot_faq_observation, conversation: conversation, status: :attached, faq_suggestion: suggestion)
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same conversation to observe different suggestions' do
      other_suggestion = create(:pilot_faq_suggestion, assistant: assistant)
      create(:pilot_faq_observation, conversation: conversation, status: :attached, faq_suggestion: suggestion)

      observation = build(:pilot_faq_observation, conversation: conversation, status: :attached,
                                                  faq_suggestion: other_suggestion)
      expect(observation).to be_valid
    end
  end
end
