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
require "y2storage/clients/partitions_proposal"

describe Y2Storage::Clients::PartitionsProposal do
  subject { described_class.new }

  before do
    Y2Storage::StorageManager.fake_from_yaml(input_file_for("empty_hard_disk_gpt_50GiB"))
    # To generate a new PartitionsProposal.actions_presenter for each test
    described_class.staging_revision = 0
  end

  let(:actions_presenter) { described_class.actions_presenter }

  describe "#initialize" do
    let(:storage_manager) { Y2Storage::StorageManager.instance }

    context "when running the client for the first time" do
      before do
        allow(storage_manager).to receive(:staging_changed?).and_return false
      end

      context "and there is not a proposal" do
        it "calculates a new proposal" do
          expect(storage_manager.proposal).to be_nil
          subject
          expect(storage_manager.proposal).not_to be_nil
          expect(storage_manager.proposal.proposed?).to be true
        end
      end

      context "and a proposal already exists" do
        before do
          allow(storage_manager).to receive(:proposal).and_return(proposal)
        end

        let(:proposal) { instance_double(Y2Storage::GuidedProposal, proposed?: proposed) }

        context "but it is not calculated yet" do
          let(:proposed) { false }

          it "calculates the proposal" do
            expect(storage_manager.proposal).to receive(:propose)
            subject
          end
        end

        context "and it is already calculated" do
          let(:proposed) { true }

          it "does not re-calculate the proposal" do
            expect(storage_manager.proposal).to_not receive(:propose)
            subject
          end
        end
      end
    end

    context "when the staging devicegraph has already been manually set" do
      before do
        allow(storage_manager).to receive(:staging_changed?).and_return true
      end

      it "does not create a new proposal" do
        proposal = storage_manager.proposal
        subject
        expect(storage_manager.proposal).to eq(proposal)
      end

      it "does not propose anything" do
        expect(storage_manager.proposal).not_to receive(:propose)
        subject
      end
    end

    context "when it has the current staging revision" do
      before do
        described_class.staging_revision = 1
        described_class.actions_presenter = presenter
      end

      let(:presenter) { instance_double(Y2Storage::ActionsPresenter) }

      it "does not update the staging revision" do
        subject
        expect(described_class.staging_revision).to eq(1)
      end

      it "does not update the actions presenter" do
        subject
        expect(described_class.actions_presenter).to eq(presenter)
      end
    end

    context "when it has not the current staging revision" do
      before do
        described_class.staging_revision = 1
        described_class.actions_presenter = presenter1
        allow(storage_manager).to receive(:staging_revision).and_return(2)
        allow(Y2Storage::ActionsPresenter).to receive(:new).and_return(presenter2)
      end

      let(:presenter1) { instance_double(Y2Storage::ActionsPresenter) }
      let(:presenter2) { instance_double(Y2Storage::ActionsPresenter) }

      it "updates the staging revision" do
        subject
        expect(described_class.staging_revision).to eq 2
      end

      it "updates the actions presenter" do
        subject
        expect(described_class.actions_presenter).to eq(presenter2)
      end
    end
  end

  describe "#make_proposal" do
    context "when it has been successful" do
      before do
        allow(subject).to receive(:failed).and_return(false)
      end

      it "returns a hash with 'preformatted_proposal', 'links' and 'language_changed'" do
        proposal = subject.make_proposal({})
        expect(proposal).to be_a Hash
        expect(proposal).to include("preformatted_proposal", "links", "language_changed")
      end

      it "returns html representation for 'preformatted_proposal' key" do
        proposal = subject.make_proposal({})
        html_content = actions_presenter.to_html
        expect(proposal["preformatted_proposal"]).to eq html_content
      end

      it "includes actions presenter events in 'links' value" do
        proposal = subject.make_proposal({})
        presenter_events = actions_presenter.events
        expect(proposal["links"]).to include(*presenter_events)
      end

      it "returns false for 'language_changed' key" do
        proposal = subject.make_proposal({})
        expect(proposal["language_changed"]).to be false
      end
    end

    context "when it has failed" do
      before do
        allow(subject).to receive(:failed).and_return(true)
      end

      it "returns a hash with 'warning' and 'warning_level'" do
        proposal = subject.make_proposal({})
        expect(proposal).to be_a Hash
        expect(proposal).to include("warning", "warning_level")
      end

      it "returns :blocker for 'warning_level' key" do
        proposal = subject.make_proposal({})
        expect(proposal["warning_level"]).to be :blocker
      end
    end
  end

  describe "#ask_user" do
    context "when 'chosen_id' is an actions presenter event" do
      let(:param) { { "chosen_id" => actions_presenter.events.first } }

      it "changes status of actions presenter" do
        subject
        expect(actions_presenter).to receive(:update_status)
        subject.ask_user(param)
      end

      it "returns a hash with :again for 'workflow_sequence' key" do
        result = subject.ask_user(param)
        expect(result).to be_a(Hash)
        expect(result["workflow_sequence"]).to eq :again
      end
    end

    context "when 'chosen_id' is not an actions presenter event" do
      let(:param) { { "chosen_id" => "whatever" } }

      it "shows a warning dialog" do
        expect(Yast::Report).to receive(:Warning)
        subject.ask_user(param)
      end

      it "returns a hash with :back for 'workflow_sequence' key" do
        result = subject.ask_user(param)
        expect(result).to be_a(Hash)
        expect(result["workflow_sequence"]).to eq :back
      end
    end
  end

  describe "#description" do
    it "returns a hash with 'id', 'rich_text_title' and 'menu_title'" do
      description = subject.description
      expect(description).to be_a Hash
      expect(description).to include("id", "menu_title", "rich_text_title")
    end
  end
end
