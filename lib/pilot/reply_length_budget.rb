# Resolves the character budget a Pilot reply must fit for a given
# conversation, derived from the destination channel's platform constraints.
#
# Resolution precedence:
#   1. Instagram direct-message conversations (conversation type marker) — the
#      DM surface is tighter than the inbox channel alone suggests.
#   2. Twilio inboxes — the channel's medium (SMS vs WhatsApp) decides.
#   3. The inbox's channel type.
#   4. A generous fallback for channels without a tighter platform limit.
#
# A nil conversation (e.g. playground runs) resolves to no budget at all, in
# which case no length disclosure or enforcement applies.
class Pilot::ReplyLengthBudget
  INSTAGRAM_DM_BUDGET = 1_000

  CHANNEL_BUDGETS = {
    'Channel::FacebookPage' => 2_000,
    'Channel::Instagram' => 1_000,
    'Channel::Line' => 5_000,
    'Channel::Sms' => 320,
    'Channel::Telegram' => 4_096,
    'Channel::Tiktok' => 6_000,
    'Channel::Whatsapp' => 4_096
  }.freeze

  TWILIO_MEDIUM_BUDGETS = {
    'sms' => 320,
    'whatsapp' => 1_600
  }.freeze

  DEFAULT_BUDGET = 10_000

  def self.for(conversation)
    return nil if conversation.nil?
    return INSTAGRAM_DM_BUDGET if instagram_direct_message?(conversation)

    inbox = conversation.inbox
    return DEFAULT_BUDGET if inbox.blank?

    channel = inbox.channel
    return twilio_budget(channel) if channel.is_a?(::Channel::TwilioSms)

    CHANNEL_BUDGETS.fetch(inbox.channel_type.to_s, DEFAULT_BUDGET)
  end

  def self.instagram_direct_message?(conversation)
    conversation.additional_attributes&.dig('type') == 'instagram_direct_message'
  end
  private_class_method :instagram_direct_message?

  def self.twilio_budget(channel)
    TWILIO_MEDIUM_BUDGETS.fetch(channel.medium.to_s, DEFAULT_BUDGET)
  end
  private_class_method :twilio_budget
end
