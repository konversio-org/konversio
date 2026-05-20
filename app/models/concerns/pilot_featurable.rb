# frozen_string_literal: true

module PilotFeaturable
  extend ActiveSupport::Concern

  included do
    validate :validate_pilot_models

    Llm::Models.feature_keys.each do |feature_key|
      define_method("pilot_#{feature_key}_enabled?") do
        pilot_features_with_defaults[feature_key]
      end

      define_method("pilot_#{feature_key}_model") do
        pilot_models_with_defaults[feature_key]
      end
    end
  end

  def pilot_preferences
    {
      models: pilot_models_with_defaults,
      features: pilot_features_with_defaults
    }.with_indifferent_access
  end

  private

  def pilot_models_with_defaults
    stored_models = pilot_models || {}
    Llm::Models.feature_keys.each_with_object({}) do |feature_key, result|
      stored_value = stored_models[feature_key]
      result[feature_key] = if stored_value.present? && Llm::Models.valid_model_for?(feature_key, stored_value)
                              stored_value
                            else
                              Llm::Models.default_model_for(feature_key)
                            end
    end
  end

  def pilot_features_with_defaults
    stored_features = pilot_features || {}
    Llm::Models.feature_keys.index_with do |feature_key|
      stored_features[feature_key] == true
    end
  end

  def validate_pilot_models
    return if pilot_models.blank?

    pilot_models.each do |feature_key, model_name|
      next if model_name.blank?
      next if Llm::Models.valid_model_for?(feature_key, model_name)

      allowed_models = Llm::Models.models_for(feature_key)
      errors.add(:pilot_models, "'#{model_name}' is not a valid model for #{feature_key}. Allowed: #{allowed_models.join(', ')}")
    end
  end
end
