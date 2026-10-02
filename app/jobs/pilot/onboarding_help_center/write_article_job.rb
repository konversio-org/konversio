class Pilot::OnboardingHelpCenter::WriteArticleJob < ApplicationJob
  queue_as :low

  # rubocop:disable Metrics/ParameterLists
  def perform(account_id, portal_id, user_id, generation_id, category_slug, title, source_urls)
    tracker = Pilot::OnboardingHelpCenter::GenerationTracker.new(generation_id)
    return if tracker.state.blank? || tracker.terminal?

    begin
      write_article(
        account: Account.find_by(id: account_id),
        portal: Portal.find_by(id: portal_id),
        user: User.find_by(id: user_id),
        category_slug: category_slug,
        title: title,
        source_urls: Array(source_urls)
      )
    ensure
      tracker.finish_article!
    end
  rescue StandardError => e
    Rails.logger.error "[Onboarding HelpCenter] article write failed for generation #{generation_id}: #{e.message}"
    tracker.finish_article!
  end
  # rubocop:enable Metrics/ParameterLists

  private

  # rubocop:disable Metrics/ParameterLists
  def write_article(account:, portal:, user:, category_slug:, title:, source_urls:)
    return if account.nil? || portal.nil?

    pages = scrape_pages(source_urls)
    return if pages.empty?

    composed = compose(account, pages, title)
    return if composed.blank?

    category = portal.categories.find_by(slug: category_slug, locale: portal.default_locale)
    portal.articles.create!(
      account: account,
      category: category,
      author: user,
      locale: portal.default_locale,
      status: :draft,
      title: composed[:title],
      description: composed[:description],
      content: composed[:body],
      meta: { 'source_urls' => pages.pluck(:url) }
    )
  end
  # rubocop:enable Metrics/ParameterLists

  def scrape_pages(source_urls)
    source_urls.filter_map do |url|
      page = Pilot::OnboardingHelpCenter::ScrapingProvider.scrape(url)
      next if page.nil? || page[:markdown].blank?
      next unless page[:status].between?(200, 299)

      { url: url, markdown: page[:markdown] }
    end
  end

  def compose(account, pages, title)
    response = Pilot::OnboardingHelpCenter::ArticleTask.new(account: account, pages: pages, title: title).perform
    return if response.blank? || response[:error].present?

    payload = parse_json(response[:message])
    return unless payload.is_a?(Hash)

    composed = {
      title: payload['title'].to_s.strip,
      description: payload['description'].to_s.strip,
      body: payload['body'].to_s.strip
    }
    return if composed[:title].blank? || composed[:body].blank?

    composed
  end

  def parse_json(text)
    return if text.blank?

    cleaned = text.to_s.strip.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '')
    JSON.parse(cleaned)
  rescue JSON::ParserError
    nil
  end
end
