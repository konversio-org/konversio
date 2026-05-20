class SuperAdmin::LlmSettingsController < SuperAdmin::ApplicationController
  SLOTS = %i[chat embedding audio].freeze

  SLOT_PURPOSES = {
    chat: { label: 'Chat', used_for: 'Replies, summaries, agent reasoning' },
    embedding: { label: 'Embeddings', used_for: 'Search and retrieval' },
    audio: { label: 'Audio', used_for: 'Transcription (plumbed, not yet consumed)' }
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

  private

  def apply_preset(slug)
    Llm::Presets.apply!(slug)
    persist_embedding_dimensions_override(nil)
    GlobalConfig.clear_cache
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

    embedding_dim_override = resolve_embedding_dimensions_override(slot_params, parsed[:embedding][:model])

    ActiveRecord::Base.transaction do
      SLOTS.each do |slot|
        write_config("PILOT_LLM_#{slot.upcase}_PROVIDER", parsed[slot][:provider])
        write_config("PILOT_LLM_#{slot.upcase}_MODEL", parsed[slot][:model])
      end
      persist_embedding_dimensions_override(embedding_dim_override)
      matching = Llm::Presets.matching_current_config_for(parsed)
      write_config(Llm::Presets::PRESET_CONFIG_KEY, matching || Llm::Presets::CUSTOM_SLUG)
    end
    GlobalConfig.clear_cache
    Llm::Config.reset!
    Llm::Config.initialize!

    flash.now[:notice] = 'LLM slot configuration updated. Sanity test results below.'
    render_with_slot_tests
  end

  # Returns the validated embedding dimensions override integer, or nil when
  # the model is in MODEL_DIMENSIONS and the operator left the field blank.
  # Raises ArgumentError when an unknown-model save omits the field, so the
  # show action re-renders with the error flash.
  def resolve_embedding_dimensions_override(slot_params, model)
    embedding_row = slot_params['embedding'] || slot_params[:embedding] || {}
    raw = embedding_row['dimensions'] || (embedding_row.respond_to?(:[]) ? embedding_row[:dimensions] : nil)
    raw = raw.to_s.strip
    known_dim = Custom::Pilot::EmbeddingService::MODEL_DIMENSIONS[model]

    if raw.blank?
      if known_dim.nil?
        raise ArgumentError,
              "Embedding slot: Dimensions is required when the model ('#{model}') is not in the built-in catalog."
      end
      return nil
    end

    value = Integer(raw, 10)
    raise ArgumentError, 'Embedding slot: Dimensions must be a positive integer.' unless value.positive?

    # Drop the override when it just restates the known value — keeps the
    # config row absent unless the operator really meant to override.
    return nil if known_dim == value

    value
  rescue ::ArgumentError, ::TypeError => e
    raise ArgumentError, 'Embedding slot: Dimensions must be a positive integer.' if e.message.include?('invalid value for Integer')

    raise
  end

  def persist_embedding_dimensions_override(value)
    row = InstallationConfig.find_by(name: 'PILOT_LLM_EMBEDDING_DIMENSIONS_OVERRIDE')
    if value.nil?
      row&.destroy
    else
      row ||= InstallationConfig.new(name: 'PILOT_LLM_EMBEDDING_DIMENSIONS_OVERRIDE', locked: false)
      row.value = value.to_s
      row.save!
    end
  end

  def render_with_slot_tests
    @test_results = SLOTS.index_with { |slot| run_slot_test(slot) }
    load_view_state
    render :show
  end

  def load_view_state
    @providers = Llm::ProviderRegistry.known_slugs.map { |slug| Llm::ProviderRegistry.provider(slug) }
    @slots = SLOTS.index_with do |slot|
      {
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

  # Compares the resolved expected dimension (from slot config) against the
  # live pgvector column type. Returns a warning hash on mismatch, an
  # :unknown_model hash when the model isn't in MODEL_DIMENSIONS and no
  # override is set, or nil when everything agrees.
  def embedding_dimension_warning
    column_dim = pilot_assistant_responses_embedding_column_dim
    return nil if column_dim.nil?

    current_model = @slots[:embedding][:model]
    slot_config = ::Llm::Config.for_slot(:embedding)
    begin
      expected_dim = Custom::Pilot::EmbeddingService.expected_dimension(slot_config)
    rescue Custom::Pilot::EmbeddingService::UnknownModelDimensionError
      return { kind: :unknown_model, model: current_model, column_dim: column_dim }
    end

    return nil if expected_dim == column_dim

    { kind: :mismatch, model: current_model, expected_dim: expected_dim, column_dim: column_dim }
  end

  # Queries pg_attribute for the `embedding` column's vector(N) type and
  # returns N as an integer. Returns nil when the table or column is
  # absent (which would imply a not-yet-migrated install).
  def pilot_assistant_responses_embedding_column_dim
    sql = <<~SQL.squish
      SELECT format_type(atttypid, atttypmod) AS sql_type
      FROM pg_attribute
      WHERE attrelid = 'pilot_assistant_responses'::regclass
        AND attname = 'embedding'
        AND NOT attisdropped
    SQL
    row = ActiveRecord::Base.connection.execute(sql).first
    return nil if row.nil?

    match = row['sql_type'].to_s.match(/\Avector\((\d+)\)\z/)
    match && match[1].to_i
  rescue ActiveRecord::StatementInvalid
    nil
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

    begin
      expected = Custom::Pilot::EmbeddingService.expected_dimension(config)
    rescue Custom::Pilot::EmbeddingService::UnknownModelDimensionError => e
      return { state: :failed, message: e.message }
    end

    if vector.length != expected
      return {
        state: :failed,
        message: "Model returned #{vector.length}-dim vectors but you declared #{expected}-dim. " \
                 'Update the Dimensions field or pick a model whose native dimension is ' \
                 "#{expected}."
      }
    end

    { state: :connected, message: "Provider responded successfully — #{vector.length} dimensions." }
  end

  def run_audio_test(_config)
    { state: :not_configured, message: 'Audio transcription is not enabled for this build.' }
  end
end
