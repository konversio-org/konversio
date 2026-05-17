class GlobalConfigService
  # Env-first precedence, per pilot-foundation D5 ("Env-first config via
  # GlobalConfigService"): if the process environment has a value for the
  # key, that value wins over any cached DB row, and the DB row is updated
  # so the admin UI shows the effective value. Falls back to DB, then to
  # the supplied default.
  def self.load(config_key, default_value)
    env_value = ENV[config_key].presence
    return load_from_env(config_key, env_value) if env_value

    db_value = GlobalConfig.get(config_key)[config_key]
    return db_value if db_value.present?

    default_value.presence
  end

  def self.load_from_env(config_key, env_value)
    row = InstallationConfig.find_by(name: config_key)
    if row.nil?
      InstallationConfig.create!(name: config_key, value: env_value, locked: false)
      GlobalConfig.clear_cache
    elsif row.value != env_value
      row.update!(value: env_value)
      GlobalConfig.clear_cache
    end
    env_value
  end

  def self.account_signup_enabled?
    load('ENABLE_ACCOUNT_SIGNUP', 'false').to_s != 'false'
  end
end
