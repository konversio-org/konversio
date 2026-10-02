json.payload do
  json.array! @calls, partial: 'api/v1/models/call', as: :call
end

json.meta do
  json.count @calls_count
end
