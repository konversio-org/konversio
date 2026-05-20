Rails.application.config.after_initialize do
  Llm::Config.initialize!
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished,
       ActiveRecord::StatementInvalid => e
  Rails.logger.info("[llm] Skipping LLM config initialization (DB not ready): #{e.class}")
end
