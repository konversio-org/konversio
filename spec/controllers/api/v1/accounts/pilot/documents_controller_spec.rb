require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::Documents', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/documents" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
    # Ingestion/refresh runs async — stub the jobs so creates/refreshes don't
    # actually hit Firecrawl / pdf-reader during these tests.
    allow(Pilot::Documents::CrawlJob).to receive(:perform_later)
    allow(Pilot::Documents::RefreshJob).to receive(:perform_later)
    allow(Pilot::DocumentResponseBuilderJob).to receive(:perform_later)
  end

  describe 'GET /api/v1/accounts/:account_id/pilot/documents' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get base_url, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the pilot_autopilot feature is disabled' do
      it 'returns 403' do
        account.disable_features!(:pilot_autopilot)

        get base_url, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated' do
      it 'returns an empty data array when no documents exist' do
        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['data']).to eq([])
        expect(response.parsed_body['meta']).to include('current_page' => 1, 'total_count' => 0, 'total_pages' => 0)
      end

      it 'filters by assistant_id when provided' do
        doc = create(:pilot_document, assistant: assistant, account: account)
        other_assistant = create(:pilot_assistant, account: account)
        create(:pilot_document, assistant: other_assistant, account: account)

        get base_url, params: { assistant_id: assistant.id }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        ids = response.parsed_body['data'].pluck('id')
        expect(ids).to contain_exactly(doc.id)
      end

      it 'returns pagination meta' do
        create_list(:pilot_document, 3, assistant: assistant, account: account)

        get base_url, headers: admin.create_new_auth_token, as: :json

        meta = response.parsed_body['meta']
        expect(meta).to include('current_page' => 1, 'total_count' => 3, 'total_pages' => 1, 'per_page' => 25)
      end

      it 'allows read access for agents' do
        create(:pilot_document, assistant: assistant, account: account)

        get base_url, headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pilot/documents/:id' do
    let(:document) { create(:pilot_document, assistant: assistant, account: account) }

    it 'returns the document for admins' do
      get "#{base_url}/#{document.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(document.id)
      expect(response.parsed_body['assistant_id']).to eq(assistant.id)
    end

    it 'returns 404 for cross-account access' do
      other_doc = create(:pilot_document, assistant: create(:pilot_assistant, account: create(:account)))

      get "#{base_url}/#{other_doc.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pilot/documents' do
    it 'returns 403 when an agent tries to create' do
      post base_url,
           params: { document: { assistant_id: assistant.id, external_link: 'https://example.com/help' } },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a document from an external_link and enqueues the crawl job' do
      expect do
        post base_url,
             params: { document: { assistant_id: assistant.id, external_link: 'https://example.com/help' } },
             headers: admin.create_new_auth_token,
             as: :json
      end.to change(Pilot::Document, :count).by(1)

      expect(response).to have_http_status(:created)
      doc = Pilot::Document.last
      expect(doc.external_link).to eq('https://example.com/help')
      expect(doc.status).to eq('in_progress')
      expect(Pilot::Documents::CrawlJob).to have_received(:perform_later).with(doc.id)
    end

    it 'returns 422 when the external_link is malformed' do
      post base_url,
           params: { document: { assistant_id: assistant.id, external_link: 'not a url' } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 when neither external_link nor pdf_file is provided' do
      post base_url,
           params: { document: { assistant_id: assistant.id } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'creates a document from a PDF upload and enqueues the crawl job' do
      pdf = Tempfile.new(['sample', '.pdf'])
      pdf.binmode
      pdf.write("%PDF-1.4\n%%EOF\n")
      pdf.rewind

      uploaded = Rack::Test::UploadedFile.new(pdf.path, 'application/pdf', true)

      expect do
        post base_url,
             params: { document: { assistant_id: assistant.id, pdf_file: uploaded } },
             headers: admin.create_new_auth_token
      end.to change(Pilot::Document, :count).by(1)

      expect(response).to have_http_status(:created)
      doc = Pilot::Document.last
      expect(doc.pdf_file).to be_attached
      expect(Pilot::Documents::CrawlJob).to have_received(:perform_later).with(doc.id)
    ensure
      pdf&.close
      pdf&.unlink
    end

    it 'returns 422 when assistant_id is missing' do
      post base_url,
           params: { document: { external_link: 'https://example.com/help' } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 404 when assistant belongs to another account' do
      other_assistant = create(:pilot_assistant, account: create(:account))

      post base_url,
           params: { document: { assistant_id: other_assistant.id, external_link: 'https://example.com/help' } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/pilot/documents/:id' do
    let!(:document) { create(:pilot_document, assistant: assistant, account: account) }

    it 'destroys the document when admin' do
      expect do
        delete "#{base_url}/#{document.id}", headers: admin.create_new_auth_token, as: :json
      end.to change(Pilot::Document, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'returns 403 when an agent tries to destroy' do
      delete "#{base_url}/#{document.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for cross-account destroy' do
      other_doc = create(:pilot_document, assistant: create(:pilot_assistant, account: create(:account)))

      delete "#{base_url}/#{other_doc.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pilot/documents/:id/refresh' do
    let(:document) do
      create(:pilot_document, assistant: assistant, account: account,
                              status: :available, sync_status: :synced,
                              external_link: 'https://example.com/help')
    end

    it 'enqueues an immediate refresh for an available web document' do
      post "#{base_url}/#{document.id}/refresh", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:accepted)
      expect(Pilot::Documents::RefreshJob).to have_received(:perform_later).with(document.id)
      document.reload
      expect(document.sync_status).to eq('syncing')
      expect(document.last_sync_attempted_at).to be_present
      expect(document.refresh_phase).to eq('queued')
    end

    it 'rejects file-backed documents' do
      pdf = create(:pilot_document, assistant: assistant, account: account,
                                    status: :available, external_link: 'PDF: handbook.pdf')

      post "#{base_url}/#{pdf.id}/refresh", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Pilot::Documents::RefreshJob).not_to have_received(:perform_later)
    end

    it 'rejects documents that are not available yet' do
      in_progress = create(:pilot_document, assistant: assistant, account: account,
                                            status: :in_progress, sync_status: nil)

      post "#{base_url}/#{in_progress.id}/refresh", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Pilot::Documents::RefreshJob).not_to have_received(:perform_later)
    end

    it 'returns 403 for agents' do
      post "#{base_url}/#{document.id}/refresh", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'markdown documents' do
    it 'creates an available document from pasted markdown' do
      expect do
        post base_url,
             params: { document: { assistant_id: assistant.id, markdown_content: '# Notes' } },
             headers: admin.create_new_auth_token,
             as: :json
      end.to change(Pilot::Document, :count).by(1)

      expect(response).to have_http_status(:created)
      doc = Pilot::Document.last
      expect(doc).to be_available
      expect(doc.markdown_file).to be_attached
      expect(doc.content).to eq('# Notes')
      expect(doc.external_link).to start_with(Pilot::Document::MARKDOWN_LINK_PREFIX)
      expect(Pilot::Documents::CrawlJob).not_to have_received(:perform_later)
    end

    it 'creates an available document from an uploaded .md file' do
      file = Tempfile.new(['notes', '.md'])
      file.write('# Uploaded notes')
      file.rewind

      post base_url,
           params: { document: { assistant_id: assistant.id, markdown_file: Rack::Test::UploadedFile.new(file.path, 'text/markdown', true) } },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      doc = Pilot::Document.last
      expect(doc).to be_available
      expect(doc.markdown_file).to be_attached
      expect(doc.content).to include('Uploaded notes')
    ensure
      file&.close
      file&.unlink
    end

    it 'rejects a non-markdown upload' do
      file = Tempfile.new(['notes', '.txt'])
      file.write('plain text')
      file.rewind

      post base_url,
           params: { document: { assistant_id: assistant.id, markdown_file: Rack::Test::UploadedFile.new(file.path, 'text/plain', true) } },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    ensure
      file&.close
      file&.unlink
    end

    it 'rejects oversized pasted markdown' do
      post base_url,
           params: { document: { assistant_id: assistant.id, markdown_content: 'a' * (Pilot::Document::MARKDOWN_MAX_CHARS + 1) } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'sync-state and source filters and payload fields' do
    it 'exposes sync fields and the account cadence' do
      document = create(:pilot_document, assistant: assistant, account: account,
                                         status: :available, sync_status: :synced,
                                         last_synced_at: 1.hour.ago, last_sync_attempted_at: 1.hour.ago)

      get "#{base_url}/#{document.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include(
        'sync_status' => 'synced',
        'source_type' => 'web',
        'sync_interval_hours' => 24
      )
      expect(body.keys).to include('last_synced_at', 'last_sync_attempted_at', 'last_sync_failure_category', 'refresh_phase')
    end

    it 'filters by source type' do
      web = create(:pilot_document, assistant: assistant, account: account, status: :available)
      create(:pilot_document, assistant: assistant, account: account, status: :available, external_link: 'PDF: handbook.pdf')
      markdown = create(:pilot_document, assistant: assistant, account: account, status: :available, external_link: 'MD: notes.md')
      create(:pilot_document, assistant: assistant, account: account, status: :available, external_link: 'https://example.com/a.pdf')

      get base_url, params: { source: 'markdown' }, headers: admin.create_new_auth_token, as: :json
      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to contain_exactly(markdown.id)
      expect(ids).not_to include(web.id)
    end

    it 'filters by cadence-aware staleness' do
      account.pilot_document_sync_interval = 'weekly'
      account.save!
      stale = create(:pilot_document, assistant: assistant, account: account,
                                      status: :available, sync_status: :synced, last_synced_at: 10.days.ago)
      fresh = create(:pilot_document, assistant: assistant, account: account,
                                      status: :available, sync_status: :synced, last_synced_at: 3.days.ago)

      get base_url, params: { sync_state: 'stale' }, headers: admin.create_new_auth_token, as: :json
      ids = response.parsed_body['data'].pluck('id')

      expect(ids).to include(stale.id)
      expect(ids).not_to include(fresh.id)
    end
  end
end
