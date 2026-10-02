require 'rails_helper'

RSpec.describe Pilot::OnboardingHelpCenter::StatusService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  it 'returns nil-safe defaults when no generation pointer is stored' do
    expect(service.perform).to eq(generation_id: nil, state: nil, articles_count: 0, categories_count: 0)
  end

  context 'when a generation pointer is stored' do
    let(:portal) { create(:portal, account: account) }
    let(:generation_id) { SecureRandom.uuid }
    let(:tracker) { Pilot::OnboardingHelpCenter::GenerationTracker.new(generation_id) }

    before do
      account.update!(custom_attributes: account.custom_attributes.merge(Pilot::OnboardingHelpCenter::GENERATION_KEY => generation_id))
      tracker.begin!
      tracker.total = 5
    end

    it 'reports the tracked state and the first portal counts' do
      category = create(:category, portal: portal, account: account)
      create(:article, portal: portal, account: account, category: category, author: create(:user, account: account))

      expect(service.perform).to eq(
        generation_id: generation_id,
        state: 'generating',
        articles_count: 1,
        categories_count: 1
      )
    end

    it 'reports a nil state once the ephemeral state expires' do
      Redis::Alfred.delete(format(Redis::Alfred::PILOT_ONBOARDING_HELP_CENTER, generation_id: generation_id))

      expect(service.perform).to include(generation_id: generation_id, state: nil)
    end
  end
end
