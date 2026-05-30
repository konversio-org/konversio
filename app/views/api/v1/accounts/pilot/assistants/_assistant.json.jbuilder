json.id assistant.id
json.name assistant.name
json.description assistant.description
json.config assistant.config
json.enabled_tool_slugs assistant.enabled_tool_slugs
json.response_guidelines assistant.response_guidelines
json.guardrails assistant.guardrails
json.enabled_inbox_count assistant.pilot_inboxes.count
json.inboxes assistant.inboxes do |inbox|
  json.id inbox.id
  json.name inbox.name
  json.channel_type inbox.channel_type
end
json.created_at assistant.created_at.to_i
json.updated_at assistant.updated_at.to_i
