class SuperAdmin::LlmSettingsController < SuperAdmin::ApplicationController
  SLOTS = %i[chat embedding audio].freeze

  SLOT_PURPOSES = {
    chat: { label: 'Chat', used_for: 'Replies, summaries, agent reasoning' },
    embedding: { label: 'Embeddings', used_for: 'Search and retrieval' },
    audio: { label: 'Audio', used_for: 'Transcription (plumbed, not yet consumed)' }
  }.freeze

  EMBEDDING_DIMENSIONS = {
    'text-embedding-3-small' => 1536,
    'text-embedding-3-large' => 3072,
    'BAAI/bge-en-icl' => 4096,
    'bge-multilingual-gemma2' => 3584
  }.freeze

  def show
    load_view_state
  end

  def update
    if params[:preset].present? && params[:preset] != Llm::Presets::CUSTOM_SLUG
      apply_preset(params[:preset])
    else
      apply_slots(params[:slots])
    end
  rescue Llm::ProviderRegistry::CapabilityMismatch, ArgumentError => e
    @error = e.message
    load_view_state
    render :show, status: :unprocessable_entity
  end

  def test
    @test_results = SLOTS.each_with_object({}) do |slot, h|
      h[slot] = run_slot_test(slot)
    end
    load_view_state
    render :show
  end

  private

  def apply_preset(slug)
    Llm::Presets.apply!(slug)
    Llm::Config.reset!
    Llm::Config.initialize!
    flash.now[:notice] = "Preset '#{slug}' applied. Sanity test results below."
    render_with_slot_tests
  end

  def apply_slots(slot_params)
    raise ArgumentError, 'No slot configuration submitted.' if slot_params.blank?

    parsed = SLOTS.each_with_object({}) do |slot, h|
      row = slot_params[slot.to_s] || slot_params[slot] || {}
      provider_val = row['provider'] || (row.respond_to?(:[]) ? row[:provider] : nil)
      model_val = row['model'] || (row.respond_to?(:[]) ? row[:model] : nil)
      h[slot] = {
        provider: provider_val.to_s.presence,
        model: model_val.to_s.strip.presence
      }
    end

    SLOTS.each do |slot|
      provider = parsed[slot][:provider]
      model = parsed[slot][:model]
      raise ArgumentError, "#{slot.capitalize} slot: provider is required." if provider.blank?
      raise ArgumentError, "#{slot.capitalize} slot: model is required." if model.blank?

      unless Llm::ProviderRegistry.providers_for(slot).map(&:to_s).include?(provider)
        raise Llm::ProviderRegistry::CapabilityMismatch,
              "#{slot.capitalize} slot: provider '#{provider}' is not available or does not declare the '#{slot}' capability."
      end
    end

    ActiveRecord::Base.transaction do
      SLOTS.each do |slot|
        write_config("PILOT_LLM_#{slot.upcase}_PROVIDER", parsed[slot][:provider])
        write_config("PILOT_LLM_#{slot.upcase}_MODEL", parsed[slot][:model])
      end
      matching = Llm::Presets.matching_current_config_for(parsed)
      write_config(Llm::Presets::PRESET_CONFIG_KEY, matching || Llm::Presets::CUSTOM_SLUG)
    end
    GlobalConfig.clear_cache
    Llm::Config.reset!
    Llm::Config.initialize!

    flash.now[:notice] = 'LLM slot configuration updated. Sanity test results below.'
    render_with_slot_tests
  end

  def render_with_slot_tests
    @test_results = SLOTS.each_with_object({}) { |slot, h| h[slot] = run_slot_test(slot) }
    load_view_state
    render :show
  end

  def load_view_state
    @providers = Llm::ProviderRegistry.known_slugs.map { |slug| Llm::ProviderRegistry.provider(slug) }
    @slots = SLOTS.each_with_object({}) do |slot, h|
      h[slot] = {
        provider: Llm::ProviderRegistry.slot_provider(slot),
        model: Llm::ProviderRegistry.slot_model(slot),
        candidates: Llm::ProviderRegistry.providers_for(slot)
      }
    end
    @presets = Llm::Presets.applicable
    @current_preset = GlobalConfigService.load(Llm::Presets::PRESET_CONFIG_KEY, nil).presence ||
                      Llm::Presets.matching_current_config ||
                      Llm::Presets::CUSTOM_SLUG
    @dimension_warning = embedding_dimension_warning
    configured_count = @providers.count { |p| p[:available] }
    missing_count = @providers.length - configured_count
    @provider_status_summary = { configured: configured_count, missing: missing_count }
  end

  def embedding_dimension_warning
    current_model = @slots[:embedding][:model]
    new_dim = EMBEDDING_DIMENSIONS[current_model]
    stored_dim = GlobalConfigService.load('PILOT_LLM_EMBEDDING_DIMENSIONS', nil).to_i
    return nil if new_dim.nil? || stored_dim.zero? || new_dim == stored_dim

    {
      model: current_model,
      new_dim: new_dim,
      stored_dim: stored_dim
    }
  end

  def write_config(name, value)
    row = InstallationConfig.find_or_initialize_by(name: name)
    row.value = value
    row.locked = false if row.new_record?
    row.save!
  end

  def run_slot_test(slot)
    config = Llm::Config.for_slot(slot)
    return { state: :not_configured, message: 'No provider is configured for this capability.' } if config[:api_key].blank?

    case slot
    when :chat then run_chat_test(config)
    when :embedding then run_embedding_test(config)
    when :audio then run_audio_test(config)
    end
  rescue StandardError => e
    { state: :failed, message: e.message }
  end

  def run_chat_test(config)
    Llm::Config.reset!
    Llm::Config.initialize!

    agent = ::Agents::Agent.new(
      name: 'llm_settings_test',
      instructions: 'Respond with the single word: pong.',
      model: config[:model],
      temperature: 0.0,
      tools: []
    )
    result = ::Agents::Runner.with_agents(agent).run('ping', max_turns: 1)
    return { state: :failed, message: result.error&.message.presence || 'Provider returned a failure with no error message.' } if result.failed?

    { state: :connected, message: 'Provider responded successfully.' }
  end

  def run_embedding_test(config)
    client = OpenAI::Client.new(access_token: config[:api_key], uri_base: "#{config[:endpoint]}/v1")
    response = client.embeddings(parameters: { model: config[:model], input: 'ping' })
    vector = response.dig('data', 0, 'embedding')
    return { state: :failed, message: 'Provider returned no embedding vector.' } if vector.blank?

    { state: :connected, message: "Provider responded successfully — #{vector.length} dimensions." }
  end

  def run_audio_test(_config)
    { state: :not_configured, message: 'Audio transcription is not enabled for this build.' }
  end
end
