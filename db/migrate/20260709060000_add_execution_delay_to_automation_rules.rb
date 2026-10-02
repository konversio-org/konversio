class AddExecutionDelayToAutomationRules < ActiveRecord::Migration[7.1]
  def change
    add_column :automation_rules, :execution_delay, :integer
  end
end
