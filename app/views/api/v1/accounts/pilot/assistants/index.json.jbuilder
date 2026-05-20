json.array! @assistants do |assistant|
  json.partial! 'assistant', assistant: assistant
end
