class MakePilotInboxesInboxIdUnique < ActiveRecord::Migration[7.1]
  def up
    # Keep the most recently updated connection for each inbox. Ties fall back
    # to the highest id so the cleanup is deterministic.
    execute <<~SQL.squish
      DELETE FROM pilot_inboxes
      WHERE id NOT IN (
        SELECT DISTINCT ON (inbox_id) id
        FROM pilot_inboxes
        ORDER BY inbox_id, updated_at DESC, id DESC
      )
    SQL

    if index_exists?(:pilot_inboxes, [:pilot_assistant_id, :inbox_id],
                     name: :index_pilot_inboxes_on_pilot_assistant_id_and_inbox_id)
      remove_index :pilot_inboxes, name: :index_pilot_inboxes_on_pilot_assistant_id_and_inbox_id
    end

    if index_exists?(:pilot_inboxes, :inbox_id, name: :index_pilot_inboxes_on_inbox_id)
      remove_index :pilot_inboxes, name: :index_pilot_inboxes_on_inbox_id
    end

    add_index :pilot_inboxes, :inbox_id, unique: true, name: :index_pilot_inboxes_on_inbox_id
  end

  def down
    if index_exists?(:pilot_inboxes, :inbox_id, name: :index_pilot_inboxes_on_inbox_id)
      remove_index :pilot_inboxes, name: :index_pilot_inboxes_on_inbox_id
    end

    unless index_exists?(:pilot_inboxes, :inbox_id, name: :index_pilot_inboxes_on_inbox_id)
      add_index :pilot_inboxes, :inbox_id, name: :index_pilot_inboxes_on_inbox_id
    end

    unless index_exists?(:pilot_inboxes, [:pilot_assistant_id, :inbox_id],
                         name: :index_pilot_inboxes_on_pilot_assistant_id_and_inbox_id)
      add_index :pilot_inboxes, [:pilot_assistant_id, :inbox_id],
                unique: true,
                name: :index_pilot_inboxes_on_pilot_assistant_id_and_inbox_id
    end
  end
end
