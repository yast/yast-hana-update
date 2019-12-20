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
require 'hana_update/system'

describe HANAUpdater::SystemClass do
  let(:const) { Constants.new }

  # rubocop:disable Style/BlockDelimiters

  describe '#resource_maintenance' do
    it 'sets resource attribute to true' do
      expect_syscall(
        type:   :output,
        cmd:    ['crm', 'resource', 'maintenance', const.resources[:vip], 'on'],
        output: '',
        rc:     0
      )
      _, status = HANAUpdater::System.resource_maintenance(const.resources[:vip], :on)
      expect(status.exitstatus).to eq 0
    end

    it 'sets resource attribute to off' do
      expect_syscall(
        type:   :output,
        cmd:    ['crm', 'resource', 'maintenance', const.resources[:vip], 'off'],
        output: '',
        rc:     0
      )
      _, status = HANAUpdater::System.resource_maintenance(const.resources[:vip], :off)
      expect(status.exitstatus).to eq 0
    end
  end

  describe '#resource_cleanup' do
    it 'cleans up resource status' do
      expect_syscall(
        type:   :output,
        cmd:    ['crm', 'resource', 'cleanup', const.resources[:vip]],
        output: '',
        rc:     0
      )
      _, status = HANAUpdater::System.resource_cleanup(const.resources[:vip])
      expect(status.exitstatus).to eq 0
    end
  end

  describe '#resource_force' do
    context 'on remote node' do
      it 'forces resource start' do
        expect_syscall(
          type:   :output,
          cmd:    ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                   'crm_resource', '--force-start', '--resource', const.resources[:vip]],
          output: '',
          rc:     0
        )
        _, status = HANAUpdater::System.resource_force(const.resources[:vip], :start,
          node: const.remote.host_name)
        expect(status.exitstatus).to eq 0
      end

      it 'forces resource stop' do
        expect_syscall(
          type:   :output,
          cmd:    ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                   'crm_resource', '--force-stop', '--resource', const.resources[:vip]],
          output: '',
          rc:     0
        )
        _, status = HANAUpdater::System.resource_force(const.resources[:vip],
          :stop, node: const.remote.host_name)
        expect(status.exitstatus).to eq 0
      end

      it 'forces resource check' do
        expect_syscall(
          type:   :output,
          cmd:    ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                   'crm_resource', '--force-check', '--resource', const.resources[:vip]],
          output: '',
          rc:     0
        )
        _, status = HANAUpdater::System.resource_force(const.resources[:vip], :check,
          node: const.remote.host_name)
        expect(status.exitstatus).to eq 0
      end

      it 'does not accept other verbs' do
        expect { HANAUpdater::System.resource_force(const.resources[:vip], :move,
          node: const.remote.host_name) }.to raise_error(ArgumentError)
      end
    end

    context 'on local node' do
      it 'forces resource start' do
        expect_syscall(
          type:   :output,
          cmd:    ['crm_resource', '--force-start', '--resource', const.resources[:vip]],
          output: '',
          rc:     0
        )
        _, status = HANAUpdater::System.resource_force(const.resources[:vip], :start)
        expect(status.exitstatus).to eq 0
      end

      it 'forces resource stop' do
        expect_syscall(
          type:   :output,
          cmd:    ['crm_resource', '--force-stop', '--resource', const.resources[:vip]],
          output: '',
          rc:     0
        )
        _, status = HANAUpdater::System.resource_force(const.resources[:vip], :stop)
        expect(status.exitstatus).to eq 0
      end

      it 'forces resource check' do
        expect_syscall(
          type:   :output,
          cmd:    ['crm_resource', '--force-check', '--resource', const.resources[:vip]],
          output: '',
          rc:     0
        )
        _, status = HANAUpdater::System.resource_force(const.resources[:vip], :check)
        expect(status.exitstatus).to eq 0
      end

      it 'does not accept other verbs' do
        expect { HANAUpdater::System.resource_force(const.resources[:vip], :move) }.to\
          raise_error(ArgumentError)
      end
    end
  end

  describe '#mount_nfs' do
    context 'on local node' do
      it 'mounts an NFS share' do
        expect(Dir).to receive(:mktmpdir).with('hana').and_return('/tmp/hana1')
        expect_syscall(
          type:   :output,
          cmd:    %w(mount host_name:/path/to/share /tmp/hana1),
          output: '',
          rc:     0
        )
        local_path = HANAUpdater::System.mount_nfs('host_name:/path/to/share')
        expect(local_path).to eq '/tmp/hana1'
      end
    end

    context 'on remote node' do
      it 'mounts an NFS share' do
        expect_syscall(
          type:   :output,
          cmd:    ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                   'mktemp', '-d'],
          output: "/tmp/hana1\n",
          rc:     0
        )
        expect_syscall(
          type:   :output,
          cmd:    ['ssh', '-o', 'StrictHostKeyChecking=no', "root@#{const.remote.host_name}",
                   'mount', 'host_name:/path/to/share', '/tmp/hana1'],
          output: "/tmp/hana1\n",
          rc:     0
        )
        local_path = HANAUpdater::System.mount_nfs('host_name:/path/to/share', node: const.remote.host_name)
        expect(local_path).to eq '/tmp/hana1'
      end
    end
  end

  describe '#recursive_copy' do
    context 'on local node' do
      it 'copies the update medium' do
        source_path = '/tmp/hana1'
        destination_path = '/hana/upd'
        expect(Dir).to receive(:exist?).with(destination_path).and_return(true)
        expect_syscall(
          type:   :output,
          cmd:    %w(cp -far /tmp/hana1/. /hana/upd),
          output: '',
          rc:     0
        )
        expect_syscall(
          type:   :output,
          cmd:    %W(chown -R #{const.system.user}:sapsys /hana/upd),
          output: '',
          rc:     0
        )
        status = HANAUpdater::System.recursive_copy(source_path, destination_path, const.system.id)
        expect(status).to eq true
      end
    end

    context 'on remote node' do
      it 'copies the update medium' do
        source_path = '/tmp/hana1'
        destination_path = '/hana/upd'
        expect_syscall(
          type:   :status,
          cmd:    %W(ssh -o StrictHostKeyChecking=no root@#{const.remote.host_name} test -d /hana/upd),
          output: '',
          rc:     0
        )
        expect_syscall(
          type:   :output,
          cmd:    %W(ssh -o StrictHostKeyChecking=no root@#{const.remote.host_name} cp -far /tmp/hana1/. /hana/upd),
          output: '',
          rc:     0
        )
        expect_syscall(
          type:   :output,
          cmd:    %W(ssh -o StrictHostKeyChecking=no root@#{const.remote.host_name}
                     chown -R #{const.system.user}:sapsys /hana/upd),
          output: '',
          rc:     0
        )
        status = HANAUpdater::System.recursive_copy(source_path, destination_path,
          const.system.id, node: const.remote.host_name)
        expect(status).to eq true
      end
    end
  end
end
