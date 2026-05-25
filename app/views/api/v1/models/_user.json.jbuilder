json.access_token resource.access_token.token
json.account_id resource.active_account_user&.account_id
json.available_name resource.available_name
json.avatar_url resource.avatar_url
json.confirmed resource.confirmed?
json.display_name resource.display_name
json.message_signature resource.message_signature
json.email resource.email
json.hmac_identifier resource.hmac_identifier if GlobalConfig.get('CHATWOOT_INBOX_HMAC_KEY')['CHATWOOT_INBOX_HMAC_KEY'].present?
json.id resource.id
json.inviter_id resource.active_account_user&.inviter_id
json.name resource.name
json.provider resource.provider
json.pubsub_token resource.pubsub_token
json.custom_attributes resource.custom_attributes if resource.custom_attributes.present?
json.role resource.active_account_user&.role
json.ui_settings resource.ui_settings
json.uid resource.uid
json.type resource.type
json.accounts do
  json.array! resource.account_users do |account_user|
    json.id account_user.account_id
    json.name account_user.account.name
    json.status account_user.account.status
    json.active_at account_user.active_at
    json.role account_user.role
    json.permissions account_user.permissions
    # the actual availability user has configured
    json.availability account_user.availability
    # availability derived from presence
    json.availability_status account_user.availability_status
    json.auto_offline account_user.auto_offline
    json.pilot_enabled account_user.account.pilot_enabled
    json.pilot_briefing_enabled account_user.account.pilot_briefing_enabled
    json.pilot_copilot_enabled account_user.account.pilot_copilot_enabled
    json.pilot_autopilot_enabled account_user.account.pilot_autopilot_enabled
    json.pilot_logbook_enabled account_user.account.pilot_logbook_enabled
    json.pilot_tools_enabled account_user.account.pilot_tools_enabled
    json.pilot_autoresolve_enabled account_user.account.pilot_autoresolve_enabled
    json.pilot_summary_enabled account_user.account.pilot_summary_enabled
    json.pilot_csat_analysis_enabled account_user.account.pilot_csat_analysis_enabled
    json.pilot_follow_up_enabled account_user.account.pilot_follow_up_enabled
    json.pilot_rewrite_enabled account_user.account.pilot_rewrite_enabled
    json.pilot_label_suggestion_enabled account_user.account.pilot_label_suggestion_enabled
    json.partial! 'api/v1/models/account_user', account_user: account_user if KonversioApp.enterprise?
  end
end
