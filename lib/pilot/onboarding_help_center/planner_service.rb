class Pilot::OnboardingHelpCenter::PlannerService
  def initialize(account:, portal:, user:, generation_id:)
    @account = account
    @portal = portal
    @user = user
    @generation_id = generation_id
  end

  # rubocop:disable Metrics/AbcSize
  def perform
    return if tracker.terminal?
    return tracker.skip!('scraping_provider_unconfigured') unless Pilot::OnboardingHelpCenter::ScrapingProvider.configured?

    urls = Pilot::OnboardingHelpCenter::ScrapingProvider.discover_urls(website)
    return tracker.skip!('no_content_discovered') if urls.blank?

    plan = parsed_plan(urls)
    return tracker.skip!('planning_unavailable') if plan.blank?

    categories = persist_categories(plan[:categories])
    retained = filter_articles(plan[:articles], categories, urls)
    return tracker.skip!('insufficient_articles') if retained.size < Pilot::OnboardingHelpCenter::MIN_ARTICLES

    tracker.total = retained.size
    enqueue_writers(retained)
  end
  # rubocop:enable Metrics/AbcSize

  private

  def website
    @account.custom_attributes['website'].presence || brand_info[:domain].presence
  end

  def brand_info
    @brand_info ||= (@account.custom_attributes['brand_info'] || {}).deep_symbolize_keys
  end

  def parsed_plan(urls)
    response = Pilot::OnboardingHelpCenter::PlanTask.new(account: @account, urls: urls).perform
    return if response.blank? || response[:error].present?

    payload = parse_json(response[:message])
    return unless payload.is_a?(Hash)

    {
      categories: Array(payload['categories']).map { |c| symbolize(c) }.select { |c| c[:name].present? },
      articles: Array(payload['articles']).map { |a| symbolize(a) }.select { |a| a[:title].present? }
    }
  end

  def symbolize(hash)
    hash.to_h.deep_symbolize_keys
  end

  def parse_json(text)
    return if text.blank?

    cleaned = text.to_s.strip.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '')
    JSON.parse(cleaned)
  rescue JSON::ParserError
    nil
  end

  def persist_categories(planned)
    planned.each_with_index.map do |attrs, index|
      @portal.categories.create!(
        name: attrs[:name],
        description: attrs[:description],
        locale: @portal.default_locale,
        position: index + 1,
        slug: unique_category_slug(attrs[:name])
      )
    end
  end

  def unique_category_slug(name)
    base = name.to_s.parameterize.presence || 'category'
    slug = base
    suffix = 2
    while @portal.categories.exists?(slug: slug, locale: @portal.default_locale)
      slug = "#{base}-#{suffix}"
      suffix += 1
    end
    slug
  end

  def filter_articles(planned, categories, urls)
    known = categories.index_by { |category| category.name.to_s.downcase }
    discovered = urls.map(&:to_s)

    planned.filter_map do |attrs|
      category = known[attrs[:category].to_s.downcase]
      sources = Array(attrs[:source_urls]).map(&:to_s)
      next if category.nil? || sources.blank?
      next unless sources.all? { |url| discovered.include?(url) }

      { category_slug: category.slug, title: attrs[:title].to_s, source_urls: sources }
    end
  end

  def enqueue_writers(retained)
    retained.each do |article|
      Pilot::OnboardingHelpCenter::WriteArticleJob.perform_later(
        @account.id, @portal.id, @user&.id, @generation_id,
        article[:category_slug], article[:title], article[:source_urls]
      )
    end
  end

  def tracker
    @tracker ||= Pilot::OnboardingHelpCenter::GenerationTracker.new(@generation_id)
  end
end
