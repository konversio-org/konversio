json.data @responses do |response|
  json.partial! 'api/v2/accounts/pilot/responses/response', formats: [:json], resource: response
end

json.meta do
  json.current_page @responses.current_page
  json.per_page Api::V2::Accounts::Pilot::ResponsesController::PER_PAGE
  json.total_count @responses.total_count
  json.total_pages @responses.total_pages
end
