require 'rails_helper'

RSpec.describe Pilot::Document do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  def build_document(overrides = {})
    build(:pilot_document, { assistant: assistant, account: account, content: nil }.merge(overrides))
  end

  def resolves_to(*addresses)
    allow(Resolv).to receive(:getaddresses).and_return(addresses)
  end

  describe 'sync-state helpers' do
    it 'classifies web vs file-backed documents' do
      web = build_document(external_link: 'https://example.com/help', status: :available)
      pdf = build_document(external_link: 'https://example.com/help.pdf', status: :available)
      markdown = build_document(external_link: nil, status: :available)
      markdown.markdown_file.attach(io: StringIO.new('# Notes'), filename: 'notes.md', content_type: 'text/markdown')

      expect(web).to be_syncable
      expect(web).not_to be_file_document
      expect(pdf).to be_file_document
      expect(pdf).not_to be_syncable
      expect(markdown).to be_file_document
      expect(markdown).not_to be_syncable
    end

    it 'treats never-synced documents as stale' do
      expect(build_document(last_synced_at: nil)).to be_sync_stale
    end

    it 'uses the account cadence to decide staleness' do
      account.pilot_document_sync_interval = 'weekly'
      account.save!

      fresh = build_document(last_synced_at: 3.days.ago)
      stale = build_document(last_synced_at: 10.days.ago)

      expect(stale).to be_sync_stale
      expect(fresh).not_to be_sync_stale
    end

    it 'reports syncing state' do
      expect(build_document(sync_status: :syncing)).to be_sync_in_progress
      expect(build_document(sync_status: :synced)).not_to be_sync_in_progress
    end
  end

  describe 'fingerprint on refresh' do
    let(:document) do
      create(:pilot_document, assistant: assistant, account: account, status: :available,
                              content: 'body', sync_status: :synced, external_link: 'https://example.com/help')
    end

    before do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return(nil)
    end

    it 'records the content fingerprint after a successful refresh' do
      result = Custom::Pilot::DocumentIngestionService::Result.new(success: true, content: 'body')
      service = instance_double(Custom::Pilot::DocumentIngestionService, perform: result)
      allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(service)

      Pilot::Documents::RefreshService.new(document).perform

      expect(document.reload.content_fingerprint).to eq(Digest::SHA256.hexdigest('body'))
    end
  end

  describe '#customer_visible_source_url' do
    def url_for(link)
      build_document(external_link: link, status: :available).customer_visible_source_url
    end

    it 'returns an ordinary public http(s) link as-is' do
      resolves_to('93.184.216.34')
      expect(url_for('https://example.com/help')).to eq('https://example.com/help')
    end

    it 'rejects private, loopback, link-local, and reserved addresses' do
      resolves_to('10.0.0.5')
      expect(url_for('https://example.com/a')).to be_nil
      resolves_to('127.0.0.1')
      expect(url_for('https://example.com/a')).to be_nil
      resolves_to('169.254.1.1')
      expect(url_for('https://example.com/a')).to be_nil
      resolves_to('192.0.2.5')
      expect(url_for('https://example.com/a')).to be_nil
    end

    it 'rejects non-public IPv6 addresses, including IPv4-mapped ones' do
      resolves_to('::1')
      expect(url_for('https://example.com/a')).to be_nil
      resolves_to('fc00::1')
      expect(url_for('https://example.com/a')).to be_nil
      resolves_to('fe80::1')
      expect(url_for('https://example.com/a')).to be_nil
      resolves_to('::ffff:10.0.0.1')
      expect(url_for('https://example.com/a')).to be_nil
    end

    it 'rejects a mixed public/non-public resolution' do
      resolves_to('93.184.216.34', '10.0.0.5')
      expect(url_for('https://example.com/a')).to be_nil
    end

    it 'rejects unresolvable hosts and DNS errors' do
      resolves_to
      expect(url_for('https://example.com/a')).to be_nil

      allow(Resolv).to receive(:getaddresses).and_raise(Resolv::ResolvError)
      expect(url_for('https://example.com/a')).to be_nil
    end

    it 'rejects malformed links and embedded credentials' do
      resolves_to('93.184.216.34')
      expect(url_for('not a url')).to be_nil
      expect(url_for('ftp://example.com/a')).to be_nil
      expect(url_for('https://user:pass@example.com/a')).to be_nil
    end

    it 'rejects PDF paths and file-backed documents' do
      resolves_to('93.184.216.34')
      expect(url_for('https://example.com/help.pdf')).to be_nil

      markdown = build_document(external_link: nil, status: :available)
      markdown.markdown_file.attach(io: StringIO.new('# Notes'), filename: 'notes.md', content_type: 'text/markdown')
      expect(markdown.customer_visible_source_url).to be_nil
    end
  end

  describe 'markdown documents' do
    it 'makes pasted markdown available immediately with a synthetic source link' do
      document = build_document(external_link: nil)
      document.markdown_content = '# Notes'
      document.save!

      expect(document).to be_available
      expect(document.markdown_file).to be_attached
      expect(document.content).to eq('# Notes')
      expect(document.external_link).to start_with(Pilot::Document::MARKDOWN_LINK_PREFIX)
      expect(document).to be_markdown_document
    end

    it 'stores an uploaded .md file as the document source' do
      document = build_document(content: '# Uploaded')
      document.markdown_file.attach(io: StringIO.new('# Uploaded'), filename: 'notes.md', content_type: 'text/markdown')
      document.save!

      expect(document).to be_available
      expect(document.content).to eq('# Uploaded')
    end

    it 'rejects a non-.md upload' do
      document = build_document
      document.markdown_file.attach(io: StringIO.new('hi'), filename: 'notes.txt', content_type: 'text/plain')

      expect(document).not_to be_valid
      expect(document.errors[:markdown_file]).to be_present
    end

    it 'rejects a markdown file with a non-markdown content type' do
      document = build_document
      document.markdown_file.attach(io: StringIO.new('hi'), filename: 'notes.md', content_type: 'application/pdf')

      expect(document).not_to be_valid
      expect(document.errors[:markdown_file]).to be_present
    end

    it 'rejects blank markdown content' do
      document = build_document
      document.markdown_file.attach(io: StringIO.new(''), filename: 'notes.md', content_type: 'text/markdown')

      expect(document).not_to be_valid
      expect(document.errors[:markdown_content]).to be_present
    end

    it 'rejects markdown content over the length cap' do
      document = build_document
      document.markdown_content = 'a' * (Pilot::Document::MARKDOWN_MAX_CHARS + 1)

      expect(document).not_to be_valid
      expect(document.errors[:markdown_content]).to be_present
    end

    it 'rejects a document with both a PDF and a markdown attachment' do
      document = build_document
      document.pdf_file.attach(io: StringIO.new('%PDF-1.4'), filename: 'doc.pdf', content_type: 'application/pdf')
      document.markdown_file.attach(io: StringIO.new('# Notes'), filename: 'notes.md', content_type: 'text/markdown')

      expect(document).not_to be_valid
      expect(document.errors[:base]).to be_present
    end
  end
end
