require 'rails_helper'

RSpec.describe Pilot::Articles::TranslateJob, type: :job do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:portal) { create(:portal, account: account, config: { allowed_locales: %w[en nl] }) }
  let!(:category) { create(:category, portal: portal, account: account, locale: 'en', slug: 'basics') }
  let!(:target_category) { create(:category, portal: portal, account: account, locale: 'nl', slug: 'basis') }
  let!(:article) do
    create(:article, portal: portal, account: account, category: category, author: user,
                     status: :published, locale: 'en', title: 'Getting started', content: 'Some body text')
  end

  # Title is translated first, content second; and_return feeds them in order.
  let(:title_service) { instance_double(Pilot::ArticleTranslationService, perform: { message: 'Aan de slag' }) }
  let(:content_service) { instance_double(Pilot::ArticleTranslationService, perform: { message: 'Wat inhoud' }) }

  before do
    allow(Pilot::ArticleTranslationService).to receive(:new) do |*args, **kwargs|
      options = kwargs.presence || args.first
      options[:type].to_sym == :title ? title_service : content_service
    end
  end

  describe '#perform' do
    it 'creates a draft linked to the source root in the target locale and category' do
      described_class.perform_now(account, article.id, 'nl', target_category.id, user)

      translation = portal.articles.find_by(locale: 'nl', associated_article_id: article.id)
      expect(translation).to be_present
      expect(translation.title).to eq('Aan de slag')
      expect(translation.content).to eq('Wat inhoud')
      expect(translation.category_id).to eq(target_category.id)
      expect(translation.author_id).to eq(user.id)
      expect(translation).to be_draft
    end

    it 'passes the source title and content through the translation service' do
      described_class.perform_now(account, article.id, 'nl', target_category.id, user)

      expect(Pilot::ArticleTranslationService).to have_received(:new)
        .with(account: account, text: 'Getting started', target_language: 'nl', type: :title)
      expect(Pilot::ArticleTranslationService).to have_received(:new)
        .with(account: account, text: 'Some body text', target_language: 'nl', type: :content)
    end

    it 'updates the existing translation on repeat runs instead of duplicating' do
      described_class.perform_now(account, article.id, 'nl', target_category.id, user)
      translation = portal.articles.find_by(locale: 'nl', associated_article_id: article.id)

      expect do
        described_class.perform_now(account, article.id, 'nl', target_category.id, user)
      end.not_to change(Article, :count)

      expect(translation.reload.title).to eq('Aan de slag')
      expect(translation.reload.content).to eq('Wat inhoud')
    end

    it 'skips content translation when the source content is blank' do
      article.update!(status: :draft, content: nil)

      described_class.perform_now(account, article.id, 'nl', target_category.id, user)

      translation = portal.articles.find_by(locale: 'nl', associated_article_id: article.id)
      expect(translation.content).to be_blank
      expect(Pilot::ArticleTranslationService).not_to have_received(:new)
        .with(hash_including(type: :content))
    end

    it 'raises when the translation service returns an error' do
      allow(content_service).to receive(:perform).and_return({ error: 'LLM unavailable' })

      expect do
        described_class.perform_now(account, article.id, 'nl', target_category.id, user)
      end.to raise_error(/LLM unavailable/)
    end
  end
end
