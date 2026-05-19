# One-shot migration from the legacy single-slot LLM rows
# (PILOT_LLM_ACTIVE_PROVIDER / PILOT_LLM_ACTIVE_MODEL) into the new per-slot
# chat rows (PILOT_LLM_CHAT_PROVIDER / PILOT_LLM_CHAT_MODEL).
#
# Idempotent: only writes when the destination row is unset.

Rails.application.config.after_initialize do
  migrations = {
    'PILOT_LLM_ACTIVE_PROVIDER' => 'PILOT_LLM_CHAT_PROVIDER',
    'PILOT_LLM_ACTIVE_MODEL' => 'PILOT_LLM_CHAT_MODEL'
  }

  migrations.each do |from, to|
    source = InstallationConfig.find_by(name: from)
    next if source.nil? || source.value.to_s.strip.empty?

    destination = InstallationConfig.find_or_initialize_by(name: to)
    next if destination.persisted? && destination.value.to_s.strip.present?

    destination.value = source.value
    destination.locked = false if destination.new_record?
    destination.save!
    Rails.logger.info("[Llm::SlotMigration] migrated #{from} -> #{to}")
  end

  GlobalConfig.clear_cache
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished,
       ActiveRecord::StatementInvalid, PG::ConnectionBad => e
  Rails.logger.warn("[Llm::SlotMigration] skipped: #{e.class}: #{e.message}")
end
