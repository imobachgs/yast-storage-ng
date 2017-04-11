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

require_relative "../spec_helper"
require "y2storage/dialogs/guided_setup"

describe Y2Storage::Dialogs::GuidedSetup do

  def allow_run_dialog(dialog, &block)
    allow_any_instance_of(dialog).to receive(:run), &block
  end

  def allow_run_select_disks(&block)
    allow_run_dialog(Y2Storage::Dialogs::GuidedSetup::SelectDisks, &block)
  end

  def allow_run_select_root_disk(&block)
    allow_run_dialog(Y2Storage::Dialogs::GuidedSetup::SelectRootDisk, &block)
  end

  def allow_run_select_scheme(&block)
    allow_run_dialog(Y2Storage::Dialogs::GuidedSetup::SelectScheme, &block)
  end

  def allow_run_select_filesystem(&block)
    allow_run_dialog(Y2Storage::Dialogs::GuidedSetup::SelectFilesystem, &block)
  end

  def expect_run_dialog(dialog)
    expect_any_instance_of(dialog).to receive(:run).once
  end

  def expect_not_run_dialog(dialog)
    expect_any_instance_of(dialog).not_to receive(:run)
  end

  def expect_not_run_select_disks
    expect_not_run_dialog(Y2Storage::Dialogs::GuidedSetup::SelectDisks)
  end

  def disk(name)
    instance_double(Y2Storage::Disk, name: name, size: Y2Storage::DiskSize.new(0))
  end

  subject { described_class.new(devicegraph, settings) }

  before do
    allow_any_instance_of(Y2Storage::DiskAnalyzer).to receive(:candidate_disks) do
      candidate_disks.map { |d| disk(d) }
    end
  end

  let(:devicegraph) { instance_double(Y2Storage::Devicegraph) }

  let(:settings) { Y2Storage::ProposalSettings.new }

  let(:candidate_disks) { [] }

  describe "#run" do
    before do
      allow_run_select_disks { :next }
      allow_run_select_root_disk { :next }
      allow_run_select_scheme { :next }
      allow_run_select_filesystem { :next }
    end

    context "when there is only one candidate disk" do
      let(:candidate_disks) { ["/dev/sda"] }

      it "does not show disks selection dialog" do
        expect_not_run_select_disks
      end
    end

    context "when all dialogs return :next" do
      it "returns :next" do
        expect(subject.run).to eq(:next)
      end

      context "and some options are selected" do
        before do
          allow_run_select_scheme do
            subject.settings.use_lvm = true
            :next
          end
        end

        it "updates settings" do
          subject.run
          expect(subject.settings.use_lvm).to eq(true)
        end
      end
    end

    context "when first dialog returns :back" do
      before do
        allow_run_select_disks { :back }
      end

      it "returns :back" do
        expect(subject.run).to eq(:back)
      end
    end

    context "when some dialog aborts" do
      before do
        allow_run_select_scheme { :abort }
      end

      it "returns :abort" do
        expect(subject.run).to eq(:abort)
      end
    end
  end
end
