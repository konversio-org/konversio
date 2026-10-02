class AddListingIndexToAudits < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :audits,
              [:associated_type, :associated_id, :created_at],
              name: 'index_audits_on_associated_and_created_at',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
