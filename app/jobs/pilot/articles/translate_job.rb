module Pilot
  module Articles
    # Translates one Help Center article into a target locale and persists the
    # result as a draft in the same portal. Enqueued once per selected article
    # from the article list's bulk translate action.
    #
    # A linked translation (same root article + target locale) is refreshed in
    # place instead of being duplicated; otherwise a new draft is created and
    # pointed at the source article's root via `associated_article_id`.
    class TranslateJob < ApplicationJob
      queue_as :low

      def perform(account, article_id, target_locale, target_category_id, user)
        @account = account
        @source_article = account.articles.find(article_id)
        @target_locale = target_locale

        translated_title = translate(@source_article.title, type: :title)
        translated_content = translate_content

        translation = find_existing_translation
        if translation
          translation.update!(
            title: translated_title,
            content: translated_content,
            description: @source_article.description
          )
        else
          create_translation(translated_title, translated_content, target_category_id, user)
        end
      end

      private

      def translate_content
        return @source_article.content if @source_article.content.blank?

        translate(@source_article.content, type: :content)
      end

      def translate(text, type:)
        response = Pilot::ArticleTranslationService.new(
          account: @account,
          text: text,
          target_language: @target_locale,
          type: type
        ).perform
        raise "Article translation failed: #{response[:error]}" if response[:error]

        response[:message]
      end

      def find_existing_translation
        root_id = Article.find_root_article_id(@source_article)
        @source_article.portal.articles.find_by(associated_article_id: root_id, locale: @target_locale)
      end

      def create_translation(title, content, category_id, user)
        @source_article.portal.articles.create!(
          title: title,
          content: content,
          description: @source_article.description,
          category_id: category_id,
          locale: @target_locale,
          author_id: user.id,
          status: :draft,
          associated_article_id: Article.find_root_article_id(@source_article)
        )
      end
    end
  end
end
