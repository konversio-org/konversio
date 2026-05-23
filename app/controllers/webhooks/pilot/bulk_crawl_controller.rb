# frozen_string_literal: true

# Inbound webhook the external bulk-crawl service POSTs each page payload to
# so Pilot can keep an assistant's knowledge corpus in sync without holding
# an account-scoped session.
#
# Per pilot-telemetry spec "Inbound webhook for bulk content ingestion"
# (17.20–17.23):
#
#   * URL path embeds the assistant id plus an HMAC-style token derivable
#     from `(last_four_of_api_key + assistant_id + account_id)`.
#   * Comparison uses `ActiveSupport::SecurityUtils.secure_compare` so we
#     stay constant-time.
#   * 404 on unknown assistant, 403 on token mismatch, 200 on accept.
#
# The handler is intentionally minimal — it create-or-updates a single
# `Pilot::Document` keyed on `(assistant_id, external_link)`. Crawl-source
# orchestration lives elsewhere; this endpoint only ingests the payloads
# the external service has already collected.
class Webhooks::Pilot::BulkCrawlController < ActionController::API
  def create
    assistant = ::Pilot::Assistant.find_by(id: params[:assistant_id])
    return render(json: { error: 'assistant not found' }, status: :not_found) if assistant.blank?

    expected = expected_token_for(assistant)
    provided = params[:token].to_s

    return render(json: { error: 'forbidden' }, status: :forbidden) unless ActiveSupport::SecurityUtils.secure_compare(expected, provided)

    document = upsert_document(assistant)
    render json: { id: document.id, external_link: document.external_link }, status: :ok
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  # Expected token: SHA-256 of `(last_four_of_api_key + assistant_id + account_id)`.
  # The external service computes the same value using its provisioned
  # last-four. We do the constant-time comparison server-side.
  def expected_token_for(assistant)
    api_key_last_four = ::Llm::Config.api_key.to_s.last(4)
    digest_input = "#{api_key_last_four}#{assistant.id}#{assistant.account_id}"
    Digest::SHA256.hexdigest(digest_input)
  end

  # Per spec "Valid bulk-crawl callback": create OR update a Pilot::Document
  # for the page payload. Match by (assistant_id, external_link) which is
  # the unique index on the table.
  def upsert_document(assistant)
    payload = page_payload
    document = ::Pilot::Document.find_or_initialize_by(
      assistant_id: assistant.id,
      external_link: payload[:external_link]
    )
    document.account_id = assistant.account_id
    document.content = payload[:content] if payload.key?(:content)
    document.name = payload[:name] if payload.key?(:name)
    document.status = :available if payload[:content].present?
    document.sync_status = :synced
    document.last_synced_at = Time.current
    document.save!
    document
  end

  def page_payload
    {
      external_link: params.require(:external_link).to_s,
      content: params[:content],
      name: params[:name]
    }
  end
end
