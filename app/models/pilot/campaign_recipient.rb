# One row per audience contact of a WhatsApp one-off campaign. It records what
# was sent to that contact and how far the provider took it, so campaigns can
# report outcomes even for contacts that never produced a conversation.
#
# Lifecycle:
#   queued -> sent -> delivered -> read
#   skipped (never attempted) and failed (terminal provider error) are absorbing.
class Pilot::CampaignRecipient < ApplicationRecord
  self.table_name = 'pilot_campaign_recipients'

  belongs_to :account
  belongs_to :campaign
  belongs_to :contact
  belongs_to :inbox, class_name: '::Inbox'

  enum status: {
    queued: 0,
    sent: 1,
    delivered: 2,
    read: 3,
    skipped: 4,
    failed: 5
  }

  # Ranked so webhook updates can be rejected when they would move the recipient
  # backwards; skipped/failed sit outside the ranking because they are terminal.
  PROGRESSION = {
    'sent' => 1,
    'delivered' => 2,
    'read' => 3
  }.freeze

  # The subset of provider delivery states that reconcile an existing send.
  DELIVERY_STATES = (PROGRESSION.keys + ['failed']).freeze

  validates :contact_id, uniqueness: { scope: :campaign_id }
  validates :source_id, uniqueness: true, allow_blank: true

  # Aggregate counts for the campaign analytics endpoint. `delivered` includes
  # recipients who moved on to `read`, and `sent` counts only recipients with a
  # provider message identifier recorded.
  def self.summary_for(campaign)
    scope = campaign.pilot_campaign_recipients
    counts = scope.group(:status).count

    {
      audience: counts.values.sum,
      sent: scope.where.not(source_id: nil).count,
      delivered: counts.fetch('delivered', 0) + counts.fetch('read', 0),
      read: counts.fetch('read', 0),
      failed: counts.fetch('failed', 0),
      skipped: counts.fetch('skipped', 0),
      status_counts: statuses.keys.index_with { |status| counts.fetch(status, 0) }
    }
  end

  def mark_sent!(provider_message_id, content: nil)
    update!(source_id: provider_message_id, status: :sent, sent_at: Time.current,
            message_content: content || message_content, error_code: nil, error_title: nil, error_message: nil)
  end

  def mark_skipped!(reason)
    update!(status: :skipped, error_message: reason)
  end

  def mark_failed!(message:, code: nil, title: nil, at: nil)
    update!(status: :failed, failed_at: at || Time.current, error_code: code, error_title: title, error_message: message)
  end

  # Applies a provider delivery-status webhook. Progression is monotonic so late
  # or out-of-order events can never undo a later state; a failure only sticks
  # while the recipient has not already been delivered or read.
  def apply_whatsapp_status!(event)
    event = event.with_indifferent_access
    incoming = event[:status].to_s
    return unless DELIVERY_STATES.include?(incoming)

    with_lock do
      case incoming
      when 'failed' then apply_failure(event)
      when 'delivered' then apply_delivered(event)
      when 'read' then apply_read(event)
      end
    end
  end

  private

  def apply_failure(event)
    return if delivered? || read? || failed?

    error = Array(event[:errors]).first || {}
    mark_failed!(
      message: failure_message(error),
      code: error[:code],
      title: error[:title],
      at: event_time(event[:timestamp])
    )
  end

  def apply_delivered(event)
    delivered_at_value = event_time(event[:timestamp])
    if read? || delivered?
      update!(delivered_at: delivered_at_value) if delivered_at.blank?
      return
    end

    update!(status: :delivered, delivered_at: delivered_at_value)
  end

  def apply_read(event)
    return if read?

    update!(status: :read, read_at: event_time(event[:timestamp]))
  end

  def failure_message(error)
    error[:error_user_msg].presence ||
      error[:message].presence ||
      error.dig(:error_data, :details).presence ||
      'WhatsApp delivery failed'
  end

  def event_time(timestamp)
    return Time.current if timestamp.blank?

    Time.zone.at(timestamp.to_i)
  end
end
