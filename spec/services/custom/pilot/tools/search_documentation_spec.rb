require 'rails_helper'

RSpec.describe Custom::Pilot::Tools::SearchDocumentation do
  let(:account) { create(:account) }
  let(:tool) { described_class.new }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ account_id: account.id }))
  end

  it 'has the canonical name and description' do
    expect(tool.name).to eq('search_documentation')
    expect(tool.description).to include('knowledge base')
  end

  it 'reports unavailable when Pilot::AssistantResponse is not defined yet' do
    # Pilot::AssistantResponse ships with Autopilot (section 4); until then
    # `.available?` returns false and the tool is omitted from the runner.
    # We assert the runtime gracefully reports it rather than crashing.
    skip('Pilot::AssistantResponse is defined; section 4 has shipped — update this spec.') if defined?(Pilot::AssistantResponse)

    expect(described_class.available?).to be(false)
    expect(tool.perform(tool_context, query: 'refund')).to match(/not enabled/)
  end

  it 'returns a friendly message when account is missing' do
    empty_ctx = Agents::ToolContext.new(run_context: Agents::RunContext.new({}))
    expect(tool.perform(empty_ctx, query: 'x')).to match(/Account context unavailable/)
  end

  describe 'citation behavior', :pgvector do
    let(:assistant) { create(:pilot_assistant, account: account) }
    let(:ctx_with_assistant) do
      Agents::ToolContext.new(run_context: Agents::RunContext.new({ account_id: account.id, assistant_id: assistant.id }))
    end
    let(:pdf_doc) do
      doc = build(:pilot_document,
                  assistant: assistant,
                  account: account,
                  external_link: "PDF: handbook_#{Time.current.to_i}",
                  name: 'handbook.pdf',
                  content: 'PDF body')
      doc.save!(validate: false)
      doc
    end
    let(:url_doc) do
      create(:pilot_document,
             assistant: assistant,
             account: account,
             external_link: 'https://example.com/refunds',
             name: 'Refunds')
    end
    let(:pdf_response) do
      create(:pilot_assistant_response,
             assistant: assistant,
             account: account,
             question: 'How long for refunds?',
             answer: 'Within 30 days.',
             status: :approved,
             documentable: pdf_doc)
    end
    let(:url_response) do
      create(:pilot_assistant_response,
             assistant: assistant,
             account: account,
             question: 'How long for refunds?',
             answer: 'Within 30 days.',
             status: :approved,
             documentable: url_doc)
    end

    before do
      # Stub the embedding service so we don't hit the LLM. Return any
      # non-empty array; the actual vector contents don't matter once we
      # stub the ActiveRecord ordering call.
      allow(Custom::Pilot::EmbeddingService).to receive(:new)
        .and_return(instance_double(Custom::Pilot::EmbeddingService, embed: [0.1] * 1536))
    end

    it 'defaults new assistants to citation_behavior "on"' do
      expect(create(:pilot_assistant, account: account).citation_behavior).to eq('on')
    end

    it 'includes the Source line for a PDF-backed match when citation is on' do
      assistant.update!(config: assistant.config.merge('citation_behavior' => 'on'))
      stub_ordered_results(pdf_response)

      output = tool.perform(ctx_with_assistant, query: 'refund?')
      expect(output).to include('Q: How long for refunds?')
      expect(output).to include('Source: handbook.pdf')
    end

    it 'suppresses the Source line for a PDF-backed match when citation is off' do
      assistant.update!(config: assistant.config.merge('citation_behavior' => 'off'))
      stub_ordered_results(pdf_response)

      output = tool.perform(ctx_with_assistant, query: 'refund?')
      expect(output).to include('Q: How long for refunds?')
      expect(output).not_to include('Source:')
    end

    it 'keeps the Source URL visible for a URL-backed match when citation is on' do
      assistant.update!(config: assistant.config.merge('citation_behavior' => 'on'))
      stub_ordered_results(url_response)

      output = tool.perform(ctx_with_assistant, query: 'refund?')
      expect(output).to include('Source: https://example.com/refunds')
    end

    it 'keeps the Source URL visible for a URL-backed match even when citation is off' do
      assistant.update!(config: assistant.config.merge('citation_behavior' => 'off'))
      stub_ordered_results(url_response)

      output = tool.perform(ctx_with_assistant, query: 'refund?')
      expect(output).to include('Source: https://example.com/refunds')
    end

    def stub_ordered_results(*rows)
      # Bypass pgvector ordering (no usable embedding in test) and return
      # the row(s) we care about as the query result.
      relation = Pilot::AssistantResponse.where(id: rows.map(&:id))
      allow(Pilot::AssistantResponse).to receive(:where).and_call_original
      allow(Pilot::AssistantResponse).to receive(:where).with(account_id: account.id).and_return(
        instance_double(ActiveRecord::Relation).tap do |r|
          allow(r).to receive(:where).with(status: 'approved').and_return(r)
          allow(r).to receive(:order).and_return(r)
          allow(r).to receive(:limit).and_return(relation)
        end
      )
    end
  end
end
