# configuration related audited gem : https://github.com/collectiveidea/audited

Audited.config do |config|
  # NOTE: 'Enterprise::AuditLog' was referenced here but that class/directory does not exist
  # and no models in app/models/ currently call `audited`. Commented out to remove the
  # dangling reference. Re-enable with a valid class name if a custom audit log is introduced.
  # config.audit_class = 'Enterprise::AuditLog'
end
