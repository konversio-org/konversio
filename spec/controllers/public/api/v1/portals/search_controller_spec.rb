require 'rails_helper'

RSpec.describe 'Public Portal Search API', type: :request do
  let!(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, slug: 'test-portal', config: { allowed_locales: %w[en es] }, custom_domain: 'www.example.com') }
  let!(:category) { create(:category, name: 'category', portal: portal, account_id: account.id, locale: 'en', slug: 'category_slug') }
  let!(:category_es) { create(:category, name: 'category-es', portal: portal, account_id: account.id, locale: 'es', slug: 'category_slug') }

  before do
    create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id,
                     title: 'Refunds explained', content: 'How to request a refund')
    create(:article, category: category_es, portal: portal, account_id: account.id, author_id: agent.id,
                     title: 'Reembolsos', content: 'Como pedir un refund')
  end

  describe 'GET /hc/:slug/:locale/search' do
    it 'returns matching published articles in the requested locale' do
      get "/hc/#{portal.slug}/en/search", params: { query: 'refund' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Refunds explained')
      expect(response.body).not_to include('Reembolsos')
    end

    it 'excludes draft and archived articles' do
      create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id,
                       title: 'Refund draft', content: 'refund draft content', status: :draft)
      create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id,
                       title: 'Refund archived', content: 'refund archived content', status: :archived)

      get "/hc/#{portal.slug}/en/search", params: { query: 'refund' }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('Refund draft')
      expect(response.body).not_to include('Refund archived')
    end

    it 'returns no results for a blank query' do
      get "/hc/#{portal.slug}/en/search"

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('Refunds explained')
    end

    it 'paginates results at 10 per page' do
      15.times do |index|
        create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id,
                         title: "Refund #{index}", content: 'refund pagination body')
      end

      get "/hc/#{portal.slug}/en/search", params: { query: 'refund' }

      expect(response).to have_http_status(:success)
      expect(response.body.scan('refund pagination body').size).to eq(10)
    end

    it 'renders 404 for an unknown portal' do
      with_modified_env(FRONTEND_URL: 'http://app.test.local') do
        get '/hc/does-not-exist/en/search', params: { query: 'refund' }, headers: { 'Host' => 'app.test.local' }

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
