require 'rails_helper'

RSpec.describe Pilot::CustomToolPolicy, type: :policy do
  subject(:custom_tool_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:custom_tool) { create(:pilot_custom_tool, account: account) }

  let(:administrator_context) { { user: administrator, account: account, account_user: account.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.first } }

  permissions :index?, :show? do
    context 'when administrator' do
      it { expect(custom_tool_policy).to permit(administrator_context, custom_tool) }
    end

    context 'when agent' do
      it { expect(custom_tool_policy).to permit(agent_context, custom_tool) }
    end
  end

  permissions :create?, :update?, :destroy?, :test? do
    context 'when administrator' do
      it { expect(custom_tool_policy).to permit(administrator_context, custom_tool) }
    end

    context 'when agent' do
      it { expect(custom_tool_policy).not_to permit(agent_context, custom_tool) }
    end
  end
end
