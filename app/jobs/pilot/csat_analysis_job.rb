module Pilot
  # Runs sentiment + theme + escalation analysis on a free-text CSAT
  # comment and persists the result on the CsatSurveyResponse row.
  #
  # Enqueued from `CsatSurveyResponse` after_create_commit when:
  #   * `feedback_message` is present, AND
  #   * the account has `pilot_csat_analysis_enabled = true`.
  class CsatAnalysisJob < ApplicationJob
    queue_as :low

    def perform(csat_response_id)
      response = CsatSurveyResponse.find_by(id: csat_response_id)
      return if response.blank?
      return if response.feedback_message.blank?

      account = response.account
      return unless account.respond_to?(:pilot_enabled) && account.pilot_enabled
      return unless account.respond_to?(:pilot_csat_analysis_enabled) && account.pilot_csat_analysis_enabled

      result = Custom::Pilot::CsatAnalysisService.new(
        feedback_message: response.feedback_message,
        account: account
      ).perform

      response.update!(
        pilot_sentiment: result[:sentiment],
        pilot_themes: result[:themes],
        pilot_escalation_recommended: result[:escalation_recommended]
      )
    rescue Custom::Pilot::CsatAnalysisService::FeatureDisabledError => e
      Rails.logger.warn("[pilot.csat_analysis_job] feature disabled for response=#{csat_response_id}: #{e.message}")
    rescue Custom::Pilot::CsatAnalysisService::Error => e
      Rails.logger.error("[pilot.csat_analysis_job] LLM failure for response=#{csat_response_id}: #{e.message}")
    end
  end
end
