# frozen_string_literal: true

require 'agents'

Rails.application.config.after_initialize do
  api_key = Llm::Config.api_key
  model = Llm::Config.model_for(:default)
  api_base = Llm::Config.api_base

  if api_key.present?
    Agents.configure do |config|
      config.openai_api_key = api_key
      config.openai_api_base = "#{api_base}/v1"
      config.default_model = model
      config.debug = false
    end
  end
rescue StandardError => e
  Rails.logger.error "Failed to configure AI Agents SDK: #{e.message}"
end
