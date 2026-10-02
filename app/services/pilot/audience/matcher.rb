# In-memory evaluation of a Pilot audience condition tree against a contact
# and a conversation. A blank tree matches everything.
#
# Comparison semantics mirror the core contact filter system: text compares
# case-insensitively, phone numbers ignore the `+` prefix, label conditions
# are has-tag checks, unset checkbox custom attributes count as false,
# numeric custom attribute types compare numerically, ISO date strings are
# treated as dates, and blank or unparseable actual values never match range
# or date operators.
class Pilot::Audience::Matcher
  def self.call(tree, contact:, conversation:)
    return true if tree.blank?

    new(tree, contact: contact, conversation: conversation).match?
  end

  def initialize(tree, contact:, conversation:)
    @tree = tree.is_a?(Hash) ? tree.deep_stringify_keys : {}
    @resolver = ::Pilot::Audience::ValueResolver.new(contact: contact, conversation: conversation)
  end

  def match?
    evaluate_group(@tree)
  rescue StandardError => e
    Rails.logger.warn("[pilot.audience.matcher] evaluation failed: #{e.class}: #{e.message}")
    false
  end

  private

  def evaluate_group(node)
    results = Array(node['conditions']).map { |child| evaluate_node(child.is_a?(Hash) ? child.deep_stringify_keys : {}) }
    node['combinator'].to_s.downcase == 'or' ? results.any? : results.all?
  end

  def evaluate_node(node)
    return evaluate_group(node) if node['combinator'].present? || (node.key?('conditions') && node['attribute_key'].blank?)

    evaluate_leaf(node)
  end

  def evaluate_leaf(leaf)
    key = leaf['attribute_key'].to_s
    actual = @resolver.value_for(key)
    apply_operator(leaf['filter_operator'].to_s, actual, Array(leaf['values']), @resolver.kind_for(key))
  end

  def apply_operator(operator, actual, values, kind)
    case operator
    when 'is_present' then present_value?(actual)
    when 'is_not_present' then !present_value?(actual)
    when 'equal_to' then matches_any?(actual, values, kind)
    when 'not_equal_to' then negated_match?(actual, kind) { matches_any?(actual, values, kind) }
    when 'contains' then present_value?(actual) && values.any? { |value| text_include?(actual, value) }
    when 'does_not_contain' then negated_match?(actual, kind) { values.any? { |value| text_include?(actual, value) } }
    when 'starts_with' then present_value?(actual) && values.any? { |value| text_starts_with?(actual, value, kind) }
    else apply_range_operator(operator, actual, values.first, kind)
    end
  end

  def apply_range_operator(operator, actual, raw_value, kind)
    case operator
    when 'is_greater_than' then range_compare(actual, raw_value, kind, &:positive?)
    when 'is_less_than' then range_compare(actual, raw_value, kind, &:negative?)
    when 'days_before' then days_before?(actual, raw_value)
    else false
    end
  end

  # SQL-style NULL semantics: negations over a blank actual value never match,
  # except for kinds with a definite blank meaning (labels list, booleans).
  def negated_match?(actual, kind)
    return !yield if %i[labels boolean checkbox].include?(kind)

    present_value?(actual) && !yield
  end

  def matches_any?(actual, values, kind)
    return labels_match?(actual, values) if kind == :labels
    return false unless actual_comparable?(actual, kind)

    values.any? { |value| value_matches?(actual, value, kind) }
  end

  def labels_match?(actual, values)
    label_list = Array(actual).map { |label| label.to_s.downcase }
    values.any? { |value| label_list.include?(value.to_s.downcase) }
  end

  def value_matches?(actual, value, kind)
    case kind
    when :phone then normalize_phone(actual).casecmp?(normalize_phone(value))
    when :boolean, :checkbox then cast_boolean(actual) == cast_boolean(value)
    when :number then numeric_value(actual) == numeric_value(value)
    when :date then date_value(actual) == date_value(value)
    else actual.to_s.casecmp?(value.to_s)
    end
  end

  def text_include?(actual, value)
    actual.to_s.downcase.include?(value.to_s.downcase)
  end

  def text_starts_with?(actual, value, kind)
    source = kind == :phone ? normalize_phone(actual) : actual.to_s.downcase
    prefix = kind == :phone ? normalize_phone(value) : value.to_s.downcase
    source.start_with?(prefix)
  end

  def range_compare(actual, raw_value, kind)
    return false unless actual_comparable?(actual, kind)

    left = kind == :date ? date_value(actual) : numeric_value(actual)
    right = kind == :date ? date_value(raw_value) : numeric_value(raw_value)
    return false if left.nil? || right.nil?

    yield(left <=> right)
  end

  def days_before?(actual, raw_value)
    date = date_value(actual)
    days = Integer(raw_value, exception: false)
    return false if date.nil? || days.nil? || days.negative?

    date < (Time.zone.today - days.days)
  end

  # Blank counts as a definite value only for kinds with an implicit default
  # (checkbox unset = false). Everything else is non-comparable when blank.
  def actual_comparable?(actual, kind)
    %i[boolean checkbox].include?(kind) || present_value?(actual)
  end

  def present_value?(actual)
    case actual
    when nil then false
    when String then actual.present?
    when Array then actual.any?
    else true
    end
  end

  def cast_boolean(value)
    return false if value.nil? || (value.is_a?(String) && value.blank?)

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def normalize_phone(value)
    value.to_s.delete('+')
  end

  def numeric_value(value)
    BigDecimal(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def date_value(value)
    case value
    when Date, Time, DateTime, ActiveSupport::TimeWithZone then value.to_date
    else Date.iso8601(value.to_s)
    end
  rescue ArgumentError, TypeError
    nil
  end
end
