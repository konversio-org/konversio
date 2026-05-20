json.partial! 'api/v1/accounts/pilot/documents/document', formats: [:json], document: @document
json.pdf_file_url(
  if @document.pdf_file.attached?
    Rails.application.routes.url_helpers.rails_blob_url(@document.pdf_file, only_path: true)
  end
)
