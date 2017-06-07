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

require "y2storage/skip_list_value"

module Y2Storage
  # AutoYaST device skip rule
  #
  # @example Using a rule
  #   Disk = Struct.new(:size_k)
  #   disk = Disk.new(8192)
  #   rule = SkipListRule.new(:size_k, :less_than, 16384)
  #   rule.matches?(disk) #=> true
  #
  # @example Creating a rule from an AutoYaST profile hash
  #   hash = { "skip_key" => "size_k", "skip_if_less_than" => 16384, "skip_value" => 1024 }
  class SkipListRule
    attr_reader :key, :predicate, :raw_reference

    class NotComparableValues < StandardError; end

    class << self
      def from_hash(hash)
        predicate =
          if hash["skip_if_less_than"]
            :less_than
          elsif hash["skip_if_more_than"]
            :more_than
          else
            :equal_to
          end
        new(hash["skip_key"], predicate, hash["skip_value"])
      end
    end

    def initialize(key, predicate, raw_reference)
      @key = key
      @predicate = predicate
      @raw_reference = raw_reference
    end

    def matches?(disk)
      value_from_disk = value(disk)
      return false unless supported_class?(value_from_disk)
      send("match_#{predicate}", value_from_disk, cast_reference(raw_reference, value_from_disk.class))
    end

    def value(disk)
      Y2Storage::SkipListValue.new(disk).send(key)
    end

    SUPPORTED_CLASSES = {
      less_than: [Fixnum].freeze,
      more_than: [Fixnum].freeze,
      equal_to:  [Fixnum, Symbol, String].freeze
    }.freeze

    def supported_class?(value)
      SUPPORTED_CLASSES[predicate].include?(value.class)
    end

    # Cast the reference value in order to do the comparison
    #
    # @param raw [String]
    # @return [String,Fixnum,Symbol] Converted reference value
    def cast_reference(raw, klass)
      if klass == Fixnum
        raw.to_i
      elsif klass == Symbol
        raw.respond_to?(:to_sym) ? raw.to_sym : :nothing
      else
        raw
      end
    end

    def match_less_than(value, reference)
      value < reference
    end

    def match_more_than(value, reference)
      value > reference
    end

    def match_equal_to(value, reference)
      value == reference
    end
  end
end
