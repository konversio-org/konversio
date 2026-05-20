class RenameCaptainEventsInReportingEvents < ActiveRecord::Migration[7.0]
  EVENT_RENAMES = {
    'conversation_captain_inference_resolved' => 'conversation_pilot_inference_resolved',
    'conversation_captain_inference_handoff' => 'conversation_pilot_inference_handoff'
  }.freeze

  def up
    rename_events(EVENT_RENAMES)
  end

  def down
    rename_events(EVENT_RENAMES.invert)
  end

  private

  def rename_events(mapping)
    mapping.each do |from, to|
      execute(<<~SQL)
        UPDATE reporting_events SET name = '#{to}' WHERE name = '#{from}'
      SQL
    end
  end
end
