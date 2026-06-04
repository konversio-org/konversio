require 'rails_helper'
require Rails.root.join('lib/portal_prefix_constraint')

RSpec.describe PortalPrefixConstraint do
  subject(:constraint) { described_class.new }

  let(:account) { create(:account) }

  def mock_request(prefix)
    instance_double(ActionDispatch::Request, path_parameters: { prefix: prefix })
  end

  describe '#matches?' do
    context 'when prefix is the built-in default "hc"' do
      it 'returns true without querying the database' do
        request = mock_request('hc')
        expect(constraint.matches?(request)).to be true
      end
    end

    context 'when prefix matches a known portal path_prefix' do
      let!(:portal) do
        create(:portal, account_id: account.id,
                        config: { 'allowed_locales' => ['en'], 'default_locale' => 'en',
                                  'draft_locales' => [], 'path_prefix' => 'docs' })
      end

      it 'returns true' do
        request = mock_request('docs')
        expect(constraint.matches?(request)).to be true
      end
    end

    context 'when prefix does not match any known portal' do
      it 'returns false' do
        request = mock_request('unknown-prefix')
        expect(constraint.matches?(request)).to be false
      end
    end

    context 'when prefix is blank' do
      it 'returns false' do
        request = mock_request('')
        expect(constraint.matches?(request)).to be false
      end

      it 'returns false for nil' do
        request = mock_request(nil)
        expect(constraint.matches?(request)).to be false
      end
    end
  end
end
