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
  class SystemReplicationException < StandardError
  end

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
      log.warn '--- Setting resources to maintenance mode ---'
      Yast::Popup.Feedback('Please wait', 'Setting resources to maintenance mode') do
        HANAUpdater::System.resource_maintenance(sap_sys.master.id, :on)
        HANAUpdater::System.resource_maintenance(sap_sys.clone.id, :on)
        HANAUpdater::System.resource_maintenance(sap_sys.vip.id, :on)
      end
      # stop HANA on local node, so that the replication can be disabled
      log.warn '--- Stopping SAP HANA on local node ---'
      Yast::Popup.Feedback('Please wait', 'Stopping SAP HANA on local node') do
        HANAUpdater::Hana.stop(sap_sys.hana_sid, node: :local)
      end
      # break replication
      log.warn '--- Disabling system replication ---'
      Yast::Popup.Feedback('Please wait', 'Disabling system replication') do
        HANAUpdater::Hana.disable_secondary(sap_sys.hana_sid)
      end
      # start HANA to apply SR settings
      log.warn '--- Starting SAP HANA on local node ---'
      Yast::Popup.Feedback('Please wait', 'Starting SAP HANA on local node') do
        HANAUpdater::Hana.start(sap_sys.hana_sid)
      end
      # mount update medium
      if config.nfs.should_mount?
        log.warn "--- Mounting update medium '#{config.nfs.source}' ---"
        Yast::Popup.Feedback('Please wait', 'Mounting update medium') do
          local_path = HANAUpdater::System.mount_nfs(config.nfs.source)
          config.nfs.mount_path = local_path
        end
      end
      # copy update medium
      if config.nfs.copy_medium?
        log.warn "--- Copying contents of the update medium '#{config.nfs.source}' to '#{config.nfs.copy_path}' ---"
        Yast::Popup.Feedback('Please wait', 'Copying contents of the update medium') do
          HANAUpdater::System.recursive_copy(config.nfs.mount_path, config.nfs.copy_path, sap_sys.hana_sid)
        end
      end
      # # TODO: start HANA for update?
      # # # start HANA on local node, so that the replication can be disabled
      # Yast::Popup.Feedback('Please wait', 'Stopping SAP HANA on local node') do
      #   HANAUpdater::Hana.hdb_stop(sap_sys.hana_sid)
      # end
    end

    def execute_remote_update_plan(config)
      sap_sys = config.system
      remote_node = sap_sys.master.remote.running_on.name
      local_node = sap_sys.master.local.running_on.name
      log.warn '--- Stopping SAP HANA on local node ---'
      Yast::Popup.Feedback('Please wait', 'Stopping SAP HANA on local node') do
        HANAUpdater::Hana.stop(sap_sys.hana_sid)
      end
      log.warn '--- Registering local HANA instance for SR ---'
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
      log.warn '--- Starting SAP HANA on local node ---'
      Yast::Popup.Feedback('Please wait', 'Starting SAP HANA on local node') do
        HANAUpdater::Hana.start(sap_sys.hana_sid)
      end
      log.warn '--- Waiting for data to be synchronized ---'
      Yast::Popup.Feedback('Please wait', 'Waiting for data to be synchronized') do
        begin
          check_system_replication(sap_sys.hana_sid, node: sap_sys.master.remote.running_on.name)
        rescue SystemReplicationException => e
          answer = Yast::Popup.AnyQuestion('Error while checking System Replication Status',
                                           e.message,
                                           'Retry', 'Cancel', :focus_yes
          )
          retry if answer
        end
      end
      log.warn '--- System Replication: Taking over to local site ---'
      Yast::Popup.Feedback('Please wait', 'Taking over to local site') do
        HANAUpdater::Hana.takeover(sap_sys.hana_sid)
      end
      log.warn '--- Migrating the virtual IP ---'
      Yast::Popup.Feedback('Please wait', 'Migrating the virtual IP') do
        out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :check, node: remote_node)
        log.info "--- #{self.class}.#{__callee__} : check vIP running on remote node #{remote_node}: rc=#{status.exitstatus}"
        if status.exitstatus == 0
          out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :stop, node: remote_node)
          log.info "--- #{self.class}.#{__callee__} : stop vIP on remote node #{remote_node}: rc=#{status.exitstatus}"
        end
        out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :start, node: :local)
        log.info "--- #{self.class}.#{__callee__} : start vIP on local node #{local_node}: rc=#{status.exitstatus}, out=#{out}"
      end
      log.warn "Disabling replication between nodes #{remote_node} and #{local_node}"
      Yast::Popup.Feedback('Please wait', "Disabling replication between nodes #{remote_node} and #{local_node}") do
        HANAUpdater::Hana.disable_secondary(sap_sys.hana_sid)
        cmd_line = HANAUpdater::Hana.disable_primary_cmd(sap_sys.hana_sid)
        status = HANAUpdater::SSH.run_command_wait(remote_node, *cmd_line)
        log.info "--- #{self.class}.#{__callee__} : disable system replication on source site #{remote_node}: rc=#{status.exitstatus}"
      end
      if config.nfs.should_mount?
        log.warn "--- Mounting update medium '#{config.nfs.source}' on node #{remote_node} ---"
        Yast::Popup.Feedback('Please wait', 'Mounting update medium') do
          local_path = HANAUpdater::System.mount_nfs(config.nfs.source, node: remote_node)
          config.nfs.mount_path = local_path
        end
      end
      if config.nfs.copy_medium?
        log.warn "--- Copying contents of the update medium '#{config.nfs.source}' to '#{config.nfs.copy_path}' on node #{remote_node}---"
        Yast::Popup.Feedback('Please wait', 'Copying contents of the update medium') do
          HANAUpdater::System.recursive_copy(config.nfs.mount_path, config.nfs.copy_path, sap_sys.hana_sid, node: remote_node)
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
    def restore_cluster(config)
      # TODO: implement
      # enable replication on local
      # register remote as secondary to local
      # wait for sync
    end

    def check_system_replication(system_id, opts={node: :local})
      cmd_line = HANAUpdater::Hana.check_sys_replication_cmd(system_id)
      statuses = {10 => 'No HANA SR', 11 => 'Fatal Error', 12 => 'Unknown',
                  13 => 'Initializing', 14 => 'Syncing', 15 => 'Active'}
      while true
        if opts[:node] == :local
          # TODO: change me
          status = HANAUpdater::SSH.run_command_wait(sap_sys.master.remote.running_on.name, *cmd_line)
        else
          status = HANAUpdater::SSH.run_command_wait(opts[:node], *cmd_line)
        end
        case status.exitstatus
          when 10, 11
            log.error "--- systemReplicationStatus.py reports status #{status.exitstatus} '#{statuses[status.exitstatus]}'"
            raise SystemReplicationException, "systemReplicationStatus.py reports status #{status.exitstatus} '#{statuses[status.exitstatus]}'"
          when 12, 13, 14
            log.warn "--- systemReplicationStatus.py reports status #{status.exitstatus} '#{statuses[status.exitstatus]}'. Will wait"
            sleep 10
          when 15
            log.warn '--- systemReplicationStatus.py reports status 15 (Active) (instances are in sync)'
          else
            log.error "--- Unexpected status returned from systemReplicationStatus.py: rc=#{status.exitstatus}"
            raise SystemReplicationException, "Unexpected status returned from systemReplicationStatus.py: rc=#{status.exitstatus}"
        end
      end
      true
    end
  end
end
