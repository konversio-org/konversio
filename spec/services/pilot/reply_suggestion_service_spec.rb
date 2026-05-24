require 'rails_helper'

RSpec.describe Pilot::ReplySuggestionService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, display_id: 123) }
  let(:service) do
    described_class.new(
      account: account,
      conversation_display_id: conversation.display_id,
      user: user
    )
  end

  before do
    account.enable_features!(:pilot, :pilot_tasks)
    # Stub the API credentials check to bypass actually hitting OpenAI
    allow(service).to receive(:api_key_configured?).and_return(true)
  end

  describe '#perform' do
    context 'when search documentation is available' do
      before do
        allow(Custom::Pilot::Tools::SearchDocumentation).to receive(:available?).and_return(true)
      end

      it 'wraps SearchDocumentation in the adapter and passes it to make_api_call' do
        expect(service).to receive(:execute_ruby_llm_request) do |opts|
          expect(opts[:tools]).not_to be_empty
          expect(opts[:tools].first).to be_a(Pilot::RubyLlmToolAdapter)
          { message: 'Suggested response' }
        end

        result = service.perform
        expect(result[:message]).to eq('Suggested response')
      end

      it 'registers the tool adapter on the RubyLLM chat instance inside execute_ruby_llm_request' do
        mock_context = instance_double(RubyLLM::Context)
        mock_chat = instance_double(RubyLLM::Chat, add_message: nil, with_instructions: nil, on_end_message: nil)
        mock_response = instance_double(RubyLLM::Message, content: 'Suggested response', input_tokens: 10, output_tokens: 5)

        allow(Llm::Config).to receive(:with_api_key).and_yield(mock_context)
        allow(mock_context).to receive(:chat).and_return(mock_chat)

        expect(mock_chat).to receive(:with_tool).with(an_instance_of(Pilot::RubyLlmToolAdapter)).and_return(mock_chat)
        expect(mock_chat).to receive(:ask).and_return(mock_response)

        result = service.perform
        expect(result[:message]).to eq('Suggested response')
      end

      it 'selects instrument_tool_session when tools are present' do
        expect(service).to receive(:instrument_tool_session).and_call_original
        expect(service).to receive(:execute_ruby_llm_request).and_return({ message: 'Suggested response' })

        service.perform
      end

      it 'includes has_search_tool as true in system prompt variables' do
        vars = service.send(:prompt_variables)
        expect(vars['has_search_tool']).to be(true)
      end
    end

    context 'when search documentation is not available' do
      before do
        allow(Custom::Pilot::Tools::SearchDocumentation).to receive(:available?).and_return(false)
      end

      it 'does not pass the search documentation tool to the LLM' do
        expect(service).to receive(:execute_ruby_llm_request) do |opts|
          expect(opts[:tools]).to be_empty
          { message: 'Suggested response' }
        end

        result = service.perform
        expect(result[:message]).to eq('Suggested response')
      end

      it 'selects instrument_llm_call when tools are empty' do
        expect(service).to receive(:instrument_llm_call).and_call_original
        expect(service).to receive(:execute_ruby_llm_request).and_return({ message: 'Suggested response' })

        service.perform
      end

      it 'includes has_search_tool as false in system prompt variables' do
        vars = service.send(:prompt_variables)
        expect(vars['has_search_tool']).to be(false)
      end
    end

    context 'when search documentation constant is not defined' do
      before do
        hide_const('Custom::Pilot::Tools::SearchDocumentation')
      end

      it 'safely returns false for doc_search_available? and does not pass tools' do
        expect(service).to receive(:execute_ruby_llm_request) do |opts|
          expect(opts[:tools]).to be_empty
          { message: 'Suggested response' }
        end

        service.perform
        expect(service.send(:doc_search_available?)).to be(false)
      end
    end

    it 'adds extra system context before the conversation prompt when provided' do
      service = described_class.new(
        account: account,
        conversation_display_id: conversation.display_id,
        user: user,
        extra_system_context: 'Known facts about this contact: Prefers email'
      )

      messages = service.send(:build_messages)

      expect(messages[1]).to eq(
        role: 'system',
        content: 'Known facts about this contact: Prefers email'
      )
      expect(messages[2][:role]).to eq('user')
    end
  end
end
