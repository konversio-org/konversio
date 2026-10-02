require 'rails_helper'

RSpec.describe Pilot::OnboardingHelpCenter::GenerationTracker do
  let(:generation_id) { SecureRandom.uuid }
  let(:tracker) { described_class.new(generation_id) }

  describe 'state transitions' do
    it 'begins in progress and completes when all articles finish' do
      tracker.begin!
      tracker.total = 2

      expect(tracker.state).to eq('generating')
      tracker.finish_article!
      expect(tracker.state).to eq('generating')
      tracker.finish_article!
      expect(tracker.state).to eq('completed')
    end

    it 'terminates as skipped with a reason' do
      tracker.begin!
      tracker.skip!('no_content_discovered')

      expect(tracker.state).to eq('skipped')
      expect(tracker).to be_terminal
    end

    it 'ignores further transitions after a terminal state' do
      tracker.begin!
      tracker.total = 2
      tracker.skip!('insufficient_articles')

      tracker.finish_article!
      tracker.finish_article!

      expect(tracker.state).to eq('skipped')
      expect(tracker.finished).to eq(0)
    end

    it 'does nothing when there is no recorded state' do
      tracker.finish_article!

      expect(tracker.state).to be_nil
    end
  end
end
