class Pilot::AssistantAvatarsController < ActionController::Base
  # Serves an assistant's padded avatar PNG directly (not a 302 to a signed blob
  # URL), with immutable cache headers so Cloudflare and browsers cache it like
  # any static asset. The :hash path segment is a content fingerprint that busts
  # the cache when the avatar changes — we serve the current variant regardless.
  def show
    assistant = Pilot::Assistant.find_by(id: params[:id])
    return head :not_found unless assistant&.avatar&.attached? && assistant.avatar.representable?

    variant = assistant.avatar_variant.processed
    response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
    send_data variant.download, type: 'image/png', disposition: 'inline'
  end
end
