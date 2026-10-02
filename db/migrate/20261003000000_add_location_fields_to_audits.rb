class AddLocationFieldsToAudits < ActiveRecord::Migration[7.2]
  def change
    change_table :audits, bulk: true do |t|
      t.string :city
      t.string :country
      t.string :country_code
    end
  end
end
