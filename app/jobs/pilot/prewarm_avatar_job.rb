# Processes the padded avatar variant ahead of time so the first widget
# visitor after an avatar change is served a ready file instead of triggering
# synchronous libvips processing on request.
class Pilot::PrewarmAvatarJob < ApplicationJob
  queue_as :low

  def perform(assistant)
    return unless assistant.avatar.attached? && assistant.avatar.representable?

    assistant.avatar_variant.processed
  end
end
