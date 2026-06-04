class BackfillEditedOnCaptainAssistantResponses < ActiveRecord::Migration[7.0]
  def up
    return unless KonversioApp.enterprise?

    # NOTE: Since there is no way of knowing currently which FAQs were edited by a human
    # we use a heuristic based on time passed between created_at and updated_at.
    # 15 days is arbitrary but seems reasonable for a user to go back and edit an FAQ.
    #
    # Using raw SQL instead of Captain::AssistantResponse (class no longer exists;
    # it was renamed to Pilot::AssistantResponse). The table at this point in the
    # migration sequence is still captain_assistant_responses (renamed to
    # pilot_assistant_responses by 20260517135325_rename_captain_tables_to_pilot.rb).
    execute(<<~SQL)
      UPDATE captain_assistant_responses
      SET edited = TRUE
      WHERE updated_at - created_at > make_interval(days := 15)
    SQL
  end

  def down
    # no-op: rolling back migration of edited column will drop the edited column entirely
  end
end
