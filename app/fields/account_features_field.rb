require 'administrate/field/base'

class AccountFeaturesField < Administrate::Field::Base
  def to_s
    data.to_s
  end
end
