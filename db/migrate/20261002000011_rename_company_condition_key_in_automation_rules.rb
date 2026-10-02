class RenameCompanyConditionKeyInAutomationRules < ActiveRecord::Migration[7.1]
  LEGACY_KEY = 'company'.freeze
  STANDARD_KEY = 'company_name'.freeze

  def up
    rename_automation_rule_conditions
    rename_saved_contact_filter_queries
  end

  # Data-preserving rename; rolling back cannot know which keys were renamed,
  # so down is intentionally a no-op.
  def down; end

  private

  def rename_automation_rule_conditions
    AutomationRule.find_each do |rule|
      renamed = rename_standard_company_key(rule.conditions)
      next if renamed == rule.conditions

      rule.update_column(:conditions, renamed) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def rename_saved_contact_filter_queries
    CustomFilter.contact.find_each do |filter|
      query = filter.query.deep_dup
      query['payload'] = rename_standard_company_key(query['payload'])
      next if query['payload'] == filter.query['payload']

      filter.update_column(:query, query) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def rename_standard_company_key(conditions)
    return conditions unless conditions.is_a?(Array)

    conditions.map do |condition|
      next condition unless standard_company_condition?(condition)

      condition.merge('attribute_key' => STANDARD_KEY)
    end
  end

  def standard_company_condition?(condition)
    condition.is_a?(Hash) &&
      condition['attribute_key'] == LEGACY_KEY &&
      condition['custom_attribute_type'].blank? &&
      [nil, '', 'standard'].include?(condition['attribute_model'])
  end
end
