#!/usr/bin/env ruby
#
# encoding: utf-8

# Copyright (c) [2015-2017] SUSE LLC
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

require "yast"
require "y2storage/planned/device"
require "y2storage/planned/mixins"

module Y2Storage
  module Planned
    # Specification for a Y2Storage::LvmLv object to be created during the
    # storage or AutoYaST proposals
    #
    # @see Device
    class LvmLv < Device
      include Planned::HasSize
      include Planned::CanBeFormatted
      include Planned::CanBeMounted
      include Planned::CanBeEncrypted

      # @return [String] name to use for Y2Storage::LvmLv#lv_name
      attr_accessor :logical_volume_name

      # Builds a new object based on a real LvmLv one
      #
      # The new instance represents the intention to reuse the real LV, so the
      # #reuse method will be set accordingly. On the other hand, it copies
      # information from the real LV to make sure it is available even if the
      # real object disappears.
      #
      #
      # @param real_vg [Y2Storage::LvmVg] Logical volume group to get the values from
      # @return [LvmLv] New LvmLv instance based on real_lv
      def self.from_real_lv(real_lv)
        lv = new(real_lv.filesystem_mountpoint, real_lv.filesystem_type)
        lv.initialize_from_real_lv(real_lv)
        lv
      end

      # Constructor.
      #
      # @param mount_point [string] See {CanBeMounted#mount_point}
      # @param filesystem_type [Filesystems::Type] See {CanBeFormatted#filesystem_type}
      def initialize(mount_point, filesystem_type = nil)
        initialize_has_size
        initialize_can_be_formatted
        initialize_can_be_mounted
        initialize_can_be_encrypted

        @mount_point = mount_point
        @filesystem_type = filesystem_type

        return unless @mount_point && @mount_point.start_with?("/")

        @logical_volume_name =
          if @mount_point == "/"
            "root"
          else
            @mount_point.sub(%r{^/}, "")
          end
      end

      # Initializes the object taking the values from a real logical volume
      #
      # @param real_vg [Y2Storage::LvmLv] Logical volume to get the values from
      def initialize_from_real_lv(real_lv)
        @logical_volume_name = real_lv.lv_name
        self.reuse = real_lv.lv_name
      end

      def self.to_string_attrs
        [:mount_point, :reuse, :min_size, :max_size, :logical_volume_name, :subvolumes]
      end
    end
  end
end
