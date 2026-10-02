json.id @session.id
json.message_id @message.id
json.model @session.llm_model
json.run_context @session.run_context_entries

json.cited_sources @session.cited_document_ids do |document_id|
  document = @cited_documents[document_id]
  next if document.blank?

  json.id document.id
  json.title document.name.presence || document.external_link
  json.link document.customer_visible_source_url
end

json.used_faqs @session.used_faq_ids do |faq_id|
  faq = @used_faqs[faq_id]
  next if faq.blank?

  json.id faq.id
  json.title faq.question
end

json.scenarios @session.scenario_ids do |scenario_id|
  scenario = @scenarios[scenario_id]
  next if scenario.blank?

  json.id scenario.id
  json.title scenario.title
end
