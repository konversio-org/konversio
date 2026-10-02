json.id resource.id
json.account_id resource.account_id
json.question resource.question
json.answer resource.answer
json.language resource.language
json.source_count resource.source_count
json.status resource.status
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
