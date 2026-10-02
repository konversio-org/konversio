class Pilot::OnboardingHelpCenter::BootstrapService
  DEFAULT_COLOR = '#1f93ff'.freeze
  LOGO_MAX_BYTES = 5.megabytes

  def initialize(account, user)
    @account = account
    @user = user
  end

  def perform
    website = known_website
    return if website.blank?

    portal = @account.portals.order(:id).first
    return portal if portal.present?

    portal = create_portal(website)
    start_generation(portal)
    portal
  rescue StandardError => e
    Rails.logger.error "[Onboarding HelpCenter] bootstrap failed for account #{@account.id}: #{e.message}"
    nil
  end

  private

  def create_portal(website)
    name = brand_title || @account.name
    locale = @account.locale.presence || 'en'

    portal = @account.portals.create!(
      name: name,
      page_title: name,
      color: brand_color,
      header_text: brand_tagline,
      homepage_link: normalize_homepage(website),
      slug: unique_slug(name),
      channel_web_widget: web_widget_channel,
      config: { 'default_locale' => locale, 'allowed_locales' => [locale] }
    )

    attach_logo(portal)
    portal
  end

  def start_generation(portal)
    generation_id = SecureRandom.uuid
    @account.custom_attributes[Pilot::OnboardingHelpCenter::GENERATION_KEY] = generation_id
    @account.save!

    Pilot::OnboardingHelpCenter::GenerationTracker.new(generation_id).begin!

    Pilot::OnboardingHelpCenter::PlanJob.perform_later(@account.id, portal.id, @user&.id, generation_id)
  end

  def attach_logo(portal)
    url = Array(brand_info[:logos]).first&.dig(:url)
    return if url.blank?

    SafeFetch.fetch(url, validate_content_type: true, max_bytes: LOGO_MAX_BYTES) do |result|
      portal.logo.attach(io: result.tempfile, filename: result.filename, content_type: result.content_type)
    end
  rescue SafeFetch::Error, ActiveStorage::Error => e
    Rails.logger.error "[Onboarding HelpCenter] logo attach failed for account #{@account.id}: #{e.message}"
    nil
  end

  def brand_info
    @brand_info ||= (@account.custom_attributes['brand_info'] || {}).deep_symbolize_keys
  end

  def known_website
    @account.custom_attributes['website'].presence || brand_info[:domain].presence
  end

  def brand_title
    brand_info[:title].presence
  end

  def brand_tagline
    brand_info[:slogan].presence || brand_info[:description].presence
  end

  def brand_color
    hex = Array(brand_info[:colors]).first&.dig(:hex).to_s
    hex.match?(/\A#\h{6}\z/) ? hex : DEFAULT_COLOR
  end

  def web_widget_channel
    @account.inboxes.find_by(channel_type: 'Channel::WebWidget')&.channel
  end

  def normalize_homepage(website)
    website.to_s.start_with?('http') ? website.to_s : "https://#{website}"
  end

  def unique_slug(name)
    base = name.to_s.parameterize.presence || 'help-center'
    slug = base
    suffix = 2

    while Portal.exists?(slug: slug)
      return "#{base}-#{SecureRandom.hex(4)}" if suffix > 10

      slug = "#{base}-#{suffix}"
      suffix += 1
    end

    slug
  end
end
