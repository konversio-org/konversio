class Api::V1::Accounts::Pilot::PreferencesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :authorize_account_update, only: [:update]

  def show
    render json: preferences_payload
  end

  def update
    params_to_update = pilot_params
    @current_account.pilot_models = params_to_update[:pilot_models] if params_to_update[:pilot_models]
    @current_account.pilot_features = params_to_update[:pilot_features] if params_to_update[:pilot_features]
    @current_account.pilot_document_sync_interval = params_to_update[:pilot_document_sync_interval] if params_to_update[:pilot_document_sync_interval]
    unless params_to_update[:pilot_false_promise_guard_enabled].nil?
      @current_account.pilot_false_promise_guard_enabled = params_to_update[:pilot_false_promise_guard_enabled]
    end
    @current_account.save!

    render json: preferences_payload
  end

  private

  def preferences_payload
    {
      providers: Llm::Models.providers,
      models: Llm::Models.models,
      features: features_with_account_preferences,
      active_provider: active_provider_payload,
      active_slots: active_slots_payload,
      document_sync_interval: @current_account.pilot_document_sync_interval_key,
      document_sync_interval_hours: @current_account.pilot_document_sync_interval_hours,
      false_promise_guard_enabled: @current_account.pilot_false_promise_guard_enabled == true
    }
  end

  def active_provider_payload
    slug = Llm::ProviderRegistry.slot_provider(:chat)
    return nil if slug.nil?

    {
      slug: slug.to_s,
      label: Llm::ProviderRegistry.provider(slug)[:label]
    }
  rescue StandardError
    nil
  end

  def active_slots_payload
    Llm::ProviderRegistry::SLOTS.each_with_object({}) do |slot, h|
      config = Llm::Config.for_slot(slot)
      provider_slug = config[:provider]
      h[slot] = {
        provider: provider_slug ? { slug: provider_slug.to_s, label: Llm::ProviderRegistry.provider(provider_slug)[:label] } : nil,
        model: config[:model].presence
      }
    end
  rescue StandardError
    {}
  end

  def authorize_account_update
    authorize @current_account, :update?
  end

  def pilot_params
    permitted = {}
    permitted[:pilot_models] = merged_pilot_models if params[:pilot_models].present?
    permitted[:pilot_features] = merged_pilot_features if params[:pilot_features].present?
    permitted[:pilot_document_sync_interval] = params[:pilot_document_sync_interval] if params[:pilot_document_sync_interval].present?
    unless params[:pilot_false_promise_guard_enabled].nil?
      permitted[:pilot_false_promise_guard_enabled] = ActiveModel::Type::Boolean.new.cast(params[:pilot_false_promise_guard_enabled])
    end
    permitted
  end

  def merged_pilot_models
    existing_models = @current_account.pilot_models || {}
    existing_models.merge(permitted_pilot_models)
  end

  def merged_pilot_features
    existing_features = @current_account.pilot_features || {}
    existing_features.merge(permitted_pilot_features)
  end

  def permitted_pilot_models
    params.require(:pilot_models).permit(
      :editor, :assistant, :copilot, :label_suggestion,
      :audio_transcription, :help_center_search
    ).to_h.stringify_keys
  end

  def permitted_pilot_features
    params.require(:pilot_features).permit(
      :editor, :assistant, :copilot, :label_suggestion,
      :audio_transcription, :help_center_search
    ).to_h.stringify_keys
  end

  def features_with_account_preferences
    preferences = Current.account.pilot_preferences
    account_features = preferences[:features] || {}
    account_models = preferences[:models] || {}

    Llm::Models.feature_keys.index_with do |feature_key|
      config = Llm::Models.feature_config(feature_key)
      config.merge(
        enabled: account_features[feature_key] == true,
        selected: account_models[feature_key] || config[:default]
      )
    end
  end
end
