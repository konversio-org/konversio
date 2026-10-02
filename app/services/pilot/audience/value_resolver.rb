# Resolves the actual value and comparison kind of an audience attribute key
# against a contact and a conversation. Covers contact standard attributes,
# contact additional attributes, contact labels, conversation additional
# attributes, widget identity-verification (HMAC) state, and contact custom
# attributes (typed per the account's CustomAttributeDefinitions).
class Pilot::Audience::ValueResolver
  CONTACT_ADDITIONAL_KEYS = %w[country_code city company_name].freeze
  CONVERSATION_ADDITIONAL_KEYS = %w[browser_language referer conversation_language].freeze

  def initialize(contact:, conversation:)
    @contact = contact
    @conversation = conversation
  end

  def value_for(key)
    return contact_label_list if key == 'labels'

    resolver = standard_resolvers[key]
    return resolver.call if resolver

    @contact&.custom_attributes&.dig(key) if custom_attribute_definitions.key?(key)
  end

  # How values for this key compare: :text (case-insensitive), :phone
  # (ignores the `+` prefix), :boolean, :checkbox (unset = false), :labels
  # (has-tag), :number, or :date (ISO strings).
  def kind_for(key)
    case key
    when 'phone_number' then :phone
    when 'blocked', 'identity_verified' then :boolean
    when 'labels' then :labels
    when 'created_at', 'last_activity_at' then :date
    else
      custom_attribute_kind(key) || :text
    end
  end

  private

  def standard_resolvers
    contact_resolvers.merge(
      CONTACT_ADDITIONAL_KEYS.index_with { |key| -> { @contact&.additional_attributes&.dig(key) } },
      CONVERSATION_ADDITIONAL_KEYS.index_with { |key| -> { @conversation&.additional_attributes&.dig(key) } }
    )
  end

  def contact_resolvers
    {
      'name' => -> { @contact&.name },
      'email' => -> { @contact&.email },
      'phone_number' => -> { @contact&.phone_number },
      'identifier' => -> { @contact&.identifier },
      'blocked' => -> { @contact&.blocked },
      'identity_verified' => -> { @conversation&.contact_inbox&.hmac_verified },
      'created_at' => -> { @contact&.created_at },
      'last_activity_at' => -> { @contact&.last_activity_at }
    }
  end

  def custom_attribute_kind(key)
    display_type = custom_attribute_definitions[key]&.attribute_display_type
    case display_type
    when 'number', 'currency', 'percent' then :number
    when 'date' then :date
    when 'checkbox' then :checkbox
    end
  end

  def contact_label_list
    @contact&.label_list.to_a
  end

  def custom_attribute_definitions
    @custom_attribute_definitions ||= begin
      account = @conversation&.account || @contact&.account
      account ? account.custom_attribute_definitions.contact_attribute.index_by(&:attribute_key) : {}
    end
  end
end
