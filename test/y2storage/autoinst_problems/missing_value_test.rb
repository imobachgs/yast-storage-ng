#!/usr/bin/env rspec
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

require_relative "../../spec_helper"
require "y2storage/autoinst_problems/missing_value"

describe Y2Storage::AutoinstProblems::MissingValue do
  subject(:problem) { described_class.new("/home", :size) }

  describe "#message" do
    it "returns a description of the problem" do
      expect(problem.message).to match(/Missing attribute.*size.*'\/home'/)
    end
  end

  describe "#severity" do
    it "returns :fatal" do
      expect(problem.severity).to eq(:fatal)
    end
  end
end
