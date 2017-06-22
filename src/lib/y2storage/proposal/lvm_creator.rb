#!/usr/bin/env ruby
#
# encoding: utf-8

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

require "y2storage/planned"
require "y2storage/disk_size"

module Y2Storage
  module Proposal
    # Class to create LVM volume groups and logical volumes following a
    # Planned::LvmVg object
    class LvmCreator
      include Yast::Logger

      # Default name for volume groups
      DEFAULT_VG_NAME = "system".freeze
      # Default name for logical volumes
      DEFAULT_LV_NAME = "lv".freeze

      private_constant :DEFAULT_VG_NAME, :DEFAULT_LV_NAME

      # @return [Devicegraph] initial devicegraph
      attr_reader :original_devicegraph

      # Constructor
      #
      # @param original_devicegraph [Devicegraph] Initial devicegraph
      def initialize(original_devicegraph)
        @original_devicegraph = original_devicegraph
      end

      # Returns a copy of the original devicegraph in which the volume
      # group (and its logical volumes, if needed) have been created.
      #
      # @param planned_vg [Planned::LvmVg]   Volume group to create
      # @param pv_partitions [Array<String>] names of the newly created
      #     partitions that should be added as PVs to the volume group
      # @return [Devicegraph] New devicegraph containing the planned volume group
      def create_volumes(planned_vg, pv_partitions = [])
        byebug
        new_graph = original_devicegraph.duplicate
        return new_graph if planned_vg.lvs.empty?

        vg = planned_vg.reuse? ? find_vg(planned_vg, new_graph) : create_volume_group(new_graph, planned_vg)

        assign_physical_volumes!(vg, pv_partitions, new_graph)
        make_space!(vg, planned_vg.lvs)
        create_logical_volumes!(vg, planned_vg.lvs)

        new_graph
      end

    private

      # Find a volume group to be reused
      #
      # @param planned_vg  [Planned::LvmVg] Planned volume group marked as 'reused'
      # @param devicegraph [Devicegraph]    Devicegraph to find the real volume group
      # @return [LvmVg] Volume group to be reused
      def find_vg(planned_vg, devicegraph)
        devicegraph.lvm_vgs.find { |vg| vg.vg_name == planned_vg.reuse }
      end

      # Create a volume group in a devicegraph
      #
      # The volume group will be DEFAULT_VG_NAME.
      #
      # @param devicegraph [Devicegraph]    Starting point
      # @param planned_vg  [Planned::LvmVg] Planned volume group
      # @return [Devicegraph] New devicegraph containing the new volume group
      def create_volume_group(devicegraph, planned_vg)
        name = available_name(planned_vg.volume_group_name || DEFAULT_VG_NAME, devicegraph)
        LvmVg.create(devicegraph, name)
      end

      # Extends the given volume group by adding as physical volumes the
      # partitions in the given list.
      #
      # This method modifies the volume group received as first argument.
      #
      # @param volume_group [LvmVg] volume group to extend
      # @param part_names [Array<String>] device names of the partitions
      # @param devicegraph [Devicegraph] to fetch the partitions
      def assign_physical_volumes!(volume_group, part_names, devicegraph)
        partitions = devicegraph.partitions.select { |p| part_names.include?(p.name) }
        partitions.each do |partition|
          device = partition.encryption || partition
          volume_group.add_lvm_pv(device)
        end
      end

      # Makes sure the given volume group has enough free extends to allocate
      # all the planned volumes, by deleting the existing volume groups.
      #
      # This method modifies the volume group received as first argument.
      #
      # FIXME: the current implementation does not guarantee than the freed
      # space is the minimum valid one.
      #
      # @param volume_group [LvmVg] volume group to modify
      def make_space!(volume_group, planned_lvs)
        space_size = DiskSize.sum(planned_lvs.map(&:min_size))
        missing = missing_vg_space(volume_group, space_size)
        while missing > DiskSize.zero
          lv_to_delete = delete_candidate(volume_group, missing)
          if lv_to_delete.nil?
            error_msg = "The volume group #{volume_group.vg_name} is not big enough"
            raise NoDiskSpaceError, error_msg
          end
          volume_group.delete_lvm_lv(lv_to_delete)
          missing = missing_vg_space(volume_group, space_size)
        end
      end

      # Creates a logical volume for each planned volume.
      #
      # This method modifies the volume group received as first argument.
      #
      # @param volume_group [LvmVg] volume group to modify
      def create_logical_volumes!(volume_group, planned_lvs)
        vg_size = volume_group.available_space
        lvs = Planned::LvmLv.distribute_space(planned_lvs, vg_size, rounding: volume_group.extent_size)
        lvs.each do |lv|
          create_logical_volume(volume_group, lv)
        end
      end

      # Creates a logical volume in a volume group
      #
      # This method modifies the volum group received as first argument.
      #
      # @param volume_group [LvmVg] Volume group
      # @param planned_lv   [Planned::LvmLv] Planned logical volume to be used as reference
      #   for the new one
      def create_logical_volume(volume_group, planned_lv)
        name = planned_lv.logical_volume_name || DEFAULT_LV_NAME
        name = available_name(name, volume_group)
        lv = volume_group.create_lvm_lv(name, planned_lv.size.to_i)
        planned_lv.format!(lv)
      end

      # Best logical volume to delete next while trying to make space for the
      # planned volumes. It returns the smallest logical volume that would
      # fulfill the goal. If no LV is big enough, it returns the biggest one.
      def delete_candidate(volume_group, target_space)
        lvs = volume_group.lvm_lvs
        big_lvs = lvs.select { |lv| lv.size >= target_space }
        if big_lvs.empty?
          lvs.max_by { |lv| lv.size }
        else
          big_lvs.min_by { |lv| lv.size }
        end
      end

      # Missing space in the volume group to fullfil a target
      #
      # @param volume_group [LvmVg]    Volume group
      # @param target_space [DiskSize] Required space
      def missing_vg_space(volume_group, target_space)
        available = volume_group.available_space
        if available > target_space
          DiskSize.zero
        else
          target_space - available
        end
      end

      # Returns the name that is available taking original_name as a base. If
      # the name is already taken, the returned name will have a number
      # appended.
      #
      # @param original_name [String]
      # @param root [Devicegraph, LvmVg] if root is a devicegraph, the name is
      #   considered a VG name. If root is a VG, the name is for a logical
      #   volume.
      # @return [String]
      def available_name(original_name, root)
        return original_name unless name_taken?(original_name, root)

        suffix = 0
        name = "#{original_name}#{suffix}"
        while name_taken?(name, root)
          suffix += 1
          name = "#{original_name}#{suffix}"
        end
        name
      end

      # Determines whether a name for a LV or a VG is already taken
      #
      # If a Devicegraph is given as {root}, it will search for a volume group
      # named like {name}. On the other hand, it will assume that the {root}
      # is a LvmVg and it will search for a volume group.
      #
      # @param name [String]      Name to check
      # @param root [Devicegraph,LvmVg] Scope to search for the name
      def name_taken?(name, root)
        if root.is_a? Devicegraph
          root.lvm_vgs.any? { |vg| vg.vg_name == name }
        else
          root.lvm_lvs.any? { |lv| lv.lv_name == name }
        end
      end
    end
  end
end
