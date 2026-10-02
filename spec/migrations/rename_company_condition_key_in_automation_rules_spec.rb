# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261002000011_rename_company_condition_key_in_automation_rules')

RSpec.describe RenameCompanyConditionKeyInAutomationRules do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe '#up' do
    it 'renames the standard company condition key in automation rules' do
      rule = create(
        :automation_rule,
        account: account,
        conditions: [
          { 'attribute_key' => 'company', 'attribute_model' => 'standard', 'custom_attribute_type' => nil,
            'filter_operator' => 'equal_to', 'values' => ['Acme'], 'query_operator' => nil }
        ]
      )

      migration.up

      expect(rule.reload.conditions.first['attribute_key']).to eq('company_name')
    end

    it 'leaves a custom company condition key untouched' do
      rule = create(
        :automation_rule,
        account: account,
        conditions: [
          { 'attribute_key' => 'company', 'attribute_model' => 'contact_attribute',
            'custom_attribute_type' => 'contact_attribute', 'filter_operator' => 'equal_to',
            'values' => ['Acme'], 'query_operator' => nil }
        ]
      )

      migration.up

      expect(rule.reload.conditions.first['attribute_key']).to eq('company')
    end

    it 'renames the standard company key in saved contact filters' do
      filter = create(
        :custom_filter,
        account: account,
        user: user,
        filter_type: :contact,
        query: {
          'payload' => [
            { 'attribute_key' => 'company', 'attribute_model' => 'standard', 'custom_attribute_type' => nil,
              'filter_operator' => 'equal_to', 'values' => ['Acme'], 'query_operator' => nil }
          ]
        }
      )

      migration.up

      expect(filter.reload.query['payload'].first['attribute_key']).to eq('company_name')
    end
  end

  describe '#down' do
    it 'is a safe no-op' do
      rule = create(
        :automation_rule,
        account: account,
        conditions: [{ 'attribute_key' => 'company', 'custom_attribute_type' => nil, 'filter_operator' => 'equal_to', 'values' => ['Acme'] }]
      )

      expect { migration.down }.not_to(change { rule.reload.conditions })
    end
  end
end
