require 'rails_helper'

RSpec.describe Pilot::ReplySuggestionService do
  subject do
    described_class.new(
      account: account,
      conversation_display_id: conversation.display_id,
      user: user
    )
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, display_id: 123) }

  before do
    account.enable_features!(:pilot, :pilot_tasks)
    # Stub the API credentials check to bypass actually hitting OpenAI
    allow(subject).to receive(:api_key_configured?).and_return(true)
  end

  describe '#perform' do
    context 'when search documentation is available' do
      before do
        allow(Custom::Pilot::Tools::SearchDocumentation).to receive(:available?).and_return(true)
      end

      it 'wraps SearchDocumentation in the adapter and passes it to make_api_call' do
        expect(subject).to receive(:execute_ruby_llm_request) do |opts|
          expect(opts[:tools]).not_to be_empty
          expect(opts[:tools].first).to be_a(Pilot::RubyLlmToolAdapter)
          { message: 'Suggested response' }
        end

        result = subject.perform
        expect(result[:message]).to eq('Suggested response')
      end

      it 'registers the tool adapter on the RubyLLM chat instance inside execute_ruby_llm_request' do
        mock_context = double('RubyLLM::Context')
        mock_chat = double('RubyLLM::Chat', add_message: nil, with_instructions: nil, on_end_message: nil)
        mock_response = double('Response', content: 'Suggested response', input_tokens: 10, output_tokens: 5)

        allow(Llm::Config).to receive(:with_api_key).and_yield(mock_context)
        allow(mock_context).to receive(:chat).and_return(mock_chat)

        expect(mock_chat).to receive(:with_tool).with(an_instance_of(Pilot::RubyLlmToolAdapter)).and_return(mock_chat)
        expect(mock_chat).to receive(:ask).and_return(mock_response)

        result = subject.perform
        expect(result[:message]).to eq('Suggested response')
      end

      it 'selects instrument_tool_session when tools are present' do
        expect(subject).to receive(:instrument_tool_session).and_call_original
        expect(subject).to receive(:execute_ruby_llm_request).and_return({ message: 'Suggested response' })

        subject.perform
      end

      it 'includes has_search_tool as true in system prompt variables' do
        vars = subject.send(:prompt_variables)
        expect(vars['has_search_tool']).to be(true)
      end
    end

    context 'when search documentation is not available' do
      before do
        allow(Custom::Pilot::Tools::SearchDocumentation).to receive(:available?).and_return(false)
      end

      it 'does not pass the search documentation tool to the LLM' do
        expect(subject).to receive(:execute_ruby_llm_request) do |opts|
          expect(opts[:tools]).to be_empty
          { message: 'Suggested response' }
        end

        result = subject.perform
        expect(result[:message]).to eq('Suggested response')
      end

      it 'selects instrument_llm_call when tools are empty' do
        expect(subject).to receive(:instrument_llm_call).and_call_original
        expect(subject).to receive(:execute_ruby_llm_request).and_return({ message: 'Suggested response' })

        subject.perform
      end

      it 'includes has_search_tool as false in system prompt variables' do
        vars = subject.send(:prompt_variables)
        expect(vars['has_search_tool']).to be(false)
      end
    end

    context 'when search documentation constant is not defined' do
      before do
        hide_const('Custom::Pilot::Tools::SearchDocumentation')
      end

      it 'safely returns false for doc_search_available? and does not pass tools' do
        expect(subject).to receive(:execute_ruby_llm_request) do |opts|
          expect(opts[:tools]).to be_empty
          { message: 'Suggested response' }
        end

        subject.perform
        expect(subject.send(:doc_search_available?)).to be(false)
      end
    end
  end
end
