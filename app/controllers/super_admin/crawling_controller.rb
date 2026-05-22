class SuperAdmin::CrawlingController < SuperAdmin::ApplicationController
  CONFIG_KEYS = %w[PILOT_FIRECRAWL_CRAWL_LIMIT PILOT_FIRECRAWL_CRAWL_MAX_DEPTH].freeze

  def show
    load_view_state
  end

  def update
    submitted = (params[:crawling] || {}).to_unsafe_h

    parsed = parse_positive_integers(submitted)
    if parsed[:error]
      @error = parsed[:error]
      load_view_state
      render :show, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      parsed[:values].each { |name, value| write_config(name, value.to_s) }
    end
    GlobalConfig.clear_cache

    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_crawling_path, notice: 'Crawl limits updated.'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  FIRECRAWL_ENDPOINT = 'https://api.firecrawl.dev'.freeze

  def load_view_state
    @crawl_limit = GlobalConfigService.load('PILOT_FIRECRAWL_CRAWL_LIMIT', Custom::Pilot::DocumentCrawlService::DEFAULT_LIMIT.to_s).to_s
    @crawl_max_depth = GlobalConfigService.load('PILOT_FIRECRAWL_CRAWL_MAX_DEPTH', Custom::Pilot::DocumentCrawlService::DEFAULT_MAX_DEPTH.to_s).to_s
    raw_key = GlobalConfigService.load('PILOT_FIRECRAWL_API_KEY', nil).to_s
    masked_key = raw_key.length >= 8 ? "#{raw_key[0, 3]}…#{raw_key[-4, 4]}" : nil
    @firecrawl = {
      api_key_set: raw_key.present?,
      masked_key: masked_key,
      endpoint: FIRECRAWL_ENDPOINT
    }
  end

  def parse_positive_integers(submitted)
    values = {}
    CONFIG_KEYS.each do |name|
      raw = submitted[name].to_s.strip
      return { error: "#{humanize(name)} is required." } if raw.blank?

      value = Integer(raw, 10)
      return { error: "#{humanize(name)} must be a positive integer." } unless value.positive?

      values[name] = value
    end
    { values: values }
  rescue ArgumentError, TypeError
    { error: 'Crawl limits must be positive integers.' }
  end

  def write_config(name, value)
    row = InstallationConfig.find_or_initialize_by(name: name)
    row.value = value
    row.locked = false if row.new_record?
    row.save!
  end

  def humanize(name)
    name.to_s.delete_prefix('PILOT_FIRECRAWL_CRAWL_').tr('_', ' ').downcase.capitalize
  end
end
