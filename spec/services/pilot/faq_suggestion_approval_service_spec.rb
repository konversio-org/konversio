# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::FaqSuggestionApprovalService do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:suggestion) do
    create(:pilot_faq_suggestion, assistant: assistant, question: 'How do I cancel?', answer: 'From Settings > Billing.')
  end

  before do
    allow(Pilot::UpdateFaqSuggestionEmbeddingJob).to receive(:perform_later)
    allow(Pilot::UpdateEmbeddingJob).to receive(:perform_later)
  end

  it 'creates an approved knowledge entry from the suggestion text' do
    response = described_class.new(suggestion: suggestion).perform

    expect(response).to be_persisted
    expect(response.status).to eq('approved')
    expect(response.assistant).to eq(assistant)
    expect(response.question).to eq('How do I cancel?')
    expect(response.answer).to eq('From Settings > Billing.')
    expect(suggestion.reload.status).to eq('approved')
  end

  it 'participates in customer-facing FAQ retrieval (approved status)' do
    response = described_class.new(suggestion: suggestion).perform
    expect(Pilot::AssistantResponse.approved.where(id: response.id)).to exist
  end

  it 'applies final edits to both the entry and the suggestion' do
    response = described_class.new(suggestion: suggestion, answer: 'Corrected answer.').perform

    expect(response.answer).to eq('Corrected answer.')
    expect(suggestion.reload.answer).to eq('Corrected answer.')
    expect(suggestion.status).to eq('approved')
  end

  it 'refuses non-open suggestions as not-found' do
    suggestion.update!(status: :dismissed)

    expect do
      described_class.new(suggestion: suggestion).perform
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(Pilot::AssistantResponse.where(assistant: assistant).count).to eq(0)
  end

  it 'creates exactly one knowledge entry under double approval' do
    described_class.new(suggestion: suggestion).perform

    expect do
      described_class.new(suggestion: suggestion.reload).perform
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(Pilot::AssistantResponse.where(assistant: assistant).count).to eq(1)
  end
end
