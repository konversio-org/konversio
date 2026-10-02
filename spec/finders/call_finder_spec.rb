require 'rails_helper'

RSpec.describe CallFinder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:hidden_conversation) { create(:conversation, account: account, inbox: other_inbox, contact: contact) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  def current_for(user)
    Current.account = account
    Current.user = user
    Current.account_user = account.account_users.find_by(user: user)
  end

  def find(user, params = {})
    current_for(user)
    described_class.new(user, account, params).perform
  end

  describe 'visibility' do
    let!(:agent_call) { create(:call, account: account, inbox: inbox, conversation: conversation, accepted_by_agent: agent) }

    before do
      create(:call, account: account, inbox: inbox, conversation: conversation, accepted_by_agent: admin)
      create(:call, account: account, inbox: other_inbox, conversation: hidden_conversation, accepted_by_agent: agent)
      create(:call, account: account, inbox: inbox, conversation: conversation, accepted_by_agent: other_agent)
    end

    it 'shows all calls to an administrator' do
      expect(find(admin)[:count]).to eq(4)
    end

    it 'shows an agent only their accepted calls in accessible conversations' do
      result = find(agent)

      expect(result[:calls]).to contain_exactly(agent_call)
      expect(result[:count]).to eq(1)
    end
  end

  describe 'filters' do
    before { current_for(admin) }

    it 'accepts display form status and direction' do
      create(:call, account: account, inbox: inbox, conversation: conversation, status: 'no_answer', direction: :incoming)
      create(:call, account: account, inbox: inbox, conversation: conversation, status: 'no_answer', direction: :outgoing)
      create(:call, account: account, inbox: inbox, conversation: conversation, status: 'completed', direction: :incoming)

      result = find(admin, status: 'no-answer', direction: 'inbound')

      expect(result[:calls].size).to eq(1)
    end

    it 'filters by date range' do
      travel_to(3.days.ago) { create(:call, account: account, inbox: inbox, conversation: conversation) }
      middle = travel_to(2.days.ago) { create(:call, account: account, inbox: inbox, conversation: conversation) }
      create(:call, account: account, inbox: inbox, conversation: conversation)

      result = find(admin, since: 2.days.ago.beginning_of_day.to_i, until: 2.days.ago.end_of_day.to_i)

      expect(result[:calls].map(&:id)).to contain_exactly(middle.id)
    end
  end

  describe 'pagination' do
    before do
      current_for(admin)
      create_list(:call, 30, account: account, inbox: inbox, conversation: conversation, contact: contact)
    end

    it 'returns 25 newest-first with a total count' do
      result = find(admin, page: 1)

      expect(result[:calls].size).to eq(25)
      expect(result[:count]).to eq(30)
      expect(result[:calls].map(&:created_at)).to eq(result[:calls].map(&:created_at).sort.reverse)
    end
  end
end
