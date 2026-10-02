# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Audience::Matcher do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, name: 'Jane Doe', email: 'Jane@Example.com',
                     phone_number: '+15551234567', blocked: false)
  end
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def match?(tree)
    described_class.call(tree, contact: contact, conversation: conversation)
  end

  def leaf(attribute_key, operator, values = ['x'])
    { 'attribute_key' => attribute_key, 'filter_operator' => operator, 'values' => values }
  end

  def group(combinator, conditions)
    { 'combinator' => combinator, 'conditions' => conditions }
  end

  it 'matches everything with a blank tree' do
    expect(match?(nil)).to be(true)
    expect(match?({})).to be(true)
  end

  describe 'group combinators' do
    it 'AND requires all children to match' do
      tree = group('and', [leaf('email', 'contains', ['example']), leaf('name', 'equal_to', ['Someone Else'])])

      expect(match?(tree)).to be(false)
    end

    it 'OR requires any child to match' do
      tree = group('or', [leaf('email', 'contains', ['example']), leaf('name', 'equal_to', ['Someone Else'])])

      expect(match?(tree)).to be(true)
    end

    it 'evaluates nested sub-groups' do
      tree = group('and', [
                     leaf('email', 'contains', ['example']),
                     group('or', [leaf('name', 'equal_to', ['Nobody']), leaf('blocked', 'equal_to', [false])])
                   ])

      expect(match?(tree)).to be(true)
    end
  end

  describe 'text semantics' do
    it 'compares case-insensitively' do
      expect(match?(group('and', [leaf('email', 'equal_to', ['jane@example.COM'])]))).to be(true)
      expect(match?(group('and', [leaf('name', 'contains', ['jane'])]))).to be(true)
    end

    it 'supports does_not_contain and not_equal_to' do
      expect(match?(group('and', [leaf('email', 'does_not_contain', ['gmail'])]))).to be(true)
      expect(match?(group('and', [leaf('email', 'not_equal_to', ['other@example.com'])]))).to be(true)
    end

    it 'supports is_present and is_not_present' do
      expect(match?(group('and', [leaf('email', 'is_present', nil)]))).to be(true)
      expect(match?(group('and', [leaf('identifier', 'is_not_present', nil)]))).to be(true)
    end
  end

  describe 'phone semantics' do
    it 'ignores the + prefix' do
      expect(match?(group('and', [leaf('phone_number', 'equal_to', ['15551234567'])]))).to be(true)
    end

    it 'supports starts_with' do
      expect(match?(group('and', [leaf('phone_number', 'starts_with', ['+1555'])]))).to be(true)
      expect(match?(group('and', [leaf('phone_number', 'starts_with', ['+44'])]))).to be(false)
    end
  end

  describe 'label semantics' do
    it 'behaves as a has-tag check' do
      contact.update_labels(%w[vip pilot])

      expect(match?(group('and', [leaf('labels', 'equal_to', ['vip'])]))).to be(true)
      expect(match?(group('and', [leaf('labels', 'equal_to', ['enterprise'])]))).to be(false)
      expect(match?(group('and', [leaf('labels', 'not_equal_to', ['enterprise'])]))).to be(true)
      expect(match?(group('and', [leaf('labels', 'is_present', nil)]))).to be(true)
    end
  end

  describe 'boolean and identity-verification semantics' do
    it 'reads the blocked flag' do
      expect(match?(group('and', [leaf('blocked', 'equal_to', [false])]))).to be(true)
    end

    it 'reads the widget HMAC verification state' do
      contact_inbox.update!(hmac_verified: true)

      expect(match?(group('and', [leaf('identity_verified', 'equal_to', [true])]))).to be(true)
      expect(match?(group('and', [leaf('identity_verified', 'equal_to', [false])]))).to be(false)
    end
  end

  describe 'additional attributes' do
    it 'reads contact additional attributes' do
      contact.update!(additional_attributes: { 'country_code' => 'NL', 'city' => 'Amsterdam' })

      expect(match?(group('and', [leaf('country_code', 'equal_to', ['nl'])]))).to be(true)
      expect(match?(group('and', [leaf('city', 'contains', ['amster'])]))).to be(true)
    end

    it 'reads conversation additional attributes' do
      conversation.update!(additional_attributes: { 'browser_language' => 'en-US' })

      expect(match?(group('and', [leaf('browser_language', 'equal_to', ['en-us'])]))).to be(true)
    end
  end

  describe 'date operators on standard attributes' do
    it 'supports is_greater_than / is_less_than with ISO dates' do
      contact.update!(created_at: 10.days.ago)

      expect(match?(group('and', [leaf('created_at', 'is_less_than', [2.days.ago.to_date.iso8601])]))).to be(true)
      expect(match?(group('and', [leaf('created_at', 'is_greater_than', [2.days.ago.to_date.iso8601])]))).to be(false)
    end

    it 'supports days_before' do
      contact.update!(created_at: 10.days.ago)

      expect(match?(group('and', [leaf('created_at', 'days_before', [5])]))).to be(true)
      expect(match?(group('and', [leaf('created_at', 'days_before', [30])]))).to be(false)
    end
  end

  describe 'custom attributes' do
    before do
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                           attribute_key: 'lifetime_value', attribute_display_type: 'number')
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                           attribute_key: 'renewal_date', attribute_display_type: 'date')
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                           attribute_key: 'subscribed', attribute_display_type: 'checkbox')
    end

    it 'compares numeric custom attributes numerically' do
      contact.update!(custom_attributes: { 'lifetime_value' => 250 })

      expect(match?(group('and', [leaf('lifetime_value', 'is_greater_than', [100])]))).to be(true)
      expect(match?(group('and', [leaf('lifetime_value', 'is_less_than', [100])]))).to be(false)
    end

    it 'never matches range operators with a blank actual value' do
      contact.update!(custom_attributes: {})

      expect(match?(group('and', [leaf('lifetime_value', 'is_greater_than', [100])]))).to be(false)
    end

    it 'never matches range operators with an unparseable actual value' do
      contact.update!(custom_attributes: { 'lifetime_value' => 'not-a-number' })

      expect(match?(group('and', [leaf('lifetime_value', 'is_greater_than', [100])]))).to be(false)
    end

    it 'treats ISO date strings as dates' do
      contact.update!(custom_attributes: { 'renewal_date' => '2027-01-15' })

      expect(match?(group('and', [leaf('renewal_date', 'is_greater_than', ['2026-01-01'])]))).to be(true)
      expect(match?(group('and', [leaf('renewal_date', 'is_less_than', ['2026-01-01'])]))).to be(false)
    end

    it 'treats an unset checkbox as false' do
      contact.update!(custom_attributes: {})

      expect(match?(group('and', [leaf('subscribed', 'equal_to', [false])]))).to be(true)
      expect(match?(group('and', [leaf('subscribed', 'equal_to', [true])]))).to be(false)
    end
  end
end
