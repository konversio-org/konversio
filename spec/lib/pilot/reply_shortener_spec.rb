# rubocop:disable RSpec/VerifiedDoubles
require 'rails_helper'

RSpec.describe Pilot::ReplyShortener do
  let(:original) do
    Pilot::StructuredReply.new([
                                 { text: 'First part with quite a lot of detail.', citations: [1, 2] },
                                 { text: 'Second part also rather wordy.', citations: [3] }
                               ])
  end
  let(:run_result) do
    Agents::RunResult.new(
      output: '{"parts":[{"text":"First part with quite a lot of detail.","source_indexes":[1,2]}]}',
      messages: [
        { role: :user, content: 'question' },
        { role: :assistant, content: '{"parts":[{"text":"First part"}]}', agent_name: 'assistant' }
      ],
      usage: nil,
      error: nil,
      context: {}
    )
  end
  let(:shortened_output) do
    { parts: [{ text: 'First part, shorter.', source_indexes: [1, 2] }, { text: 'Second, shorter.', source_indexes: [3] }] }.to_json
  end

  def stub_shortening_run(output:, failed: false)
    result = double('RunResult', output: output, failed?: failed, error: failed ? StandardError.new('boom') : nil)
    runner = double('AgentRunner')
    allow(runner).to receive(:run).and_return(result)
    allow(Agents::Runner).to receive(:with_agents).and_return(runner)
    runner
  end

  def call_shortener(citations_enabled: true)
    described_class.call(
      run_result: run_result,
      structured_reply: original,
      text_budget: 80,
      citations_enabled: citations_enabled,
      model: 'gpt-test'
    )
  end

  it 'returns a structured reply with shortened texts and the original citations re-attached' do
    stub_shortening_run(output: shortened_output)

    final = call_shortener

    expect(final.parts.map(&:text)).to eq(['First part, shorter.', 'Second, shorter.'])
    expect(final.parts.map(&:citations)).to eq([[1, 2], [3]])
  end

  it 'runs the shortening pass single-turn at temperature 0' do
    runner = stub_shortening_run(output: shortened_output)
    captured_agent = nil
    allow(Agents::Agent).to receive(:new).and_wrap_original do |method, **kwargs|
      captured_agent = kwargs
      method.call(**kwargs)
    end

    call_shortener

    expect(captured_agent[:temperature]).to eq(0)
    expect(captured_agent[:tools]).to eq([])
    expect(runner).to have_received(:run).with(anything, max_turns: 1)
  end

  it 'replaces the final assistant output in the run result and its transcript' do
    stub_shortening_run(output: shortened_output)

    final = call_shortener

    expect(run_result.output).to eq({ 'parts' => final.as_message_parts.map do |p|
      { 'text' => p['text'], 'source_indexes' => p['citations'] }
    end }.to_json)
    last_assistant = run_result.messages.reverse.find { |m| m[:role] == :assistant }
    expect(last_assistant[:content]).to eq(run_result.output)
  end

  it 'raises when the shortening pass changes the part count' do
    stub_shortening_run(output: { parts: [{ text: 'Only one part.', source_indexes: [1, 2, 3] }] }.to_json)

    expect { call_shortener }.to raise_error(described_class::Error, /part count/)
  end

  it 'raises when citations are enabled and the shortening pass changes citation indexes' do
    stub_shortening_run(output: { parts: [{ text: 'First part, shorter.', source_indexes: [2, 1] },
                                          { text: 'Second, shorter.', source_indexes: [3] }] }.to_json)

    expect { call_shortener }.to raise_error(described_class::Error, /citation indexes/)
  end

  it 'ignores returned indexes when citations are disabled and keeps part texts' do
    stub_shortening_run(output: { parts: [{ text: 'First part, shorter.', source_indexes: [] },
                                          { text: 'Second, shorter.', source_indexes: [] }] }.to_json)

    final = call_shortener(citations_enabled: false)

    expect(final.parts.map(&:text)).to eq(['First part, shorter.', 'Second, shorter.'])
    expect(final.parts.map(&:citations)).to eq([[1, 2], [3]])
  end

  it 'raises when the shortening run fails' do
    stub_shortening_run(output: nil, failed: true)

    expect { call_shortener }.to raise_error(described_class::Error, /boom/)
  end

  it 'raises when the shortening run returns no usable parts' do
    stub_shortening_run(output: '   ')

    expect { call_shortener }.to raise_error(described_class::Error, /no usable parts/)
  end
end
# rubocop:enable RSpec/VerifiedDoubles
