# Per-account ActionCable channel that streams Pilot dispatcher events to
# subscribed dashboard clients.
#
# `Custom::Pilot::EventDispatcher` calls
# `ActionCable.server.broadcast("pilot_events_#{account.id}", payload)` for
# every dispatched event, so a subscriber gets a live feed scoped to its
# own account.
#
# Subscription authentication mirrors `RoomChannel`: the client passes its
# `pubsub_token` plus `account_id`, and we verify both the user belongs to
# that account.
class PilotEventsChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_user.blank? || current_account.blank?

    stream_from "pilot_events_#{current_account.id}"
  end

  private

  def current_user
    @current_user ||= User.find_by(pubsub_token: params[:pubsub_token], id: params[:user_id])
  end

  def current_account
    return if current_user.blank?

    @current_account ||= current_user.accounts.find_by(id: params[:account_id])
  end
end
