json.data @documents do |document|
  json.partial! 'api/v1/accounts/pilot/documents/document', formats: [:json], document: document
end

json.meta do
  json.current_page @documents.current_page
  json.per_page Api::V1::Accounts::Pilot::DocumentsController::PER_PAGE
  json.total_count @documents.total_count
  json.total_pages @documents.total_pages
end
