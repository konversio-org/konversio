json.partial! 'api/v1/accounts/pilot/faq_suggestions/faq_suggestion', formats: [:json], resource: @suggestion

if @observations
  json.observations @observations do |observation|
    json.partial! 'api/v1/accounts/pilot/faq_suggestions/faq_observation', formats: [:json], resource: observation
  end
end
