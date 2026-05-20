json.id resource.id
json.question resource.question
json.answer resource.answer
json.status resource.status
json.edited resource.edited
json.created_at resource.created_at
json.updated_at resource.updated_at

json.assistant do
  if resource.assistant
    json.id resource.assistant.id
    json.name resource.assistant.name
  else
    json.null!
  end
end

doc = resource.documentable
if doc.present?
  doc_name =
    if doc.respond_to?(:name) && doc.name.present?
      doc.name
    elsif doc.respond_to?(:pdf_file) && doc.pdf_file.attached?
      doc.pdf_file.filename.to_s
    elsif doc.respond_to?(:external_link) && doc.external_link.present?
      doc.external_link
    end

  json.documentable do
    json.type resource.documentable_type
    json.id resource.documentable_id
    json.name doc_name
  end
else
  json.documentable nil
end
