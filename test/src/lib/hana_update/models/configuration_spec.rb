# -*- encoding: utf-8 -*-
require 'rspec'
require_relative '../../../../test_helper'
require 'hana_update/models/configuration'

describe HANAUpdater::Configuration do
  let(:const) { Constants.new }

  describe '#select_hana_system' do
    it 'selects the specified system if it was detected' do
      allow(HANAUpdater::Cluster).to receive(:get_cib)
        .and_return(REXML::Document.new(test_file('cibadmin.xml')))
      allow(HANAUpdater::Cluster).to receive(:get_crm_mon)
        .and_return(REXML::Document.new(test_file('crm_mon.xml')))
      expect(HANAUpdater::Cluster.groups).to be_empty
      HANAUpdater::Cluster.update_state
      conf = described_class.new
      conf.select_hana_system(const.system.id)
      expect(conf.system).not_to be_nil
      expect(conf.system.hana_sid).to eq(const.system.id)
    end

    it 'leaves the system to be nil if provided with a non-existent SID' do
      # Do not re-initialize the Cluster class, it already contains the data
      conf = described_class.new
      conf.select_hana_system('ZZZ')
      expect(conf.system).to be_nil
    end
  end

  describe 'NFS shares handling' do
    it 'Handles NFS share paths in a right way' do
      conf = described_class.new
      conf.nfs.should_mount = true
      conf.nfs.source = ''
      expect(conf.nfs.validate(:verbose)).to_not be_empty
      expect(conf.nfs.validate(:silent)).to eq(false)
      conf.nfs.source = 'garbage'
      expect(conf.nfs.validate(:verbose)).to_not be_empty
      expect(conf.nfs.validate(:silent)).to eq(false)
      conf.nfs.source = 'nfs://server/and/path'
      expect(conf.nfs.validate(:verbose)).to_not be_empty
      expect(conf.nfs.validate(:silent)).to eq(false)
      conf.nfs.source = 'myserver.mydomain:/path/to/share'
      expect(HANAUpdater::System).to receive(:mount_nfs).with(conf.nfs.source, node: :local)
        .and_return('/tmp/yourmount').twice
      expect(HANAUpdater::System).to receive(:unmount_nfs).with('/tmp/yourmount').twice
      expect(conf.nfs.validate(:verbose)).to be_empty
      expect(conf.nfs.validate(:silent)).to eq(true)
    end
  end
end
