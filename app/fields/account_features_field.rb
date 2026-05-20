require 'administrate/field/base'

class AccountFeaturesField < Administrate::Field::Base
  def feature_definitions
    Featurable::FEATURE_LIST
  end

  def standard_features
    feature_definitions.reject { |feature| pilot_feature?(feature) }
  end

  def pilot_features
    features = feature_definitions.select { |feature| pilot_feature?(feature) }
    master_features, subfeatures = features.partition { |feature| pilot_master_feature?(feature) }

    master_features + subfeatures
  end

  def feature_name(feature)
    feature.fetch('name').to_s
  end

  def feature_display_name(feature)
    feature['display_name'].presence || feature_name(feature).titleize
  end

  def feature_enabled?(feature)
    enabled_feature_names.include?(feature_name(feature))
  end

  def enabled_count(features = feature_definitions)
    features.count { |feature| feature_enabled?(feature) }
  end

  def disabled_count(features = feature_definitions)
    features.count - enabled_count(features)
  end

  def pilot_feature?(feature)
    name = feature_name(feature)

    name == 'pilot' || name.start_with?('pilot_')
  end

  def pilot_master_feature?(feature)
    feature_name(feature) == 'pilot'
  end

  def pilot_master_enabled?
    pilot_master = pilot_features.find { |feature| pilot_master_feature?(feature) }

    pilot_master.present? && feature_enabled?(pilot_master)
  end

  def to_s
    data.to_s
  end

  private

  def enabled_feature_names
    @enabled_feature_names ||= Array(data).map(&:to_s)
  end
end
