json.id document.id
json.assistant_id document.assistant_id
json.external_link document.external_link
json.name(
  if document.pdf_file.attached?
    document.pdf_file.filename.to_s
  elsif document.external_link.present?
    begin
      uri = URI.parse(document.external_link)
      [uri.host, uri.path].compact.join.presence || document.external_link
    rescue URI::InvalidURIError
      document.external_link
    end
  else
    document.name
  end
)
json.status document.status
json.sync_status document.sync_status
json.content_excerpt(document.content.to_s[0, 200])
json.response_count document.responses.count
json.created_at document.created_at.to_i
json.updated_at document.updated_at.to_i
