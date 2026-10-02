class Pilot::OnboardingHelpCenter::PlanJob < ApplicationJob
  queue_as :low

  def perform(account_id, portal_id, user_id, generation_id)
    tracker = Pilot::OnboardingHelpCenter::GenerationTracker.new(generation_id)
    return if tracker.state.blank? || tracker.terminal?

    account = Account.find_by(id: account_id)
    portal = Portal.find_by(id: portal_id)
    if account.nil? || portal.nil?
      tracker.skip!('source_unavailable')
      return
    end

    Pilot::OnboardingHelpCenter::PlannerService.new(
      account: account, portal: portal, user: User.find_by(id: user_id), generation_id: generation_id
    ).perform
  rescue StandardError => e
    Rails.logger.error "[Onboarding HelpCenter] planning failed for generation #{generation_id}: #{e.message}"
    Pilot::OnboardingHelpCenter::GenerationTracker.new(generation_id).skip!('unexpected_error')
  end
end
