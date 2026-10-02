# Delivery-status webhooks can beat the recipient row's transaction to the
# database. This job retries with backoff until the row is visible, then applies
# the provider status; if the row still is not there it gives up with a warning.
class Campaigns::ReconcileRecipientStatusJob < ApplicationJob
  class RecipientNotVisibleError < StandardError; end

  queue_as :low
  retry_on RecipientNotVisibleError, wait: ->(executions) { executions * 2.seconds }, attempts: 5 do |_job, _error|
    Rails.logger.warn 'Campaign recipient delivery status could not be reconciled before giving up'
  end

  def perform(inbox_id, status)
    status = status.with_indifferent_access
    inbox = Inbox.find(inbox_id)
    recipient = Pilot::CampaignRecipient.find_by(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: status[:id]
    )
    raise RecipientNotVisibleError unless recipient

    recipient.apply_whatsapp_status!(status)
  end
end
