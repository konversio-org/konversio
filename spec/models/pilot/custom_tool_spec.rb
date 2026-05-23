# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::CustomTool do
  describe 'param_schema validation' do
    let(:account) { create(:account) }

    Pilot::CustomTool::ALLOWED_PARAM_TYPES.each do |type|
      it "accepts param type '#{type}'" do
        tool = build(:pilot_custom_tool, account: account, param_schema: [{ 'name' => 'arg', 'type' => type }])
        expect(tool).to be_valid
      end
    end

    it 'rejects an unknown param type' do
      tool = build(:pilot_custom_tool, account: account, param_schema: [{ 'name' => 'arg', 'type' => 'uuid' }])
      expect(tool).not_to be_valid
      expect(tool.errors[:param_schema].join).to include("invalid type 'uuid'")
    end

    it 'rejects a non-array param_schema' do
      tool = build(:pilot_custom_tool, account: account, param_schema: { 'name' => 'arg', 'type' => 'string' })
      expect(tool).not_to be_valid
    end

    it 'requires a name on each entry' do
      tool = build(:pilot_custom_tool, account: account, param_schema: [{ 'type' => 'string' }])
      expect(tool).not_to be_valid
      expect(tool.errors[:param_schema].join).to include("missing 'name'")
    end

    it 'allows blank param_schema' do
      tool = build(:pilot_custom_tool, account: account, param_schema: [])
      expect(tool).to be_valid
    end
  end
end
