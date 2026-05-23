require 'rails_helper'

RSpec.describe Custom::Pilot::TraceSpan do
  describe '.wrap' do
    context 'when OpenTelemetry is disabled' do
      before { allow(KonversioApp).to receive(:otel_enabled?).and_return(false) }

      it 'yields a NullSpan-like shim that accepts set_attribute' do
        captured = nil
        described_class.wrap(name: 'pilot.test.op', attributes: { account_id: 1 }) do |span|
          captured = span
          span.set_attribute('extra', 'value')
          'ok'
        end
        expect(captured).to respond_to(:set_attribute)
      end

      it 'returns the value yielded by the block' do
        result = described_class.wrap(name: 'pilot.test.op', attributes: {}) do |_span|
          'expected'
        end
        expect(result).to eq('expected')
      end

      it 'logs a structured span line with all attributes' do
        allow(Rails.logger).to receive(:info)

        described_class.wrap(name: 'pilot.briefing.generate',
                             attributes: { account_id: 7, model: 'gpt-4', credit_used: true }) do |span|
          span.set_attribute('prompt_tokens', 100)
        end

        expect(Rails.logger).to have_received(:info).with(/span=pilot\.briefing\.generate/)
        expect(Rails.logger).to have_received(:info).with(/account_id=7/)
        expect(Rails.logger).to have_received(:info).with(/credit_used=true/)
        expect(Rails.logger).to have_received(:info).with(/prompt_tokens=100/)
      end
    end

    context 'when OpenTelemetry is enabled' do
      let(:span_double) { instance_double(OpenTelemetry::Trace::Span, set_attribute: nil) }
      let(:tracer_double) { instance_double(OpenTelemetry::Trace::Tracer) }

      before do
        allow(KonversioApp).to receive(:otel_enabled?).and_return(true)
        allow(OpentelemetryConfig).to receive(:tracer).and_return(tracer_double)
        allow(tracer_double).to receive(:in_span).and_yield(span_double)
      end

      it 'creates a span via OpentelemetryConfig.tracer' do
        described_class.wrap(name: 'pilot.tool.custom_http', attributes: { account_id: 1 }) { 'ok' }
        expect(tracer_double).to have_received(:in_span).with('pilot.tool.custom_http')
      end

      it 'sets each non-nil attribute on the span' do
        described_class.wrap(name: 'pilot.tool.custom_http',
                             attributes: { account_id: 1, model: nil, credit_used: false }) { 'ok' }

        expect(span_double).to have_received(:set_attribute).with('account_id', 1)
        expect(span_double).to have_received(:set_attribute).with('credit_used', false)
        expect(span_double).not_to have_received(:set_attribute).with('model', anything)
      end

      it 'returns the block result even when otel raises mid-span' do
        allow(tracer_double).to receive(:in_span).and_raise(StandardError.new('exporter down'))
        result = described_class.wrap(name: 'pilot.briefing.generate', attributes: {}) { 'still ok' }
        expect(result).to eq('still ok')
      end
    end
  end
end
