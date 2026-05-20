require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Custom::Pilot::DocumentCrawlService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }
  let(:seed_url) { 'https://example.com/help' }

  around do |example|
    original = ENV.fetch('PILOT_FIRECRAWL_API_KEY', nil)
    ENV['PILOT_FIRECRAWL_API_KEY'] = 'firecrawl-key'
    example.run
  ensure
    ENV['PILOT_FIRECRAWL_API_KEY'] = original
  end

  describe '#start' do
    it 'returns the Firecrawl job id on success' do
      stub_request(:post, 'https://api.firecrawl.dev/v1/crawl')
        .with(body: hash_including(url: seed_url, limit: 500, maxDepth: 50))
        .to_return(status: 200, body: { success: true, id: 'fc-job-123' }.to_json)

      result = service.start(seed_url)
      expect(result.success?).to be true
      expect(result.job_id).to eq('fc-job-123')
    end

    it 'returns crawl_start_4xx on a 4xx response' do
      stub_request(:post, 'https://api.firecrawl.dev/v1/crawl')
        .to_return(status: 400, body: 'bad url')

      result = service.start(seed_url)
      expect(result.success?).to be false
      expect(result.error_code).to eq('crawl_start_4xx')
    end

    it 'raises on a 5xx response so Sidekiq retries' do
      stub_request(:post, 'https://api.firecrawl.dev/v1/crawl')
        .to_return(status: 502)

      expect { service.start(seed_url) }.to raise_error(/crawl_start_5xx/)
    end

    it 'returns crawl_parse_error when the response body is not JSON' do
      stub_request(:post, 'https://api.firecrawl.dev/v1/crawl')
        .to_return(status: 200, body: 'not json')

      result = service.start(seed_url)
      expect(result.success?).to be false
      expect(result.error_code).to eq('crawl_parse_error')
    end
  end

  describe '#poll' do
    it 'returns in_progress with the partial pages Firecrawl has scraped so far' do
      body = {
        status: 'scraping',
        total: 5,
        completed: 2,
        data: [
          { markdown: '# Refunds', metadata: { title: 'Refunds', sourceURL: 'https://example.com/help/refunds' } },
          { markdown: '# Shipping', metadata: { title: 'Shipping', url: 'https://example.com/help/shipping' } }
        ]
      }.to_json
      stub_request(:get, 'https://api.firecrawl.dev/v1/crawl/fc-job-123')
        .to_return(status: 200, body: body)

      result = service.poll('fc-job-123')
      expect(result.in_progress?).to be true
      expect(result.pages.map { |p| p[:url] }).to contain_exactly(
        'https://example.com/help/refunds',
        'https://example.com/help/shipping'
      )
    end

    it 'returns in_progress with empty pages when Firecrawl has not started scraping yet' do
      stub_request(:get, 'https://api.firecrawl.dev/v1/crawl/fc-job-123')
        .to_return(status: 200, body: { status: 'scraping', total: 5, completed: 0 }.to_json)

      result = service.poll('fc-job-123')
      expect(result.in_progress?).to be true
      expect(result.pages).to eq([])
    end

    it 'returns completed with extracted pages when the crawl finishes' do
      body = {
        status: 'completed',
        total: 2,
        completed: 2,
        data: [
          { markdown: '# Refunds', metadata: { title: 'Refunds', sourceURL: 'https://example.com/help/refunds' } },
          { markdown: '# Shipping', metadata: { title: 'Shipping', url: 'https://example.com/help/shipping' } }
        ]
      }.to_json
      stub_request(:get, 'https://api.firecrawl.dev/v1/crawl/fc-job-123')
        .to_return(status: 200, body: body)

      result = service.poll('fc-job-123')
      expect(result.completed?).to be true
      expect(result.pages.length).to eq(2)
      expect(result.pages.first).to include(url: 'https://example.com/help/refunds', title: 'Refunds')
      expect(result.pages.last[:url]).to eq('https://example.com/help/shipping')
    end

    it 'returns crawl_empty when completed with zero usable pages' do
      stub_request(:get, 'https://api.firecrawl.dev/v1/crawl/fc-job-123')
        .to_return(status: 200, body: { status: 'completed', data: [] }.to_json)

      result = service.poll('fc-job-123')
      expect(result.failed?).to be true
      expect(result.error_code).to eq('crawl_empty')
    end

    it 'returns crawl_parse_error on malformed JSON' do
      stub_request(:get, 'https://api.firecrawl.dev/v1/crawl/fc-job-123')
        .to_return(status: 200, body: 'not json')

      result = service.poll('fc-job-123')
      expect(result.failed?).to be true
      expect(result.error_code).to eq('crawl_parse_error')
    end
  end
end
