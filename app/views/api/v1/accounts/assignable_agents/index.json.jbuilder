json.payload do
  json.array! @assignable_agents do |agent|
    json.partial! 'api/v1/models/agent', formats: [:json], resource: agent
  end
end
if @ai_assignees.present?
  json.ai_assignees do
    json.array! @ai_assignees do |entity|
      json.id entity.id
      json.name entity.name
      if entity.is_a?(Pilot::Assistant)
        json.avatar_url entity.avatar_url.presence || entity.default_avatar_url
        json.assignee_type 'Pilot::Assistant'
      else
        json.avatar_url entity.avatar_url.presence
        json.assignee_type 'AgentBot'
      end
    end
  end
end
