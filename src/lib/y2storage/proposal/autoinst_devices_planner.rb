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

require "y2storage/disk"

module Y2Storage
  module Proposal
    # Class to generate a list of Planned::Device objects that must be allocated
    # during the AutoYaST proposal.
    #
    # The list of planned devices is generated from the information that was
    # previously obtained from the AutoYaST profile. This is completely different
    # to the guided proposal equivalent ({PlannedDevicesGenerator}), which
    # generates the planned devices based on the proposal settings and its own
    # logic.
    class AutoinstDevicesPlanner
      include Yast::Logger

      # Constructor
      #
      # @param devicegraph [Devicegraph] Devicegraph to be used as starting point
      def initialize(devicegraph)
        @devicegraph = devicegraph
      end

      # Returns an array of planned devices according to the drives map
      #
      # @param drives_map [Proposal::AutoinstDrivesMap] Drives map from AutoYaST
      # @return [Array<Planned::Partition>] List of planned partitions
      def planned_devices(drives_map)
        result = []

        drives_map.each_pair do |disk_name, drive_spec|
          disk = Disk.find_by_name(devicegraph, disk_name)
          if drive_spec.fetch("type", :CT_DISK).to_sym == :CT_DISK
            result.concat(planned_for_disk(disk, drive_spec))
          else
            result << planned_for_lvm(disk, drive_spec)
          end
        end

        # assign_pvs!(drives_map, result.select { |d| d.is_a?(Y2Storage::Planned::LvmVg) })

        checker = BootRequirementsChecker.new(devicegraph, planned_devices: result)
        result.concat(checker.needed_partitions)

        result
      end

    protected

      # def assign_pvs!(disks, devices)
      #   disks.each_pair do |disk_name, drive_spec|
      #     partitions = drive_spec.fetch("partitions", []).select { |i| i["lvm_group"] }.compact
      #     partitions.each do |part|
      #       vg = devices.find { |v| v.volume_group_name == part["lvm_group"] }
      #       # vg.pvs << drive_spec["device"]
      #       vg.pvs = ["/dev/sda1"]
      #     end
      #   end
      # end

      # TODO:
      # * reusing vgs, lvs
      def planned_for_lvm(disk, spec)
        vg = Y2Storage::Planned::LvmVg.new(volume_group_name: File.basename(spec["device"]))

        spec.fetch("partitions", []).each_with_object(vg.lvs) do |lv_spec, memo|
          lv = Y2Storage::Planned::LvmLv.new(lv_spec["mount"], filesystem_for(lv_spec["filesystem"]))
          lv.logical_volume_name = lv_spec["lv_name"]
          lv.min_size = DiskSize.MiB(1)
          lv.max_size = DiskSize.unlimited
          memo << lv
        end
        vg
      end

      # @return [Devicegraph] Starting devicegraph
      attr_reader :devicegraph

      # Returns an array of planned partitions for a given disk
      #
      # @param disk         [Disk] Disk to place the partitions on
      # FIXME: I should consider passing only the disk name (and not the whole object)
      # @param partitioning [Hash] Partitioning specification from AutoYaST
      # @return [Array<Planned::Partition>] List of planned partitions
      def planned_for_disk(disk, spec)
        result = []
        spec.fetch("partitions", []).each do |partition_spec|
          # TODO: fix Planned::Partition.initialize
          partition = Y2Storage::Planned::Partition.new(nil, nil)
          partition.disk = disk.name
          partition.lvm_volume_group_name = partition_spec["lvm_group"]
          # TODO: partition.bootable is not in the AutoYaST profile. Check if
          # there's some logic to set it in the old code.
          if partition_spec["filesystem"]
            partition.filesystem_type = filesystem_for(partition_spec["filesystem"])
          end

          # TODO: set the correct id based on the filesystem type (move to Partition class?)
          partition.partition_id = 131
          if partition_spec["crypt_fs"]
            partition.encryption_password = partition_spec["crypt_key"]
          end
          partition.mount_point = partition_spec["mount"]
          partition.label = partition_spec["label"]
          partition.uuid = partition_spec["uuid"]
          if !partition_spec.fetch("create", true)
            partition_to_reuse = find_partition_to_reuse(devicegraph, partition_spec)
            if partition_to_reuse
              partition.reuse = partition_to_reuse.name
              partition.reformat = !!partition_spec["format"]
            end
            # TODO: possible errors here
            #   - missing information about what device to use
            #   - the specified device was not found
          end

          # Sizes: leave out reducing fixed sizes and 'auto'
          min_size, max_size = sizes_for(partition_spec, disk)
          partition.min_size = min_size
          partition.max_size = max_size
          result << partition
        end

        result
      end

      # Regular expression to detect which kind of size is being used in an
      # AutoYaST <size> element
      SIZE_REGEXP = /([\d,.]+)?([a-zA-Z%]+)/

      # Returns min and max sizes for a partition specification
      #
      # @param description [Hash] Partition specification from AutoYaST
      # @param disk
      # @return [[DiskSize,DiskSize]] min and max sizes for the given partition
      #
      # @see SIZE_REGEXP
      def sizes_for(part_spec, disk)
        normalized_size = part_spec["size"].to_s.strip.downcase

        if normalized_size == "max" || normalized_size.empty?
          return [disk.min_grain, DiskSize.unlimited]
        end

        number, unit = SIZE_REGEXP.match(normalized_size).values_at(1, 2)
        size =
          if unit == "%"
            percent = number.to_f
            (disk.size * percent) / 100.0
          else
            DiskSize.parse(part_spec["size"], legacy_units: true)
          end
        [size, size]
      end

      # @param type [String,Symbol] Filesystem type name
      def filesystem_for(type)
        Y2Storage::Filesystems::Type.find(type)
      end

      # @param devicegraph [Devicegraph] Devicegraph to search for the partition to reuse
      # @param part_spec   [Hash]        Partition specification from AutoYaST
      def find_partition_to_reuse(devicegraph, part_spec)
        if part_spec["partition_nr"]
          devicegraph.partitions.find { |i| i.number == part_spec["partition_nr"] }
        elsif part_spec["label"]
          devicegraph.partitions.find { |i| i.filesystem_label == part_spec["label"] }
        end
      end
    end
  end
end
