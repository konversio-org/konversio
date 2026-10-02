require 'httparty'

# Installation-configured web scraping gateway used by the Help Center generation
# pipeline. Two operations are exposed:
#
#   discover_urls(domain) -> Array<String>  candidate content URLs on the site
#   scrape(url)           -> Hash|nil       { markdown:, status: } for a page
#
# Konversio does not bundle a scanning vendor. An operator points the installation
# at any endpoint that follows the small JSON contract documented below by setting
# PILOT_HELP_CENTER_SCRAPER_BASE_URL (and optionally PILOT_HELP_CENTER_SCRAPER_API_KEY).
module Pilot::OnboardingHelpCenter::ScrapingProvider
  DISCOVERY_PATH = '/v1/map'.freeze
  SCRAPE_PATH = '/v1/scrape'.freeze
  TIMEOUT = 30

  module_function

  def configured?
    base_url.present?
  end

  def discover_urls(domain)
    return [] if !configured? || domain.blank?

    response = request(DISCOVERY_PATH, url: normalize_url(domain), limit: Pilot::OnboardingHelpCenter::DISCOVERY_LIMIT)
    payload = response&.parsed_response
    links = payload.is_a?(Hash) ? payload['links'] : payload
    Array(links).first(Pilot::OnboardingHelpCenter::DISCOVERY_LIMIT)
  rescue StandardError => e
    Rails.logger.error "[HelpCenter Scraper] discovery failed for #{domain}: #{e.message}"
    []
  end

  def scrape(url)
    return nil unless configured?

    response = request(SCRAPE_PATH, url: url)
    return nil unless response&.success?

    payload = response.parsed_response
    data = payload.is_a?(Hash) ? (payload['data'] || payload) : {}
    status = data.dig('metadata', 'statusCode') || response.code
    { markdown: data['markdown'].to_s, status: status.to_i }
  rescue StandardError => e
    Rails.logger.error "[HelpCenter Scraper] scrape failed for #{url}: #{e.message}"
    nil
  end

  def request(path, **query)
    HTTParty.get(
      "#{base_url.chomp('/')}#{path}",
      query: query,
      headers: auth_headers,
      timeout: TIMEOUT
    )
  end

  def auth_headers
    key = api_key
    key.present? ? { 'Authorization' => "Bearer #{key}" } : {}
  end

  def base_url
    GlobalConfigService.load(Pilot::OnboardingHelpCenter::SCRAPER_BASE_URL_KEY, nil).to_s.strip.presence
  end

  def api_key
    GlobalConfigService.load(Pilot::OnboardingHelpCenter::SCRAPER_API_KEY_KEY, nil).to_s.strip.presence
  end

  def normalize_url(domain)
    domain.to_s.start_with?('http') ? domain.to_s : "https://#{domain}"
  end
end
