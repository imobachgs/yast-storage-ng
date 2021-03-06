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

require "yaml"
require "storage"
require "y2storage"

module Y2Storage
  #
  # Class to write storage device trees to YAML files.
  #
  class YamlWriter
    include Yast::Logger

    class << self
      #
      # Write all devices from the specified devicegraph to a YAML file.
      #
      # This is a singleton method for convenience. It creates a YamlWriter
      # internally for one-time usage. If you use this more often (for
      # example, in a loop), it is recommended to create a YamlWriter and
      # use its write() method repeatedly.
      #
      # @param devicegraph [Devicegraph]
      # @param yaml_file [String | IO]
      #
      def write(devicegraph, yaml_file)
        writer = YamlWriter.new
        writer.write(devicegraph, yaml_file)
      end
    end

    # Write all devices from the specified device graph to a YAML file.
    #
    # @param devicegraph [Devicegraph]
    # @param yaml_file [String | IO]
    #
    def write(devicegraph, yaml_file)
      device_tree = yaml_device_tree(devicegraph)
      if yaml_file.respond_to?(:write)
        yaml_file.write(device_tree.to_yaml)
      else
        File.open(yaml_file, "w") { |file| file.write(device_tree.to_yaml) }
      end
    end

    # Convert all devices from the specified device graph to YAML data
    # structures, i.e. nested arrays and hashes. The toplevel item will
    # always be an array.
    #
    # @param devicegraph [Devicegraph]
    # @return [Array<Hash>]
    def yaml_device_tree(devicegraph)
      yaml = []
      devicegraph.disk_devices.each { |device| yaml << yaml_disk_device(device) }
      devicegraph.lvm_vgs.each { |lvm_vg| yaml << yaml_lvm_vg(lvm_vg) }
      yaml
    end

  private

    # Return the YAML counterpart of a disk device
    #
    # @param  device [Dasd, Disk]
    # @return [Hash]
    def yaml_disk_device(device)
      content = basic_disk_device_attributes(device)
      if device.partition_table
        ptable = device.partition_table
        content["partition_table"] = ptable.type.to_s
        if ptable.type.is?(:msdos)
          content["mbr_gap"] = ptable.minimal_mbr_gap.to_s
        end
        partitions = yaml_disk_device_partitions(device)
        content["partitions"] = partitions unless partitions.empty?
      else
        content.merge!(yaml_filesystem_and_encryption(device))
      end

      device = device.is?(:dasd) ? "dasd" : "disk"
      { device => content }
    end

    # Basic attributes used to represent a disk device
    #
    # @param  device [Dasd, Disk]
    # @return [Hash{String => Object}]
    def basic_disk_device_attributes(device)
      {
        "name"       => device.name,
        "size"       => device.size.to_s,
        "block_size" => device.region.block_size.to_s,
        "io_size"    => DiskSize.B(device.topology.optimal_io_size).to_s,
        "min_grain"  => device.min_grain.to_s,
        "align_ofs"  => DiskSize.B(device.topology.alignment_offset).to_s
      }
    end

    # Returns a YAML representation of the partitions and free slots in a
    #   disk device
    #
    # Free slots are calculated as best as we can and not part of the
    #   partition table object.
    #
    # @param disk [Dasd, Disk]
    # @return [Array<Hash>]
    #
    # FIXME: this method offends three different complexity cops!
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def yaml_disk_device_partitions(device)
      partition_end = 0
      partition_end_max = 0
      partition_end_ext = 0
      partitions = []
      sorted_parts = sorted_partitions(device)
      sorted_parts.each do |partition|

        # if we are about to leave an extend partition, show what's left
        if partition_end_ext > 0 && !partition.type.is?(:logical)
          gap = partition_end_ext - partition_end
          partitions << yaml_free_slot(DiskSize.B(partition_end_ext - gap), DiskSize.B(gap)) if gap > 0
          partition_end = partition_end_ext
          partition_end_ext = 0
        end

        # is there a gap before the partition?
        # note: gap might actually be negative sometimes!
        gap = partition.region.start * partition.region.block_size.to_i - partition_end
        partitions << yaml_free_slot(DiskSize.B(partition_end), DiskSize.B(gap)) if gap > 0

        # show partition itself
        partitions << yaml_partition(partition)

        # adjust end pointers
        partition_end = (partition.region.end + 1) * partition.region.block_size.to_i
        partition_end_max = [partition_end_max, partition_end].max

        # if we're inside an extended partition, remember its end for later
        if partition.type.is?(:extended)
          partition_end_ext = partition_end
          partition_end = partition.region.start * partition.region.block_size.to_i
        end
      end

      # finally, show what's left

      # see if there's space left in an extended partition
      if partition_end_ext > 0
        gap = partition_end_ext - partition_end
        partitions << yaml_free_slot(DiskSize.B(partition_end_ext), DiskSize.B(gap)) if gap > 0
      end

      # see if there's space left at the end of the device
      # show also negative sizes so we know we've overstepped
      gap = (device.region.end + 1) * device.region.block_size.to_i - partition_end_max
      partitions << yaml_free_slot(DiskSize.B(partition_end_max), DiskSize.B(gap)) if gap != 0

      partitions
    end
    # rubocop:enable all

    # Partitions sorted by position in the disk device and by type
    #
    # Start position is the primary criteria. In addition, extended partitions
    # are listed before any of its corresponding logical partitions
    #
    # @param device [Dasd, Disk]
    # @return [Array<Partition>]
    def sorted_partitions(device)
      device.partitions.sort do |a, b|
        by_start = a.region.start <=> b.region.start
        if by_start.zero?
          a.type.is?(:extended) ? -1 : 1
        else
          by_start
        end
      end
    end

    # Return the YAML counterpart of a Y2Storage::Partition.
    #
    # @param  partition [Partition]
    # @return [Hash]
    def yaml_partition(partition)
      content = {
        "size"  => partition.size.to_s,
        "start" => (partition.region.block_size * partition.region.start).to_s,
        "name"  => partition.name,
        "type"  => partition.type.to_s,
        "id"    => partition.id.to_s
      }

      content.merge!(yaml_filesystem_and_encryption(partition))

      { "partition" => content }
    end

    # Return the YAML counterpart of a free slot between partitions on a
    # disk.
    #
    # @param  size [DiskSize] size of the free slot
    # @return [Hash]
    #
    def yaml_free_slot(start, size)
      { "free" => { "size" => size.to_s, "start" => start.to_s } }
    end

    # Return the YAML counterpart of a Y2Storage::LvmVg.
    #
    # @param lvm_vg [LvmVg]
    # @return [Hash]
    #
    def yaml_lvm_vg(lvm_vg)
      content = basic_lvm_vg_attributes(lvm_vg)

      lvm_lvs = yaml_lvm_vg_lvm_lvs(lvm_vg)
      content["lvm_lvs"] = lvm_lvs unless lvm_lvs.empty?

      lvm_pvs = yaml_lvm_vg_lvm_pvs(lvm_vg)
      content["lvm_pvs"] = lvm_pvs

      { "lvm_vg" => content }
    end

    # Basic attributes used to represent a volume group
    #
    # @param lvm_vg [LvmVg]
    # @return [Hash{String => Object}]
    #
    def basic_lvm_vg_attributes(lvm_vg)
      {
        "vg_name"     => lvm_vg.vg_name,
        "extent_size" => lvm_vg.extent_size.to_s
      }
    end

    # Return a YAML representation of the logical volumes in a volume group
    #
    # @param lvm_vg [LvmVg]
    # @return [Array<Hash>]
    #
    def yaml_lvm_vg_lvm_lvs(lvm_vg)
      lvm_vg.lvm_lvs.map { |lvm_lv| yaml_lvm_lv(lvm_lv) }
    end

    # Return the YAML counterpart of a Y2Storage::LvmLv.
    #
    # @param lvm_lv [LvmLv]
    # @return [Hash]
    #
    def yaml_lvm_lv(lvm_lv)
      content = {
        "lv_name" => lvm_lv.lv_name,
        "size"    => lvm_lv.size.to_s
      }

      content["stripes"] = lvm_lv.stripes if lvm_lv.stripes != 0
      content["stripe_size"] = lvm_lv.stripe_size.to_s if lvm_lv.stripe_size != DiskSize.zero

      content.merge!(yaml_filesystem_and_encryption(lvm_lv))

      { "lvm_lv" => content }
    end

    # Return a YAML representation of the physical volumes in a volume group
    #
    # @param lvm_vg [LvmVg]
    # @return [Array<Hash>]
    #
    def yaml_lvm_vg_lvm_pvs(lvm_vg)
      pvs = lvm_vg.lvm_pvs.sort_by { |pv| pv.blk_device.name }
      pvs.map { |lvm_pv| yaml_lvm_pv(lvm_pv) }
    end

    # Return the YAML counterpart of a Y2Storage::LvmPv.
    #
    # @param lvm_pv [LvmPv]
    # @return [Hash]
    #
    def yaml_lvm_pv(lvm_pv)
      content = {
        "blk_device" => lvm_pv.blk_device.name
      }

      { "lvm_pv" => content }
    end

    # Return the YAML counterpart of a filesystem and encryption.
    #
    # @param parent [Dasd, Disk, Partition, LvmLv]
    # @return [Hash]
    #
    def yaml_filesystem_and_encryption(parent)
      content = {}
      if parent.filesystem
        content.merge!(yaml_filesystem(parent.filesystem))
        content.merge!(yaml_btrfs_subvolumes(parent.filesystem))
      end
      if parent.encryption
        encryption = parent.encryption
        content.merge!(yaml_encryption(encryption))
        if encryption.filesystem
          filesystem = encryption.filesystem
          content.merge!(yaml_filesystem(filesystem))
          content.merge!(yaml_btrfs_subvolumes(filesystem))
        end
      end
      content
    end

    # Return the YAML counterpart of a Y2Storage::BlkFilesystem.
    #
    # @param file_system [BlkFilesystem]
    # @return [Hash{String => Object}]
    #
    def yaml_filesystem(file_system)
      content = {
        "file_system" => file_system.type.to_s
      }

      content["mount_point"] = file_system.mountpoint unless file_system.mountpoint.nil?
      content["label"] = file_system.label unless file_system.label.empty?
      content["fstab_options"] = file_system.fstab_options unless file_system.fstab_options.empty?

      content
    end

    # Return the YAML counterpart of a Y2Storage::Encryption.
    #
    # @param encryption [BlkFilesystem]
    # @return [Hash{String => Object}]
    #
    def yaml_encryption(encryption)
      content = {
        "type" => "luks"
        # "type" = encryption.type.to_s # not implemented yet in lib
      }

      content["name"] = encryption.name
      content["password"] = encryption.password unless encryption.password.empty?

      { "encryption" => content }
    end

    # Return the YAML counterpart of a Btrfs's subvolumes or an empty hash if
    # the filesystem is not Btrfs.
    #
    # @param filesystem [Filesystems::BlkFilesystem]
    # @return [Hash{String => Object}]
    #
    def yaml_btrfs_subvolumes(filesystem)
      return {} unless filesystem.type.is?(:btrfs)
      subvolumes = filesystem.btrfs_subvolumes
      return {} if subvolumes.empty? # the toplevel subvol doesn't have a path
      default_subvolume = subvolumes.find { |s| s.default_btrfs_subvolume? && !s.path.empty? }
      content = {}
      content["default_subvolume"] = default_subvolume.path if default_subvolume
      content["subvolumes"] = subvolumes.map do |subvol|
        yaml_btrfs_subvolume(subvol)
      end.compact

      { "btrfs" => content }
    end

    # Return the YAML counterpart of one Btrfs subvolume or nil if it has an
    # empty path.
    #
    # @param subvol [BtrfsSubvolume]
    # @return [Hash{String=>Object}] YAML
    #
    def yaml_btrfs_subvolume(subvol)
      return nil if subvol.path.empty?
      content = { "path" => subvol.path }
      content["nocow"] = "true" if subvol.nocow?
      { "subvolume" => content }
    end
  end
end
