# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE Linux GmbH, Nuremberg, Germany.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE Linux GmbH.
#
# ------------------------------------------------------------------------------
#
# Summary: SAP HANA updater in a SUSE cluster
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'singleton'
require 'yast'
Yast.import 'Popup'
require 'hana_update/helpers'
require 'hana_update/cluster'
require 'hana_update/system'
require 'hana_update/ssh'


module HANAUpdater
  # Base class for component configuration
  class Executor
    include Yast::Logger
    include Singleton

    def execute_update_plan(part, config)
      case part
        when :local
          execute_local_update_plan(config)
        when :remote
          execute_remote_update_plan(config)
        when :restore
          restore_cluster(config, true)
        else
          raise ArgumentError, "unknown part=#{part.inspect}"
      end
    end

    def execute_local_update_plan(config)
      sap_sys = config.system
      # put resources to maintenance mode
      Yast::Popup.Feedback('Please wait', 'Setting resources to maintenance mode') do
        HANAUpdater::System.resource_maintenance(sap_sys.master.id, :on)
        HANAUpdater::System.resource_maintenance(sap_sys.clone.id, :on)
        HANAUpdater::System.resource_maintenance(sap_sys.vip.id, :on)
      end
      # stop HANA on local node, so that the replication can be disabled
      Yast::Popup.Feedback('Please wait', 'Stopping SAP HANA on local node') do
        HANAUpdater::Hana.hdb_stop(sap_sys.hana_sid)
      end
      # break replication
      Yast::Popup.Feedback('Please wait', 'Disabling system replication') do          
        HANAUpdater::Hana.disable_secondary(sap_sys.hana_sid.downcase)
      end
      # mount update medium
      if config.nfs.should_mount?
        Yast::Popup.Feedback('Please wait', 'Mounting update medium') do
          local_path = HANAUpdater::System.mount_nfs(config.nfs.source)
          config.nfs.mount_path = local_path
        end
      end
      # copy update medium
      if config.nfs.copy_medium?
        Yast::Popup.Feedback('Please wait', 'Copying contents of the update medium') do
          HANAUpdater::System.recursive_copy(config.nfs.mount_path, config.nfs.copy_path)
        end
      end
      # TODO: start HANA for update?
      # # start HANA on local node, so that the replication can be disabled
      # Yast::Popup.Feedback('Please wait', 'Stopping SAP HANA on local node') do
      #   HANAUpdater::Hana.hdb_stop(sap_sys.hana_sid)
      # end
    end

    def execute_remote_update_plan(config)
        # TODO: what kind of omode should we use here?
        # operation modes for system replication:
        # > delta_datashipping [def]
        # > logreplay
        # TODO: get from cluster attribute hana_<SID>_op_mode
      sap_sys = config.system
      Yast::Popup.Feedback('Please wait', 'Stopping SAP HANA on local node') do
        HANAUpdater::Hana.hdb_stop(sap_sys.hana_sid)
      end
      Yast::Popup.Feedback('Please wait', 'Registering local HANA instance for SR') do
        # cmd_line = HANAUpdater::Hana.enable_secondary_cmd(
        #   sap_sys.hana_sid,
        #   sap_sys.master.local.running_on.site,
        #   sap_sys.master.remote.running_on.name,
        #   sap_sys.hana_inst,
        #   sap_sys.master.local.running_on.instance_attributes['srmode'],
        #   sap_sys.clone.local.running_on.instance_attributes['op_mode']
        # )
        # HANAUpdater::SSH.run_command_wait(remote.running_on.name, cmd_line)
        HANAUpdater::Hana.enable_secondary(
          sap_sys.hana_sid,
          sap_sys.master.local.running_on.site,
          sap_sys.master.remote.running_on.name,
          sap_sys.hana_inst,
          sap_sys.master.local.running_on.instance_attributes['srmode'],
          sap_sys.clone.local.running_on.instance_attributes['op_mode']
        )
      end
      Yast::Popup.Feedback('Please wait', 'Starting SAP HANA on local node') do
        HANAUpdater::Hana.hdb_start(sap_sys.hana_sid)
      end
      Yast::Popup.Feedback('Please wait', 'Waiting for data to be synchronized') do
        cmd_line = HANAUpdater::Hana.check_sys_replication_cmd(sap_sys.hana_sid)
        status = HANAUpdater::SSH.run_command_wait(sap_sys.master.remote.running_on.name, *cmd_line)
        while status.exitstatus == 14
          log.info "--- #{self.class}.#{__callee__} : remote host #{sap_sys.hana_sid} is syncing ---"
          sleep 10
          status = HANAUpdater::SSH.run_command_wait(sap_sys.master.remote.running_on.name, *cmd_line)
        end
        if status.exitstatus != 15
          log.error "--- #{self.class}.#{__callee__} : remote host #{sap_sys.hana_sid} replied with SR status #{status.exitstatus} ---"
        end
      end
      Yast::Popup.Feedback('Please wait', 'Taking over to local site') do
        HANAUpdater::Hana.takeover(sap_sys.hana_sid)
      end
      Yast::Popup.Feedback('Please wait', 'Migrating the virtual IP') do
        remote_node = sap_sys.master.remote.running_on.name
        local_node = sap_sys.master.local.running_on.name
        out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :check, node: remote_node)
        log.info "--- #{self.class}.#{__callee__} : check vIP running on remote node #{remote_node}: rc=#{status.exitstatus}"
        if status.exitstatus == 0
          out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :stop, node: remote_node)
          log.info "--- #{self.class}.#{__callee__} : stop vIP on remote node #{remote_node}: rc=#{status.exitstatus}"
        end
        out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :start, node: :local)
        log.info "--- #{self.class}.#{__callee__} : start vIP on local node #{local_node}: rc=#{status.exitstatus}, out=#{out}"
      end
      Yast::Popup.Feedback('Please wait', "Disabling replication between nodes #{remote_node} and #{local_node}") do
        HANAUpdater::Hana.disable_secondary(sap_sys.hana_sid)
        cmd_line = HANAUpdater::Hana.disable_primary_cmd(sap_sys.hana_sid)
        status = HANAUpdater::SSH.run_command_wait(remote_node, *cmd_line)
        log.info "--- #{self.class}.#{__callee__} : disable system replication on source site #{remote_node}: rc=#{status.exitstatus}"
      end
      if config.nfs.should_mount?
        Yast::Popup.Feedback('Please wait', 'Mounting update medium') do
          local_path = HANAUpdater::System.mount_nfs(config.nfs.source, node: remote_node)
          config.nfs.mount_path = local_path
        end
      end
      if config.nfs.copy_medium?
        Yast::Popup.Feedback('Please wait', 'Copying contents of the update medium') do
          HANAUpdater::System.recursive_copy(config.nfs.mount_path, config.nfs.copy_path, node: remote_node)
        end
      end
    end

    def remove_copied_medium(source)
      # TODO: implement
    end

    def umount(source)
      # TODO: implement 
    end

    # Restore original cluster state
    # @param config
    # @param full_reverse [Bool]
    def restore_cluster(config, full_reverse)
        # enable replication on local
        # register remote as secondary to local
        # wait for sync
    end
  end
end
