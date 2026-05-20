json.data @responses do |response|
  json.partial! 'api/v1/accounts/pilot/assistant_responses/assistant_response', formats: [:json], resource: response
end

json.meta do
  json.current_page @responses.current_page
  json.per_page Api::V1::Accounts::Pilot::AssistantResponsesController::PER_PAGE
  json.total_count @responses.total_count
  json.total_pages @responses.total_pages
end
