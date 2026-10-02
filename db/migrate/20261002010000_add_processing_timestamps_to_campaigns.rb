class AddProcessingTimestampsToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :started_at, :datetime
    add_column :campaigns, :completed_at, :datetime
  end
end
