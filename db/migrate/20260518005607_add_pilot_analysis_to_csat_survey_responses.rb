class AddPilotAnalysisToCsatSurveyResponses < ActiveRecord::Migration[7.1]
  def change
    change_table :csat_survey_responses, bulk: true do |t|
      t.string :pilot_sentiment
      t.text :pilot_themes, array: true, default: []
      t.boolean :pilot_escalation_recommended, default: false, null: false
    end
  end
end
