require 'rails_helper'

RSpec.describe Custom::Pilot::PayloadRedactor do
  describe '.call' do
    it 'returns an empty hash for nil input' do
      expect(described_class.call(nil)).to eq({})
    end

    it 'returns an empty hash for blank-string input' do
      expect(described_class.call('')).to eq({})
    end

    it 'leaves a non-hash payload untouched' do
      expect(described_class.call('passthrough')).to eq('passthrough')
    end

    it 'redacts the prompt field to length + sha256' do
      result = described_class.call(prompt: 'Hello world')

      expect(result).not_to have_key(:prompt)
      expect(result[:prompt_length]).to eq(11)
      expect(result[:prompt_sha256]).to eq(Digest::SHA256.hexdigest('Hello world'))
    end

    it 'redacts every sensitive text field listed in the spec' do
      described_class::REDACTED_TEXT_FIELDS.each do |field|
        result = described_class.call(field => 'abc')

        expect(result).not_to have_key(field), "expected #{field} to be removed"
        expect(result[:"#{field}_length"]).to eq(3)
        expect(result[:"#{field}_sha256"]).to eq(Digest::SHA256.hexdigest('abc'))
      end
    end

    it 'accepts string keys for sensitive fields as well as symbols' do
      result = described_class.call('prompt' => 'Hello')

      expect(result).not_to have_key(:prompt)
      expect(result).not_to have_key('prompt')
      expect(result[:prompt_length]).to eq(5)
    end

    # §13 testing-patterns gap: redaction should be idempotent on
    # already-redacted payloads (no double-hashing, no key churn).
    it 'is idempotent on its own output' do
      first = described_class.call(prompt: 'Hello world')
      second = described_class.call(first)
      expect(second).to eq(first)
    end

    it 'redacts auth header hashes to a name-only list' do
      result = described_class.call(auth_headers: { 'Authorization' => 'Bearer abc', 'X-Api-Key' => 'sek' })

      expect(result).not_to have_key(:auth_headers)
      expect(result[:auth_header_names]).to match_array(%w[Authorization X-Api-Key])
    end

    it 'accepts auth_headers passed as an array of names' do
      result = described_class.call(auth_headers: %w[Authorization X-Custom])

      expect(result[:auth_header_names]).to eq(%w[Authorization X-Custom])
    end

    it 'reduces auth_headers passed as an unexpected scalar to an empty list' do
      result = described_class.call(auth_headers: 'not a hash or array')
      expect(result[:auth_header_names]).to eq([])
    end

    # The redactor only drops the canonical key, but the redacted-list field
    # set is private to the class. Don't iterate redactor internals from
    # outside — instead verify behavior: a sensitive field never survives,
    # an unrelated field always does.
    it 'preserves unrelated payload keys unchanged' do
      result = described_class.call(account_id: 42, conversation_id: 7, prompt: 'x')

      expect(result[:account_id]).to eq(42)
      expect(result[:conversation_id]).to eq(7)
      expect(result).not_to have_key(:prompt)
    end

    it 'handles empty-string sensitive values by still hashing them' do
      result = described_class.call(prompt: '')
      expect(result).not_to have_key(:prompt)
      expect(result[:prompt_length]).to eq(0)
      expect(result[:prompt_sha256]).to eq(Digest::SHA256.hexdigest(''))
    end

    it 'coerces non-string sensitive values via to_s before hashing' do
      result = described_class.call(prompt: 12_345)
      expect(result[:prompt_length]).to eq('12345'.length)
      expect(result[:prompt_sha256]).to eq(Digest::SHA256.hexdigest('12345'))
    end

    it 'does not mutate the caller-supplied payload' do
      original = { prompt: 'leak-me', account_id: 1 }
      _ = described_class.call(original)
      # Caller's hash must still be intact for any post-dispatch logging.
      expect(original).to eq(prompt: 'leak-me', account_id: 1)
    end
  end
end
