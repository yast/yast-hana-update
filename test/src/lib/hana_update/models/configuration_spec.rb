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
    end

    it 'leaves the system to be nil if provided with a non-existent SID' do
      conf = described_class.new
      conf.select_hana_system('ZZZ')
      expect(conf.system).to be_nil
    end
  end
end
