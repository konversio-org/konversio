require 'rails_helper'

RSpec.describe 'Super Admin accounts API', type: :request do
  include ActiveJob::TestHelper

  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  describe 'GET /super_admin/accounts' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get '/super_admin/accounts'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/accounts'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('New account')
        expect(response.body).to include(account.name)
      end
    end
  end

  describe 'PATCH /super_admin/accounts/{account_id}' do
    before { sign_in(super_admin, scope: :super_admin) }

    def suspension_params(overrides = {})
      {
        account: {
          name: account.name,
          locale: account.locale,
          status: 'suspended'
        }.merge(overrides)
      }
    end

    context 'when suspending an active account' do
      it 'requires a suspension category' do
        patch "/super_admin/accounts/#{account.id}", params: suspension_params(suspension_reason: 'Abusive usage')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload).to be_active
        expect(account.suspension_history).to be_empty
      end

      it 'requires a suspension reason' do
        patch "/super_admin/accounts/#{account.id}", params: suspension_params(suspension_category: 'spam')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload).to be_active
      end

      it 'rejects a reason longer than 256 characters' do
        patch "/super_admin/accounts/#{account.id}",
              params: suspension_params(suspension_category: 'spam', suspension_reason: 'a' * 257)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload).to be_active
      end

      it 'rejects a category outside the allowed list' do
        patch "/super_admin/accounts/#{account.id}",
              params: suspension_params(suspension_category: 'made_up', suspension_reason: 'Abusive usage')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload).to be_active
      end

      it 'suspends the account and records the suspension in history' do
        patch "/super_admin/accounts/#{account.id}",
              params: suspension_params(suspension_category: 'spam', suspension_reason: 'Abusive usage')

        expect(response).to have_http_status(:redirect)
        account.reload
        expect(account).to be_suspended
        expect(account.suspension_history.last).to include('category' => 'spam', 'reason' => 'Abusive usage')
        expect(account.suspension_history.last['suspended_at']).to be_present
      end
    end

    context 'when re-saving an already suspended account' do
      before do
        account.update!(
          status: :suspended,
          internal_attributes: {
            'suspensions' => [{ 'category' => 'spam', 'reason' => 'first note', 'suspended_at' => 1.week.ago.iso8601 }]
          }
        )
      end

      it 'updates the latest event in place without appending' do
        patch "/super_admin/accounts/#{account.id}",
              params: suspension_params(suspension_category: 'other', suspension_reason: 'corrected note')

        expect(response).to have_http_status(:redirect)
        history = account.reload.suspension_history
        expect(history.size).to eq(1)
        expect(history.last).to include('category' => 'other', 'reason' => 'corrected note')
      end
    end

    context 'when reactivating a suspended account' do
      before do
        account.update!(
          status: :suspended,
          internal_attributes: {
            'suspensions' => [{ 'category' => 'spam', 'reason' => 'first note', 'suspended_at' => 1.week.ago.iso8601 }]
          }
        )
      end

      it 'does not require suspension metadata and leaves history unchanged' do
        history_before = account.suspension_history

        patch "/super_admin/accounts/#{account.id}",
              params: { account: { name: account.name, locale: account.locale, status: 'active' } }

        expect(response).to have_http_status(:redirect)
        account.reload
        expect(account).to be_active
        expect(account.suspension_history).to eq(history_before)
      end
    end

    context 'when updating a legacy suspended account with no history' do
      before { account.update!(status: :suspended) }

      it 'does not require metadata' do
        patch "/super_admin/accounts/#{account.id}",
              params: { account: { name: 'Renamed account', locale: account.locale, status: 'suspended' } }

        expect(response).to have_http_status(:redirect)
        expect(account.reload.name).to eq('Renamed account')
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/reset_cache' do
    before do
      create(:label, account: account)
      create(:inbox, account: account)
      create(:team, account: account)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        expect(account.cache_keys.keys).to contain_exactly(:inbox, :label, :team)
        sign_in(super_admin, scope: :super_admin)

        now_timestamp = Time.now.utc.to_i
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('Cache keys cleared')

        range = now_timestamp..(now_timestamp + 10)
        expect(account.reload.cache_keys.values.all? { |v| range.cover?(v.to_i) }).to be(true)
      end
    end
  end

  describe 'DELETE /super_admin/accounts/{account_id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/super_admin/accounts/#{account.id}"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'Deletes the account' do
        total_accounts = Account.count
        sign_in(super_admin, scope: :super_admin)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/super_admin/accounts/#{account.id}"
        end

        expect(Account.count).to eq(total_accounts - 1)
      end
    end
  end
end
