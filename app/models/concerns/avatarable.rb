# frozen_string_literal: true

module Avatarable
  extend ActiveSupport::Concern
  include Rails.application.routes.url_helpers

  included do
    has_one_attached :avatar
    validate :acceptable_avatar, if: -> { avatar.changed? }
    after_save :fetch_avatar_from_gravatar
  end

  def avatar_url
    return url_for(avatar.representation(resize_to_fill: [250, nil])) if avatar.attached? && avatar.representable?

    ''
  end

  def fetch_avatar_from_gravatar
    return unless saved_changes.key?(:email)
    return if email.blank?

    # Incase avatar_url is supplied, we don't want to fetch avatar from gravatar
    # So we will wait for it to be processed
    Avatar::AvatarFromGravatarJob.set(wait: 30.seconds).perform_later(self, email)
  end

  def acceptable_avatar
    return unless avatar.attached?

    errors.add(:avatar, 'is too big') if avatar.byte_size > 1.megabyte

    acceptable_types = ['image/jpeg', 'image/png', 'image/gif'].freeze
    errors.add(:avatar, 'filetype not supported') unless acceptable_types.include?(avatar.content_type)

    validate_avatar_dimensions
  end

  # Enforce reasonable pixel dimensions for avatars (small icons, not full photos).
  def validate_avatar_dimensions
    width = avatar.metadata[:width]
    height = avatar.metadata[:height]
    return if width.blank? || height.blank?
    return unless width > 512 || height > 512

    errors.add(:avatar, 'dimensions are too large (maximum 512x512)')
  end
end
