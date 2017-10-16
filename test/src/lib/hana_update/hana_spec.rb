# -*- encoding: utf-8 -*-
require_relative '../../../test_helper'
require 'hana_update/hana'

describe HANAUpdater::HanaClass do
  let (:const) {Constants.new}
  let(:hdb_version_1_sps12) {test_file('hdb_version_out_1.00.121.txt')}
  let(:hdb_version_2_sps01) {test_file('hdb_version_out_2.00.010.txt')}

  describe '#start' do
    context 'starting a local HANA' do
      it 'starts HANA' do
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'HDB start', const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.start(const.system.id)
        expect(result).to eq true
      end

      it 'starts HANA even if the first call does not succeed' do
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'HDB start', const.system.user],
                       output: '',
                       rc: 1
        )
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'HDB start', const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.start(const.system.id)
        expect(result).to eq true
      end
    end


    context 'starting a remote HANA' do
      it 'starts HANA' do
        expect_syscall(type: :output,
                       cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.local.host_name}",
                             'su', '-lc', '"HDB start"', const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.start(const.system.id, node: const.local.host_name)
        expect(result).to eq true
      end
    end
  end

  describe '#stop' do
    context 'stopping a local HANA' do
      it 'stops HANA' do
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'HDB stop', const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.stop(const.system.id)
        expect(result).to eq true
      end

      it 'stops HANA even if the first call does not succeed' do
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'HDB stop', const.system.user],
                       output: '',
                       rc: 1
        )
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'HDB stop', const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.stop(const.system.id)
        expect(result).to eq true
      end
    end


    context 'stopping a remote HANA' do
      it 'stops HANA' do
        expect_syscall(type: :output,
                       cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                             'su', '-lc', '"HDB stop"', const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.stop(const.system.id, node: const.remote.host_name)
        expect(result).to eq true
      end
    end
  end


  describe '#version' do
    context 'querying local HANA' do
      context 'when the call to HDB succeeds' do
        it 'returns the version string' do
          expect_syscall(type: :output,
                         cmd: ['su', '-lc', 'HDB version', const.system.user],
                         output: hdb_version_1_sps12,
                         rc: 0
          )
          result = HANAUpdater::Hana.version(const.system.id)
          expect(result).to eq '1.00.121.00.1466466057'
          expect_syscall(type: :output,
                         cmd: ['su', '-lc', 'HDB version', const.system.user],
                         output: hdb_version_2_sps01,
                         rc: 0
          )
          result = HANAUpdater::Hana.version(const.system.id)
          expect(result).to eq '2.00.010.00.1491294693'
        end
      end

      context 'when the call to HDB succeeds, but the version string is garbled' do
        it 'returns nil' do
          expect_syscall(type: :output,
                         cmd: ['su', '-lc', 'HDB version', const.system.user],
                         output: '',
                         rc: 0
          )
          result = HANAUpdater::Hana.version(const.system.id)
          expect(result).to eq nil
        end
      end

      context 'when the call to HDB fails' do
        it 'returns nil' do
          expect_syscall(type: :output,
                         cmd: ['su', '-lc', 'HDB version', const.system.user],
                         output: '',
                         rc: 1
          )
          result = HANAUpdater::Hana.version(const.system.id)
          expect(result).to eq nil
        end
      end
    end

    context 'querying remote HANA' do
      context 'when the call to HDB succeeds' do
        it 'returns the version string' do
          expect_syscall(type: :output,
                         cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                               'su', '-lc', '"HDB version"', const.system.user],
                         output: hdb_version_1_sps12,
                         rc: 0
          )
          result = HANAUpdater::Hana.version(const.system.id, node: const.remote.host_name)
          expect(result).to eq '1.00.121.00.1466466057'
        end
      end

      context 'when the call to HDB succeeds, but the version string is garbled' do
        it 'returns nil' do
          expect_syscall(type: :output,
                         cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                               'su', '-lc', '"HDB version"', const.system.user],
                         output: '',
                         rc: 0
          )
          result = HANAUpdater::Hana.version(const.system.id, node: const.remote.host_name)
          expect(result).to eq nil
        end
      end

      context 'when the call to HDB fails' do
        it 'returns nil' do
          expect_syscall(type: :output,
                         cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                               'su', '-lc', '"HDB version"', const.system.user],
                         output: '',
                         rc: 1
          )
          result = HANAUpdater::Hana.version(const.system.id, node: const.remote.host_name)
          expect(result).to eq nil
        end
      end
    end
  end

  describe '#sr_enable_primary' do
    context 'enabling local instance' do
      it 'enables system replication' do
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', "hdbnsutil -sr_enable --name=#{const.local.site_name}", const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.sr_enable_primary(const.system.id, const.local.site_name)
        expect(result).to eq true
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', "hdbnsutil -sr_enable --name=#{const.local.site_name}", const.system.user],
                       output: '',
                       rc: 1
        )
        result = HANAUpdater::Hana.sr_enable_primary(const.system.id, const.local.site_name)
        expect(result).to eq false
      end
    end

    context 'enabling remote instance' do
      it 'enables system replication' do
        expect_syscall(type: :output,
                       cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                             'su', '-lc', "\"hdbnsutil -sr_enable --name=#{const.local.site_name}\"", const.system.user],
                       output: '',
                       rc: 0
        )
        # expect(HANAUpdater::SSH).to receive(:rexec_wait_get_output)
        #                                 .with(const.remote.host_name, "su -lc \"hdbnsutil -sr_enable --name=#{const.local.site_name}\" #{const.system.user}")
        #                                 .and_return(['', good_exit])
        result = HANAUpdater::Hana.sr_enable_primary(const.system.id, const.local.site_name, node: const.remote.host_name)
        expect(result).to eq true
      end
    end
  end

  describe '#sr_disable_primary' do
    context 'disabling local instance' do
      it 'disables system replication' do
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'hdbnsutil -sr_disable', const.system.user],
                       output: '',
                       rc: 0
        )
        # expect(HANAUpdater::Hana).to receive(:su_exec_get_output)
        #                                  .with(const.system.user, 'hdbnsutil', '-sr_disable')
        #                                  .and_return(['', good_exit])
        result = HANAUpdater::Hana.sr_disable_primary(const.system.id)
        expect(result).to eq true
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'hdbnsutil -sr_disable', const.system.user],
                       output: '',
                       rc: 0
        )
        # expect(HANAUpdater::Hana).to receive(:su_exec_get_output)
        #                                  .with(const.system.user, 'hdbnsutil', '-sr_disable')
        #                                  .and_return(['', good_exit])
        result = HANAUpdater::Hana.sr_disable_primary(const.system.id, node: :local)
        expect(result).to eq true
      end
    end

    context 'disabling remote instance' do
      it 'disables system replication' do
        expect_syscall(type: :output,
                       cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                             'su', '-lc', '"hdbnsutil -sr_disable"', const.system.user],
                       output: hdb_version_1_sps12,
                       rc: 0
        )
        result = HANAUpdater::Hana.sr_disable_primary(const.system.id, node: const.remote.host_name)
        expect(result).to eq true
      end
    end
  end

  describe '#sr_register_secondary' do
    context 'registering a local instance' do
      it 'registers an instance for replication' do
        # TODO: check that it will work for HANA 1.0 SPS10, too
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', 'HDB version', const.system.user],
                       output: hdb_version_1_sps12,
                       rc: 0
        )
        expect_syscall(type: :output,
                       cmd: ['su', '-lc',
                             %W(hdbnsutil -sr_register --remoteHost=#{const.remote.host_name}
                                --remoteInstance=#{const.system.instance}
                                --replicationMode=#{const.replication_modes[0]}
                                --operationMode=#{const.operation_modes[0]}
                                --name=#{const.local.site_name}).join(' '), const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.sr_register_secondary(const.system.id, const.system.instance, const.local.site_name,
                                                         const.remote.host_name, const.replication_modes[0],
                                                         const.operation_modes[0])
        expect(result).to eq true
      end
    end

    context 'registering a remote instance' do
      it 'registers an instance for replication' do
        expect_syscall(type: :output,
                       cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                             'su', '-lc', '"HDB version"', const.system.user],
                       output: hdb_version_1_sps12,
                       rc: 0
        )
        inner_cmd = %W(hdbnsutil -sr_register --remoteHost=#{const.remote.host_name}
                                --remoteInstance=#{const.system.instance}
                                --replicationMode=#{const.replication_modes[0]}
                                --operationMode=#{const.operation_modes[0]}
                                --name=#{const.local.site_name}).join(' ')
        inner_cmd = "\"#{inner_cmd}\""
        expect_syscall(type: :output,
                       cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}", 'su', '-lc',
                             inner_cmd, const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.sr_register_secondary(const.system.id, const.system.instance, const.local.site_name,
                                                         const.remote.host_name, const.replication_modes[0],
                                                         const.operation_modes[0], node: const.remote.host_name)
        expect(result).to eq true
      end
    end
  end

  describe '#sr_unregister_secondary' do
    context 'de-registering a local instance' do
      it 'de-registers an instance for replication' do
        expect_syscall(type: :output,
                       cmd: ['su', '-lc', "hdbnsutil -sr_unregister", const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.sr_unregister_secondary(const.system.id, const.remote.site_name)
        expect(result).to eq true
      end
    end

    context 'de-registering a remote instance' do
      it 'de-registers an instance for replication' do
        expect_syscall(type: :output,
                       cmd: ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                             'su', '-lc', '"hdbnsutil -sr_unregister"', const.system.user],
                       output: '',
                       rc: 0
        )
        result = HANAUpdater::Hana.sr_unregister_secondary(const.system.id, const.local.site_name, node: const.remote.host_name)
        expect(result).to eq true
      end
    end
  end

  describe '#sr_check_status' do
    # TODO
  end

  describe '#sr_takeover' do
    # TODO
  end


end
