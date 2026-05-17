class RemoveCaptainInstallationConfigs < ActiveRecord::Migration[7.0]
  CAPTAIN_CONFIG_NAMES = %w[
    CAPTAIN_OPEN_AI_API_KEY
    CAPTAIN_OPEN_AI_MODEL
    CAPTAIN_OPEN_AI_ENDPOINT
    CAPTAIN_EMBEDDING_MODEL
    CAPTAIN_FIRECRAWL_API_KEY
    CAPTAIN_CLOUD_PLAN_LIMITS
  ].freeze

  # One-way removal: Konversio reads PILOT_* env vars via GlobalConfigService
  # and writes them back as InstallationConfig rows. The CAPTAIN_* rows are
  # stale upstream-Chatwoot seeds with no Pilot-runtime reader.
  def up
    InstallationConfig.where(name: CAPTAIN_CONFIG_NAMES).delete_all
    GlobalConfig.clear_cache if defined?(GlobalConfig)
  end

  def down
    # Intentionally no-op: rolling back this purge migration does not
    # re-seed CAPTAIN_* rows. Run the rake task `rake db:chatwoot_load`
    # against an upstream branch if you genuinely need them back.
  end
end
