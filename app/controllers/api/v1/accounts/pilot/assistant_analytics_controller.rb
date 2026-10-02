class Api::V1::Accounts::Pilot::AssistantAnalyticsController < Api::V1::Accounts::BaseController
  SUMMARY_CACHE_TTL = 1.hour

  before_action :ensure_feature_enabled
  before_action :fetch_assistant
  before_action :authorize_request

  def overview
    render json: Pilot::Analytics::OverviewReport.new(assistant: @assistant, window: reporting_window).report
  end

  def resolution_flow
    render json: Pilot::Analytics::ResolutionFlowReport.new(assistant: @assistant, window: reporting_window).report
  end

  def resolution_trend
    render json: Pilot::Analytics::ResolutionTrendReport.new(assistant: @assistant, window: reporting_window).report
  end

  def overview_summary
    return render json: { error: 'Invalid timezone offset' }, status: :unprocessable_entity unless reporting_window.timezone_valid?

    cached = read_cached_summary
    return render json: cached if cached.present?

    result = Pilot::Analytics::OverviewSummaryGenerator.new(
      account: Current.account, assistant: @assistant, window: reporting_window
    ).perform

    if result[:error].present?
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      payload = { points: result[:points] }
      write_cached_summary(payload)
      render json: payload
    end
  end

  private

  def reporting_window
    @reporting_window ||= Pilot::Analytics::ReportingWindow.new(range: params[:range], timezone_offset: params[:timezone_offset])
  end

  def read_cached_summary
    cached = Redis::Alfred.get(summary_cache_key)
    JSON.parse(cached).deep_symbolize_keys if cached.present?
  rescue JSON::ParserError
    nil
  end

  def write_cached_summary(payload)
    Redis::Alfred.setex(summary_cache_key, payload.to_json, SUMMARY_CACHE_TTL)
  end

  # Versioned key: any change of range, timezone, assistant version, tracking
  # start, or account locale generates a fresh summary instead of serving a
  # stale entry.
  def summary_cache_key
    [
      'pilot_assistant_overview_summary',
      "account_#{Current.account.id}",
      "assistant_#{@assistant.id}_v#{@assistant.cache_version}",
      "range_#{reporting_window.range}",
      "tz_#{params[:timezone_offset].presence || 'server'}",
      "tracking_#{Pilot::OutcomeTrackingHistory.tracking_started_at&.to_i || 'none'}",
      "locale_#{Current.account.locale}"
    ].join('/')
  end

  def ensure_feature_enabled
    return if Current.account.feature_enabled?('pilot') && Current.account.feature_enabled?('pilot_autopilot')

    render json: { error: 'Pilot Autopilot is not enabled for this account' }, status: :forbidden
  end

  def fetch_assistant
    @assistant = Current.account.pilot_assistants.find(params[:assistant_id])
  end

  def authorize_request
    authorize @assistant, policy_class: Pilot::AssistantPolicy
  end
end
