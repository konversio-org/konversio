# Validates a Pilot audience condition tree stored in
# `Pilot::Assistant#config['audience']`.
#
# A tree is a recursive structure: a **group** node carries a combinator
# (`and`/`or`) and a non-empty `conditions` array; a **leaf** node carries an
# `attribute_key`, a `filter_operator`, and `values`. Nesting is limited to a
# root group, at most one level of sub-groups, and leaves (depth 3).
#
# The attribute/operator vocabulary mirrors the core (MIT) contact filter
# system so an audience matches the same contacts an equivalent segment
# would. Operators are checked per standard attribute and per custom
# attribute display type from the account's CustomAttributeDefinitions.
class Pilot::Audience::TreeValidator
  MAX_GROUP_DEPTH = 2 # root group + one sub-group level; leaves live at depth 3
  COMBINATORS = %w[and or].freeze
  NO_VALUE_OPERATORS = %w[is_present is_not_present].freeze

  EQUALITY_OPERATORS = %w[equal_to not_equal_to].freeze
  CONTAINMENT_OPERATORS = %w[equal_to not_equal_to contains does_not_contain].freeze
  TEXT_OPERATORS = %w[equal_to not_equal_to contains does_not_contain is_present is_not_present].freeze
  PRESENCE_OPERATORS = %w[equal_to not_equal_to is_present is_not_present].freeze
  DATE_OPERATORS = %w[is_greater_than is_less_than days_before].freeze
  NUMERIC_OPERATORS = %w[equal_to not_equal_to is_greater_than is_less_than is_present is_not_present].freeze

  # Standard audience attributes (contact, contact-additional,
  # conversation-additional, and widget identity state) with the operators
  # each supports.
  STANDARD_ATTRIBUTES = {
    'name' => TEXT_OPERATORS,
    'email' => TEXT_OPERATORS,
    'phone_number' => TEXT_OPERATORS + ['starts_with'],
    'identifier' => PRESENCE_OPERATORS,
    'country_code' => PRESENCE_OPERATORS,
    'city' => TEXT_OPERATORS,
    'company_name' => TEXT_OPERATORS,
    'blocked' => EQUALITY_OPERATORS,
    'labels' => PRESENCE_OPERATORS,
    'identity_verified' => EQUALITY_OPERATORS,
    'created_at' => DATE_OPERATORS,
    'last_activity_at' => DATE_OPERATORS,
    'browser_language' => EQUALITY_OPERATORS,
    'referer' => CONTAINMENT_OPERATORS,
    'conversation_language' => EQUALITY_OPERATORS
  }.freeze

  # Operators per custom-attribute display type.
  CUSTOM_ATTRIBUTE_OPERATORS = {
    'text' => TEXT_OPERATORS,
    'link' => TEXT_OPERATORS,
    'number' => NUMERIC_OPERATORS,
    'currency' => NUMERIC_OPERATORS,
    'percent' => NUMERIC_OPERATORS,
    'date' => NUMERIC_OPERATORS,
    'list' => PRESENCE_OPERATORS,
    'checkbox' => EQUALITY_OPERATORS
  }.freeze

  def self.call(tree, account: nil)
    new(tree, account: account).call
  end

  def initialize(tree, account: nil)
    @tree = tree
    @account = account
  end

  # Returns the first validation error message, or nil when the tree is valid.
  def call
    return nil if @tree.blank?
    return 'audience root must be a condition group' unless @tree.is_a?(Hash)

    @error = nil
    validate_group(normalize_node(@tree), 1)
    @error
  end

  private

  def normalize_node(node)
    node.respond_to?(:to_unsafe_h) ? node.to_unsafe_h : node.to_h.deep_stringify_keys
  rescue StandardError
    {}
  end

  def validate_group(node, depth)
    return if @error
    return fail_with('audience nesting is limited to one sub-group level') if depth > MAX_GROUP_DEPTH

    combinator = node['combinator'].to_s.downcase
    return fail_with("group combinator must be one of: #{COMBINATORS.join(', ')}") unless COMBINATORS.include?(combinator)

    conditions = node['conditions']
    return fail_with('group must contain at least one condition') unless conditions.is_a?(Array) && conditions.any?

    conditions.each do |child|
      child = normalize_node(child)
      if group_node?(child)
        validate_group(child, depth + 1)
      else
        validate_leaf(child)
      end
      break if @error
    end
  end

  def group_node?(node)
    node['combinator'].present? || (node.key?('conditions') && node['attribute_key'].blank?)
  end

  def validate_leaf(leaf)
    key = leaf['attribute_key'].to_s
    return fail_with('condition is missing an attribute key') if key.blank?

    allowed = allowed_operators_for(key)
    return fail_with("unknown audience attribute: #{key}") if allowed.nil?

    operator = leaf['filter_operator'].to_s
    return fail_with("operator '#{operator}' is not allowed for attribute '#{key}'") unless allowed.include?(operator)

    validate_values(leaf, operator)
  end

  def validate_values(leaf, operator)
    values = leaf['values']

    if NO_VALUE_OPERATORS.include?(operator)
      fail_with("operator '#{operator}' does not take comparison values") if values.present?
      return
    end

    entries = values.is_a?(Array) ? values : [values].compact
    fail_with("operator '#{operator}' requires at least one comparison value") if entries.blank? || entries.all?(&:blank?)
  end

  def allowed_operators_for(key)
    STANDARD_ATTRIBUTES[key] || custom_attribute_operators(key)
  end

  def custom_attribute_operators(key)
    definition = custom_attribute_definitions[key]
    return nil if definition.blank?

    CUSTOM_ATTRIBUTE_OPERATORS[definition.attribute_display_type] || TEXT_OPERATORS
  end

  def custom_attribute_definitions
    @custom_attribute_definitions ||= @account ? @account.custom_attribute_definitions.contact_attribute.index_by(&:attribute_key) : {}
  end

  def fail_with(message)
    @error = message
  end
end
