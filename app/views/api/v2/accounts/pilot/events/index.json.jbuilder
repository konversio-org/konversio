json.data @events do |event|
  json.id event.id
  json.event_name event.event_name
  json.payload event.payload || {}
  json.related_entity_type event.related_entity_type
  json.related_entity_id event.related_entity_id
  json.created_at event.created_at.iso8601
end

json.meta do
  json.current_page @events.current_page
  json.per_page Api::V2::Accounts::Pilot::EventsController::PER_PAGE
  json.total_count @events.total_count
  json.total_pages @events.total_pages
end
