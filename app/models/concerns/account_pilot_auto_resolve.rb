module AccountPilotAutoResolve
  extend ActiveSupport::Concern

  VALID_PILOT_AUTO_RESOLVE_MODES = %w[evaluated legacy disabled].freeze

  included do
    VALID_PILOT_AUTO_RESOLVE_MODES.each do |mode|
      define_method("pilot_auto_resolve_#{mode}?") do
        pilot_auto_resolve_mode == mode
      end
    end
  end

  def pilot_auto_resolve_mode
    mode = settings&.[]('pilot_auto_resolve_mode')
    return mode if VALID_PILOT_AUTO_RESOLVE_MODES.include?(mode)
    return 'disabled' if settings&.[]('pilot_disable_auto_resolve') == true

    feature_enabled?('pilot_tasks') ? 'evaluated' : 'legacy'
  end
end
