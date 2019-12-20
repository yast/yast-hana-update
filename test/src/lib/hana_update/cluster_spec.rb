# -*- encoding: utf-8 -*-
# Copyright (c) [2019] SUSE LLC
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

require_relative '../../../test_helper'
require 'hana_update/cluster'
require 'rexml/document'
require 'rexml/xpath'
require 'socket'

# Matcher for a unique text message in array
RSpec::Matchers.define :match_message do |expected|
  matches = 0
  match do |actual|
    matches = actual.map{|z| z.match(expected)}.map(&:nil?).count(false)
    matches == 1
  end
  failure_message do |actual|
    "found #{matches} matches, expected a single match\nMessages were:\n\t#{actual.join("\n\t")}"
  end
end


describe HANAUpdater::ClusterClass do
  let (:const) {Constants.new}

  describe '#update_state' do
    it 'updates the state of the cluster' do
      HANAUpdater::Cluster.reset
      allow(HANAUpdater::Cluster).to receive(:get_cib)
        .and_return(REXML::Document.new(test_file('cibadmin.xml')))
      allow(HANAUpdater::Cluster).to receive(:get_crm_mon)
        .and_return(REXML::Document.new(test_file('crm_mon.xml')))
      expect(HANAUpdater::Cluster.groups).to be_empty
      HANAUpdater::Cluster.update_state
      expect(HANAUpdater::Cluster.groups).not_to be_empty
    end
  end

  describe '#get_system' do
    it 'returns the correct system' do
      HANAUpdater::Cluster.reset
      allow(HANAUpdater::Cluster).to receive(:get_cib)
        .and_return(REXML::Document.new(test_file('cibadmin.xml')))
      allow(HANAUpdater::Cluster).to receive(:get_crm_mon)
        .and_return(REXML::Document.new(test_file('crm_mon.xml')))
      HANAUpdater::Cluster.update_state
      grp = HANAUpdater::Cluster.get_system(const.system.id, const.system.instance)
      expect(grp).not_to be_nil
      expect(grp.hana_sid).to eq const.system.id
      expect(grp.hana_inst).to eq const.system.instance
    end
  end

  describe '#all_managed?' do
    context 'when all resource instances are managed' do
      it 'should return true' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test10.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test10.mon.xml')))
        HANAUpdater::Cluster.update_state
        grp = HANAUpdater::Cluster.get_system(const.system.id, const.system.instance)
        expect(grp).not_to be_nil
        expect(grp.all_managed?).to eq(true)
      end
    end

    context 'when not all resource instances are managed' do
      it 'should return false' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('cibadmin.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('crm_mon.xml')))
        HANAUpdater::Cluster.update_state
        grp = HANAUpdater::Cluster.get_system(const.system.id, const.system.instance)
        expect(grp).not_to be_nil
        expect(grp.all_managed?).to eq(false)
      end
    end
  end

  describe '#all_running?' do
    context 'when all resource instances are running' do
      it 'should return true' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test10.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test10.mon.xml')))
        HANAUpdater::Cluster.update_state
        grp = HANAUpdater::Cluster.get_system(const.system.id, const.system.instance)
        expect(grp).not_to be_nil
        expect(grp.all_running?).to eq(true)
      end
    end

    context 'when not all instances are running' do
      it 'should return false' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test11.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test11.mon.xml')))
        HANAUpdater::Cluster.update_state
        grp = HANAUpdater::Cluster.get_system(const.system.id, const.system.instance)
        expect(grp).not_to be_nil
        expect(grp.all_running?).to eq(false)
      end
    end
  end

  describe 'internal state' do
    it 'should always differentiate between remote and local' do
      allow(HANAUpdater::Cluster).to receive(:get_cib)
        .and_return(REXML::Document.new(test_file('cibadmin.xml')))
      allow(HANAUpdater::Cluster).to receive(:get_crm_mon)
        .and_return(REXML::Document.new(test_file('crm_mon.xml')))
      # fake our hostname
      allow(Socket).to receive(:gethostname).and_return('hana01')
      HANAUpdater::Cluster.update_state
      grp = HANAUpdater::Cluster.get_system(const.system.id, const.system.instance)
      local = grp.master.local
      expect(local.mon_attr['nodes_running_on']).to eq '1'
      expect(local.running_on.name).to eq const.local.host_name
      remote = grp.master.remote
      expect(local).not_to eq(remote)
      expect(local.running_on.site).not_to eq remote.running_on.site
    end
  end

  # Test different cluster configurations
  describe '#update_state' do
    context 'when cluster has no resources configured' do
      it 'raises an exception' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test00.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test00.mon.xml')))
        expect(HANAUpdater::Cluster.groups).to be_empty
        expect {HANAUpdater::Cluster.update_state}.to raise_error(HANAUpdater::Exceptions::ClusterConfigurationError, /Could not find any SAP HANA/)
        expect(HANAUpdater::Cluster.groups).to be_empty
      end
    end

    context 'there is no vIP resource configured' do
      it 'issues a warning and skips the system' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test01.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test01.mon.xml')))
        HANAUpdater::Cluster.update_state
        expect(HANAUpdater::Cluster.warnings).to match_message(/colocation/)
        expect(HANAUpdater::Cluster.groups).to be_empty
      end
    end

    context 'there is no colocation rule for the vIP' do
      it 'issues a warning and skips the system' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test02.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test02.mon.xml')))
        HANAUpdater::Cluster.update_state
        expect(HANAUpdater::Cluster.warnings).to match_message(/colocation/)
        expect(HANAUpdater::Cluster.groups).to be_empty
      end
    end

    context 'there is no SAPHanaTopology agent' do
      it 'issues a warning and skips the system' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test03.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test03.mon.xml')))
        HANAUpdater::Cluster.update_state
        expect(HANAUpdater::Cluster.warnings).to match_message(/Topology/)
        expect(HANAUpdater::Cluster.groups).to be_empty
      end
    end

    context 'there is no SAPHana agent' do
      it 'raises an exception' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test04.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test04.mon.xml')))
        expect {HANAUpdater::Cluster.update_state}.to raise_error(HANAUpdater::Exceptions::ClusterConfigurationError, /SAP HANA/)
        expect(HANAUpdater::Cluster.groups).to be_empty
      end
    end

    context 'two systems, PRD has no SAPHana resource and no constraints' do
      it 'skips system PRD completely' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test05.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test05.mon.xml')))
        HANAUpdater::Cluster.update_state
        expect(HANAUpdater::Cluster.warnings).to be_empty
        expect(HANAUpdater::Cluster.groups.length).to eq(1)
        expect(HANAUpdater::Cluster.groups.first.hana_sid).to eq('QAS')
      end
    end

    context 'two systems, QAS has no SAPHanaTopology agent' do
      it 'skips system QAS, issues a warning' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test06.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test06.mon.xml')))
        HANAUpdater::Cluster.update_state
        expect(HANAUpdater::Cluster.warnings).to match_message(/SAPHanaTopology/)
        expect(HANAUpdater::Cluster.groups.length).to eq(1)
        expect(HANAUpdater::Cluster.groups.first.hana_sid).to eq('PRD')
      end
    end

    context 'two systems, QAS has no SAPHanaTopology clone, PRD has no colocation' do
      it 'lists no systems' do
        HANAUpdater::Cluster.reset
        expect(HANAUpdater::Cluster).to receive(:get_cib)
          .and_return(REXML::Document.new(test_file('xmls/test07.cib.xml')))
        expect(HANAUpdater::Cluster).to receive(:get_crm_mon)
          .and_return(REXML::Document.new(test_file('xmls/test07.mon.xml')))
        HANAUpdater::Cluster.update_state
        expect(HANAUpdater::Cluster.warnings).to match_message(/SAPHanaTopology/)
        expect(HANAUpdater::Cluster.warnings).to match_message(/colocation/)
        expect(HANAUpdater::Cluster.groups).to be_empty
      end
    end
  end
end
