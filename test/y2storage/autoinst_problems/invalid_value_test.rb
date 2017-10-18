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
require "y2storage/autoinst_problems/invalid_value"

describe Y2Storage::AutoinstProblems::InvalidValue do
  subject(:problem) { described_class.new("/", :size, "auto") }

  describe "#message" do
    it "includes relevant information" do
      message = problem.message
      expect(message).to include "/"
      expect(message).to include "size"
      expect(message).to include "auto"
    end

    context "when no new value was given" do
      it "includes a warning about the section being skipped" do
        expect(problem.message).to include "the section will be skipped"
      end
    end

    context "when a new value was given" do
      subject(:problem) { described_class.new("/", :size, "auto", "some-value") }

      it "includes a warning about the section being skipped" do
        expect(problem.message).to include "replaced by 'some-value'"
      end
    end

    context "when :skip is given as new value" do
      subject(:problem) { described_class.new("/", :size, "auto", :skip) }

      it "includes a warning about the section being skipped" do
        expect(problem.message).to include "the section will be skipped"
      end
    end
  end

  describe "#severity" do
    it "returns :warn" do
      expect(problem.severity).to eq(:warn)
    end
  end
end
