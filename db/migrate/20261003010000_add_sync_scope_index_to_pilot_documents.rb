class AddSyncScopeIndexToPilotDocuments < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :pilot_documents,
              [:account_id, :assistant_id, :sync_status, :last_synced_at],
              name: 'index_pilot_documents_on_sync_scope',
              algorithm: :concurrently
  end
end
