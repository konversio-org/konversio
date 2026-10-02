json.data @suggestions do |suggestion|
  json.partial! 'api/v1/accounts/pilot/faq_suggestions/faq_suggestion', formats: [:json], resource: suggestion
end

json.meta do
  json.current_page @suggestions.current_page
  json.per_page Api::V1::Accounts::Pilot::FaqSuggestionsController::PER_PAGE
  json.total_count @suggestions.total_count
  json.total_pages @suggestions.total_pages
end
