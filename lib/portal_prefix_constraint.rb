class PortalPrefixConstraint
  DEFAULT_PREFIX = 'hc'.freeze

  def matches?(request)
    prefix = request.path_parameters[:prefix]
    return false if prefix.blank?
    return true if prefix == DEFAULT_PREFIX

    Portal.where("config->>'path_prefix' = ?", prefix).exists?
  end
end
