# encoding: utf-8
#
# Copyright (c) [2017] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "y2storage/skip_list_rule"

module Y2Storage
  class SkipList
    class << self
      def from_array(array)
        rules = array.map { |h| Y2Storage::SkipListRule.from_hash(h) }
        new(rules)
      end
    end

    attr_reader :rules

    def initialize(rules)
      @rules = rules
    end

    def matches?(disk)
      rules.any? { |r| r.matches?(disk) }
    end
  end
end
