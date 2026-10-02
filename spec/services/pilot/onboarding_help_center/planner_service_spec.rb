require 'rails_helper'

RSpec.describe Pilot::OnboardingHelpCenter::PlannerService do
  subject(:service) { described_class.new(account: account, portal: portal, user: user, generation_id: generation_id) }

  let(:account) { create(:account, custom_attributes: { 'website' => 'acme.com' }) }
  let(:portal) { create(:portal, account: account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:generation_id) { SecureRandom.uuid }
  let(:tracker) { Pilot::OnboardingHelpCenter::GenerationTracker.new(generation_id) }
  let(:urls) { ['https://acme.com/help/a', 'https://acme.com/help/b', 'https://acme.com/help/c'] }
  let(:plan) do
    {
      'categories' => [{ 'name' => 'Getting started' }, { 'name' => 'Billing' }],
      'articles' => [
        { 'title' => 'Install', 'category' => 'Getting started', 'source_urls' => [urls[0]] },
        { 'title' => 'Configure', 'category' => 'Getting started', 'source_urls' => [urls[1]] },
        { 'title' => 'Pay', 'category' => 'Billing', 'source_urls' => [urls[2]] },
        { 'title' => 'Unknown category', 'category' => 'Nope', 'source_urls' => [urls[0]] },
        { 'title' => 'Undiscovered URL', 'category' => 'Billing', 'source_urls' => ['https://acme.com/secret'] }
      ]
    }
  end

  before do
    tracker.begin!
    allow(Pilot::OnboardingHelpCenter::ScrapingProvider).to receive(:configured?).and_return(true)
    allow(Pilot::OnboardingHelpCenter::ScrapingProvider).to receive(:discover_urls).with('acme.com').and_return(urls)
    allow(Pilot::OnboardingHelpCenter::PlanTask).to receive(:new)
      .and_return(instance_double(Pilot::OnboardingHelpCenter::PlanTask, perform: { message: plan.to_json }))
    allow(Pilot::OnboardingHelpCenter::WriteArticleJob).to receive(:perform_later)
  end

  describe '#perform' do
    it 'persists categories, filters articles, sets the total, and enqueues writers' do
      service.perform

      expect(portal.categories.pluck(:name)).to contain_exactly('Getting started', 'Billing')
      expect(portal.categories.pluck(:position)).to eq([1, 2])
      expect(tracker.total).to eq(3)
      expect(Pilot::OnboardingHelpCenter::WriteArticleJob).to have_received(:perform_later).exactly(3).times
    end

    it 'terminates as skipped when the scraping provider is not configured' do
      allow(Pilot::OnboardingHelpCenter::ScrapingProvider).to receive(:configured?).and_return(false)

      service.perform

      expect(tracker.state).to eq('skipped')
      expect(Pilot::OnboardingHelpCenter::WriteArticleJob).not_to have_received(:perform_later)
    end

    it 'terminates as skipped when discovery returns nothing' do
      allow(Pilot::OnboardingHelpCenter::ScrapingProvider).to receive(:discover_urls).and_return([])

      service.perform

      expect(tracker.state).to eq('skipped')
    end

    it 'terminates as skipped when the LLM is unavailable' do
      allow(Pilot::OnboardingHelpCenter::PlanTask).to receive(:new)
        .and_return(instance_double(Pilot::OnboardingHelpCenter::PlanTask, perform: { error: 'no key', error_code: 401 }))

      service.perform

      expect(tracker.state).to eq('skipped')
    end

    it 'terminates as skipped when fewer than three usable articles remain' do
      sparse = {
        'categories' => [{ 'name' => 'Getting started' }],
        'articles' => [
          { 'title' => 'Install', 'category' => 'Getting started', 'source_urls' => [urls[0]] },
          { 'title' => 'Nope', 'category' => 'Missing', 'source_urls' => [urls[1]] }
        ]
      }
      allow(Pilot::OnboardingHelpCenter::PlanTask).to receive(:new)
        .and_return(instance_double(Pilot::OnboardingHelpCenter::PlanTask, perform: { message: sparse.to_json }))

      service.perform

      expect(tracker.state).to eq('skipped')
      expect(Pilot::OnboardingHelpCenter::WriteArticleJob).not_to have_received(:perform_later)
    end

    it 'is inert once the generation reached a terminal state' do
      tracker.skip!('done')

      service.perform

      expect(Pilot::OnboardingHelpCenter::ScrapingProvider).not_to have_received(:discover_urls)
    end
  end
end
