json.partial! 'api/v1/accounts/pilot/documents/document', formats: [:json], document: @document
json.sync_interval_hours Current.account.pilot_document_sync_interval_hours
json.pdf_file_url(
  (Rails.application.routes.url_helpers.rails_blob_url(@document.pdf_file, only_path: true) if @document.pdf_file.attached?)
)
