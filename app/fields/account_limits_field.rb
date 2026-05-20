require 'administrate/field/base'

class AccountLimitsField < Administrate::Field::Base
  def to_s
    data.to_s
  end
end
