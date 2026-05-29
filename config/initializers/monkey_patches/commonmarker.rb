module Commonmarker
  class Node
    alias original_list_type list_type

    def list_type
      t = original_list_type
      if t == :ordered
        :ordered_list
      elsif t == :bullet
        :bullet_list
      else
        t
      end
    end
  end
end
