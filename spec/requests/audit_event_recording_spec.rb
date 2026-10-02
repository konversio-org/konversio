require 'rails_helper'

RSpec.describe 'Audit event recording', type: :request do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  before { AuditLog.delete_all }

  describe 'message deletion' do
    let(:message) { create(:message, account: account, content: 'original body') }
    let(:conversation) { message.conversation }
    let(:agent) { create(:user, account: account, role: :agent) }

    before { create(:inbox_member, inbox: conversation.inbox, user: agent) }

    def delete_message
      delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
             headers: agent.create_new_auth_token,
             as: :json
    end

    it 'records exactly one entry with a snapshot of the deletion context' do
      delete_message

      entry = AuditLog.where(auditable_type: 'Message', action: 'destroy').last
      expect(response).to have_http_status(:success)
      expect(AuditLog.where(auditable_type: 'Message').count).to eq(1)
      expect(entry.auditable_id).to eq(message.id)
      expect(entry.user_id).to eq(agent.id)
      expect(entry.associated_id).to eq(account.id)
      expect(entry.remote_address).to be_present
      expect(entry.audited_changes).to include(
        'content' => 'original body',
        'display_id' => conversation.display_id,
        'inbox_id' => message.inbox_id,
        'sender_id' => message.sender_id
      )
    end

    it 'does not record a second entry when the message was already deleted' do
      delete_message
      AuditLog.delete_all

      expect { delete_message }.not_to change(AuditLog, :count)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'sign-in and sign-out' do
    let(:user) { create(:user, password: 'Password1!', account: account) }

    before do
      second_account = create(:account)
      create(:account_user, account: second_account, user: user)
    end

    it 'writes one sign-in entry per account the user belongs to' do
      expect do
        post new_user_session_url, params: { email: user.email, password: 'Password1!' }, as: :json
      end.to change(AuditLog, :count).by(2)

      expect(response).to have_http_status(:success)
      entries = AuditLog.where(auditable_type: 'User', action: 'sign_in')
      expect(entries.pluck(:associated_id)).to match_array(user.accounts.ids)
      expect(entries.pluck(:username).uniq).to eq([user.email])
      expect(entries.pluck(:request_uuid).uniq.length).to eq(1)
    end

    it 'writes one sign-out entry per account the user belongs to' do
      expect do
        delete '/auth/sign_out', headers: user.create_new_auth_token
      end.to change(AuditLog, :count).by(2)

      expect(response).to have_http_status(:success)
      expect(AuditLog.where(action: 'sign_out').count).to eq(2)
    end

    it 'still signs the user in when audit recording fails' do
      allow(AuditLog).to receive(:insert_all!).and_raise(StandardError.new('audit down'))

      post new_user_session_url, params: { email: user.email, password: 'Password1!' }, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'governed model changes' do
    let!(:inbox) { create(:inbox, account: account) }

    it 'records the change with the actor email denormalized' do
      Audited::Audit.as_user(admin) do
        expect { inbox.update!(name: 'Renamed inbox') }.to change(AuditLog, :count).by(1)
      end

      entry = AuditLog.last
      expect(entry.action).to eq('update')
      expect(entry.auditable_type).to eq('Inbox')
      expect(entry.username).to eq(admin.email)
      expect(entry.associated_id).to eq(account.id)
    end

    it 'never records a webhook secret' do
      webhook = create(:webhook, account: account)

      Audited::Audit.as_user(admin) do
        webhook.update!(secret: 'top-secret', url: 'https://example.org/hook')
      end

      changes = AuditLog.where(auditable_type: 'Webhook').order(:version).last.audited_changes
      expect(changes).not_to have_key('secret')
      expect(changes).to have_key('url')
    end

    it 'records conversation deletion with only the display number' do
      conversation = create(:conversation, account: account, inbox: inbox)

      expect do
        DeleteObjectJob.perform_now(conversation, admin, '203.0.113.9')
      end.to change(AuditLog, :count).by(1)

      entry = AuditLog.find_by(auditable_type: 'Conversation', action: 'destroy')
      expect(entry.audited_changes).to eq('display_id' => conversation.display_id)
      expect(entry.associated_id).to eq(account.id)
      expect(entry.remote_address).to eq('203.0.113.9')
    end
  end
end
