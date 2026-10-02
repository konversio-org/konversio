require 'rails_helper'

RSpec.describe Pilot::OnboardingHelpCenter::WriteArticleJob do
  let(:account) { create(:account) }
  let(:portal) { create(:portal, account: account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:category) do
    create(:category, portal: portal, account: account, name: 'Getting started', slug: 'getting-started', locale: portal.default_locale)
  end
  let(:generation_id) { SecureRandom.uuid }
  let(:tracker) { Pilot::OnboardingHelpCenter::GenerationTracker.new(generation_id) }
  let(:source_urls) { ['https://acme.com/help/a', 'https://acme.com/help/b'] }
  let(:composed) { { 'title' => 'How to install', 'description' => 'A short intro', 'body' => '# Steps\nDo the thing.' } }

  before do
    category
    tracker.begin!
    tracker.total = 1
  end

  def perform
    described_class.perform_now(account.id, portal.id, user.id, generation_id, category.slug, 'Install', source_urls)
  end

  describe '#perform' do
    it 'creates a draft article attributed to the user with source-URL provenance' do
      allow(Pilot::OnboardingHelpCenter::ScrapingProvider).to receive(:scrape).and_return({ markdown: 'page text', status: 200 })
      allow(Pilot::OnboardingHelpCenter::ArticleTask).to receive(:new)
        .and_return(instance_double(Pilot::OnboardingHelpCenter::ArticleTask, perform: { message: composed.to_json }))

      expect { perform }.to change(portal.articles, :count).by(1)

      article = portal.articles.last
      expect(article).to be_draft
      expect(article.author).to eq(user)
      expect(article.category).to eq(category)
      expect(article.title).to eq('How to install')
      expect(article.meta['source_urls']).to eq(source_urls)
      expect(tracker.state).to eq('completed')
    end

    it 'creates no article when every source page is unusable but still advances' do
      allow(Pilot::OnboardingHelpCenter::ScrapingProvider).to receive(:scrape).and_return({ markdown: '', status: 404 })

      expect { perform }.not_to change(portal.articles, :count)
      expect(tracker.state).to eq('completed')
      expect(tracker.finished).to eq(1)
    end

    it 'creates no article on empty LLM output but still advances' do
      allow(Pilot::OnboardingHelpCenter::ScrapingProvider).to receive(:scrape).and_return({ markdown: 'page text', status: 200 })
      allow(Pilot::OnboardingHelpCenter::ArticleTask).to receive(:new)
        .and_return(instance_double(Pilot::OnboardingHelpCenter::ArticleTask, perform: { message: { title: '', body: '' }.to_json }))

      expect { perform }.not_to change(portal.articles, :count)
      expect(tracker.state).to eq('completed')
    end

    it 'swallows scrape or LLM failures' do
      allow(Pilot::OnboardingHelpCenter::ScrapingProvider).to receive(:scrape).and_raise(StandardError, 'boom')

      expect { perform }.not_to raise_error
      expect(tracker.finished).to eq(1)
    end

    it 'does nothing for a generation with no recorded state' do
      orphan = SecureRandom.uuid

      expect do
        described_class.perform_now(account.id, portal.id, user.id, orphan, category.slug, 'Install', source_urls)
      end.not_to change(portal.articles, :count)
      expect(Pilot::OnboardingHelpCenter::GenerationTracker.new(orphan).state).to be_nil
    end
  end
end
