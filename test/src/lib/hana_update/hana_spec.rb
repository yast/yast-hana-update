# -*- encoding: utf-8 -*-
require_relative '../../../test_helper'
require 'hana_update/hana'

describe HANAUpdater::HanaClass do

  describe '#check_hdb_daemon_running' do
    it 'reports that HDB daemon is running' do
      result = HANAUpdater::Hana.check_hdb_daemon_running('DEV', 10)
      expect(result).to eq(false)
    end
  end

  describe '#discover' do
    def file_contents(path)
      File.readlines(File.join('test/data/', path))
    end

    it 'returns an empty array when no HANA is installed' do
      hanas = HANAUpdater::Hana.discover
      expect(hanas).to be_empty
    end

    it 'discovers HANA when a single HANA is installed' do
      c = file_contents('sapservice_one_hana.txt')
      expect(File).to receive(:exist?).with(HANAUpdater::HanaClass::SAP_SERVICES_PATH).and_return(true)
      expect(File).to receive(:readlines).with(HANAUpdater::HanaClass::SAP_SERVICES_PATH).and_return(c)
      hanas = HANAUpdater::Hana.discover
      expect(hanas).not_to be_nil
      expect(hanas).not_to be_empty
      expect(hanas.length).to eq 1
      expect(hanas).to include({sid: 'DEV', instance: '00', virtual_host: 'hana02'})
    end

    it 'discovers HANA when two SAP products are installed' do
      c = file_contents('sapservice_two_sap.txt')
      expect(File).to receive(:exist?).with(HANAUpdater::HanaClass::SAP_SERVICES_PATH).and_return(true)
      expect(File).to receive(:readlines).with(HANAUpdater::HanaClass::SAP_SERVICES_PATH).and_return(c)
      hanas = HANAUpdater::Hana.discover
      expect(hanas).not_to be_nil
      expect(hanas).not_to be_empty
      expect(hanas.length).to eq 1
      expect(hanas).to include({sid: 'QNH', instance: '00', virtual_host: 'ix64sap001'})
    end

    it 'discovers HANA when two HANAs are installed' do
      c = file_contents('sapservice_two_hanas.txt')
      expect(File).to receive(:exist?).with(HANAUpdater::HanaClass::SAP_SERVICES_PATH).and_return(true)
      expect(File).to receive(:readlines).with(HANAUpdater::HanaClass::SAP_SERVICES_PATH).and_return(c)
      hanas = HANAUpdater::Hana.discover
      expect(hanas).not_to be_nil
      expect(hanas).not_to be_empty
      expect(hanas.length).to eq 2
    end
  end


  # TODO: auto-generated
  describe '#hdb_start' do
    it 'works' do
      result = HANAUpdater::Hana.hdb_start(system_id)
      expect(result).to eq true
    end
  end

  # TODO: auto-generated
  describe '#version' do
    it 'works' do
      result = HANAUpdater::Hana.version(system_id)
      expect(result).not_to be_nil
      # TODO: copy from the yast-sap-ha
    end
  end

  # TODO: auto-generated
  describe '#hdb_stop' do
    it 'works' do
      result = HANAUpdater::Hana.hdb_stop(system_id)
      expect(result).not_to be_nil
    end
  end

  # TODO: auto-generated
  describe '#enable_primary' do
    it 'works' do
      result = HANAUpdater::Hana.enable_primary(system_id, site_name)
      expect(result).not_to be_nil
    end
  end

  # TODO: auto-generated
  describe '#enable_secondary' do
    it 'works' do
      result = HANAUpdater::Hana.enable_secondary(system_id, site_name, host_name_primary, instance, rmode, omode)
      expect(result).not_to be_nil
    end
  end

  # TODO: auto-generated
  describe '#check_secure_store' do
    it 'works' do
      result = HANAUpdater::Hana.check_secure_store(system_id)
      expect(result).not_to be_nil
    end
  end

  # TODO: auto-generated
  describe '#set_secute_store' do
    it 'works' do
      result = HANAUpdater::Hana.set_secute_store(system_id, key_name, env, user_name, password)
      expect(result).not_to be_nil
    end
  end

  # TODO: auto-generated
  describe '#hdbsql_command' do
    it 'works' do
      result = HANAUpdater::Hana.hdbsql_command(system_id, user_name, instance_number, password, environment, statement)
      expect(result).not_to be_nil
    end
  end


end
