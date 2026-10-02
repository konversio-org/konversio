# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Audience::TreeValidator do
  let(:account) { create(:account) }

  def leaf(attribute_key, operator, values = ['x'])
    { 'attribute_key' => attribute_key, 'filter_operator' => operator, 'values' => values }
  end

  def group(combinator, conditions)
    { 'combinator' => combinator, 'conditions' => conditions }
  end

  it 'accepts a blank tree' do
    expect(described_class.call(nil, account: account)).to be_nil
    expect(described_class.call({}, account: account)).to be_nil
  end

  it 'accepts a valid root group with leaves' do
    tree = group('and', [leaf('email', 'contains', ['@example.com']), leaf('name', 'equal_to', ['Jane'])])

    expect(described_class.call(tree, account: account)).to be_nil
  end

  it 'accepts one level of nested sub-groups' do
    tree = group('or', [leaf('email', 'contains', ['@example.com']), group('and', [leaf('blocked', 'equal_to', [false])])])

    expect(described_class.call(tree, account: account)).to be_nil
  end

  it 'rejects a group nested inside a sub-group' do
    tree = group('and', [group('or', [group('and', [leaf('email', 'contains', ['x'])])])])

    expect(described_class.call(tree, account: account)).to include('nesting')
  end

  it 'rejects an unknown combinator' do
    expect(described_class.call(group('xor', [leaf('email', 'contains', ['x'])]), account: account)).to include('combinator')
  end

  it 'rejects an empty condition list' do
    expect(described_class.call(group('and', []), account: account)).to include('at least one condition')
  end

  it 'rejects a non-hash root' do
    expect(described_class.call(['not a hash'], account: account)).to include('root')
  end

  it 'rejects an unknown attribute' do
    expect(described_class.call(group('and', [leaf('favorite_color', 'equal_to', ['red'])]),
                                account: account)).to include('unknown audience attribute')
  end

  it 'rejects an operator incompatible with the attribute' do
    tree = group('and', [leaf('created_at', 'contains', ['2026'])])

    expect(described_class.call(tree, account: account)).to include("not allowed for attribute 'created_at'")
  end

  it 'accepts presence-style operators without values' do
    tree = group('and', [leaf('email', 'is_present', nil)])

    expect(described_class.call(tree, account: account)).to be_nil
  end

  it 'rejects values on presence-style operators' do
    tree = group('and', [leaf('email', 'is_present', ['x'])])

    expect(described_class.call(tree, account: account)).to include('does not take comparison values')
  end

  it 'rejects missing values on operators that require them' do
    tree = group('and', [leaf('email', 'equal_to', [])])

    expect(described_class.call(tree, account: account)).to include('requires at least one comparison value')
  end

  context 'with custom attributes' do
    before do
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                           attribute_key: 'lifetime_value', attribute_display_type: 'number')
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                           attribute_key: 'renewal_date', attribute_display_type: 'date')
    end

    it 'accepts range operators for numeric custom attributes' do
      tree = group('and', [leaf('lifetime_value', 'is_greater_than', [100])])

      expect(described_class.call(tree, account: account)).to be_nil
    end

    it 'rejects containment operators for date custom attributes' do
      tree = group('and', [leaf('renewal_date', 'contains', ['2026'])])

      expect(described_class.call(tree, account: account)).to include("not allowed for attribute 'renewal_date'")
    end

    it 'ignores conversation-model custom attributes' do
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                           attribute_key: 'order_id', attribute_display_type: 'text')

      expect(described_class.call(group('and', [leaf('order_id', 'equal_to', ['1'])]), account: account))
        .to include('unknown audience attribute')
    end
  end
end
