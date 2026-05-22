class SuperAdmin::PilotController < SuperAdmin::ApplicationController
  def show
    @llm_providers_configured = Llm::ProviderRegistry.available_providers.length
    @llm_providers_total = Llm::ProviderRegistry.known_slugs.length
    @firecrawl_set = GlobalConfigService.load('PILOT_FIRECRAWL_API_KEY', nil).present?
  end
end
