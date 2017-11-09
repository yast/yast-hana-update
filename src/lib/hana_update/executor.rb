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
        restore_cluster(config)
      else
        raise ArgumentError, "unknown part=#{part.inspect}"
      end
    end

    def execute_local_update_plan(config)
      sap_sys = config.system
      # put resources to maintenance mode
      log.warn '--- Setting resources to maintenance mode ---'
      Yast::Popup.Feedback('Please wait', 'Enabling maintenance mode for cluster resources') do
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
        HANAUpdater::Hana.sr_unregister_secondary(sap_sys.hana_sid,
          sap_sys.master.remote.running_on.site, node: :local)
      end
      # start HANA to apply SR settings
      log.warn '--- Starting SAP HANA on local node ---'
      Yast::Popup.Feedback('Please wait', 'Starting SAP HANA on local node') do
        HANAUpdater::Hana.start(sap_sys.hana_sid, node: :local)
      end
      # # mount update medium
      # if config.nfs.should_mount?
      #   log.warn "--- Mounting update medium '#{config.nfs.source}' ---"
      #   Yast::Popup.Feedback('Please wait', 'Mounting update medium') do
      #     local_path = HANAUpdater::System.mount_nfs(config.nfs.source, node: :local)
      #     config.nfs.mount_path = local_path
      #   end
      # end
      # copy update medium
      if config.nfs.copy_medium?
        log.warn "--- Copying contents of the update medium '#{config.nfs.source}'"\
                 " to '#{config.nfs.copy_path}' ---"
        Yast::Popup.Feedback('Please wait', 'Copying contents of the update medium') do
          HANAUpdater::System.recursive_copy(config.nfs.mount_path, config.nfs.copy_path,
            sap_sys.hana_sid, node: :local)
        end
      end
    end

    def execute_remote_update_plan(config) # rubocop:disable Metrics/MethodLength
      sap_sys = config.system
      remote_node = sap_sys.master.remote.running_on.name
      local_node = sap_sys.master.local.running_on.name
      log.warn '--- Stopping SAP HANA on local node ---'
      Yast::Popup.Feedback('Please wait', 'Stopping SAP HANA on local node') do
        HANAUpdater::Hana.stop(sap_sys.hana_sid)
      end
      log.warn '--- Registering local HANA instance for SR ---'
      Yast::Popup.Feedback('Please wait', 'Registering local HANA instance as secondary') do
        HANAUpdater::Hana.sr_register_secondary(
          sap_sys.hana_sid,
          sap_sys.hana_inst,
          sap_sys.master.local.running_on.site,
          sap_sys.master.remote.running_on.name,
          sap_sys.master.local.running_on.instance_attributes['srmode'],
          sap_sys.clone.local.running_on.instance_attributes['op_mode'],
          node: :local
        )
      end
      log.warn '--- Starting SAP HANA on local node ---'
      Yast::Popup.Feedback('Please wait', 'Starting SAP HANA on local node') do
        HANAUpdater::Hana.start(sap_sys.hana_sid)
      end
      log.warn '--- Waiting for data to be synchronized ---'
      Yast::Popup.Feedback('Please wait', 'Waiting for data to be synchronized') do
        begin
          check_system_replication(sap_sys.hana_sid, sap_sys.master.local.running_on.site,
            node: sap_sys.master.remote.running_on.name)
        rescue SystemReplicationException => e
          answer = Yast::Popup.AnyQuestion('Error while checking System Replication Status',
            e.message, 'Retry', 'Cancel', :focus_yes)
          retry if answer
        end
      end
      log.warn '--- Migrating the virtual IP ---'
      Yast::Popup.Feedback('Please wait', 'Migrating virtual IP address') do
        _out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :check,
          node: remote_node)
        log.info "--- #{self.class}.#{__callee__} : check vIP running on remote node "\
                 "#{remote_node}: rc=#{status.exitstatus}"
        if status.exitstatus == 0
          _out, status = HANAUpdater::System.resource_force(sap_sys.vip.id,
            :stop, node: remote_node)
          log.info "--- #{self.class}.#{__callee__} : stop vIP on remote node #{remote_node}:"\
                   " rc=#{status.exitstatus}"
        end
        out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :start, node: :local)
        log.info "--- #{self.class}.#{__callee__} : start vIP on local node "\
                 "#{local_node}: rc=#{status.exitstatus}, out=#{out}"
      end
      log.warn '--- System Replication: Taking over to local site ---'
      Yast::Popup.Feedback('Please wait', 'Taking over to the local site') do
        HANAUpdater::Hana.sr_takeover(sap_sys.hana_sid)
      end
      if config.nfs.should_mount?
        log.warn "--- Mounting update medium '#{config.nfs.source}' on node #{remote_node} ---"
        Yast::Popup.Feedback('Please wait', 'Mounting update medium') do
          local_path = HANAUpdater::System.mount_nfs(config.nfs.source, node: remote_node)
          config.nfs.mount_path = local_path
        end
      end
      if config.nfs.copy_medium?
        log.warn "--- Copying contents of the update medium '#{config.nfs.source}'"\
                 " to '#{config.nfs.copy_path}' on node #{remote_node}---"
        Yast::Popup.Feedback('Please wait', 'Copying contents of the update medium') do
          HANAUpdater::System.recursive_copy(config.nfs.mount_path, config.nfs.copy_path,
            sap_sys.hana_sid, node: remote_node)
        end
      end
    end

    # Restore original cluster state
    # @param config
    def restore_cluster(config) # rubocop:disable Metrics/MethodLength
      sap_sys = config.system
      remote_node = sap_sys.master.remote.running_on.name
      local_node = sap_sys.master.local.running_on.name
      log.warn "--- Stopping HANA instance on remote node #{remote_node} ---"
      Yast::Popup.Feedback('Please wait',
        "Stopping remote SAP HANA instance on node #{remote_node}") do
        HANAUpdater::Hana.stop(sap_sys.hana_sid, node: remote_node)
      end
      log.warn "--- Registering remote SAP HANA instance on remote node #{remote_node} ---"
      Yast::Popup.Feedback('Please wait',
        "Registering remote SAP HANA instance on remote node #{remote_node}") do
        HANAUpdater::Hana.sr_register_secondary(
          sap_sys.hana_sid,
          sap_sys.hana_inst,
          sap_sys.master.remote.running_on.site,
          sap_sys.master.local.running_on.name,
          sap_sys.master.local.running_on.instance_attributes['srmode'],
          sap_sys.clone.local.running_on.instance_attributes['op_mode'],
          node: remote_node
        )
      end
      log.warn "--- Starting HANA instance on remote node #{remote_node} ---"
      Yast::Popup.Feedback('Please wait',
        "Starting remote SAP HANA instance on node #{remote_node}") do
        HANAUpdater::Hana.start(sap_sys.hana_sid, node: remote_node)
      end
      log.warn '--- Waiting for data to be synchronized ---'
      Yast::Popup.Feedback('Please wait', 'Waiting for data to be synchronized') do
        begin
          check_system_replication(sap_sys.hana_sid,
            sap_sys.master.remote.running_on.site,
            node: :local)
        rescue SystemReplicationException => e
          answer = Yast::Popup.AnyQuestion('Error while checking System Replication Status',
            e.message, 'Retry', 'Cancel', :focus_yes)
          retry if answer
        end
      end
      if config.revert_sync_direction
        log.warn '--- Reverting System Replication to initial direction ---'
        log.warn '--- Migrating the virtual IP ---'
        Yast::Popup.Feedback('Please wait', 'Migrating virtual IP address') do
          _out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :check, node: :local)
          log.info "--- #{self.class}.#{__callee__} : check vIP running on local node"\
            " #{local_node}: rc=#{status.exitstatus}"
          if status.exitstatus == 0
            _out, status = HANAUpdater::System.resource_force(sap_sys.vip.id, :stop, node: :local)
            log.info "--- #{self.class}.#{__callee__} : stop vIP on local node"\
                     " #{local_node}: rc=#{status.exitstatus}"
          end
          out, status = HANAUpdater::System.resource_force(sap_sys.vip.id,
            :start, node: remote_node)
          log.info "--- #{self.class}.#{__callee__} : start vIP on remote node"\
                   " #{remote_node}: rc=#{status.exitstatus}, out=#{out}"
        end
        log.warn "--- System Replication: Taking over to remote site (node #{remote_node}) ---"
        Yast::Popup.Feedback('Please wait', 'Taking over to the remote site') do
          HANAUpdater::Hana.sr_takeover(sap_sys.hana_sid, node: remote_node)
        end
        # stop HANA on local node, so that the replication can be enabled
        log.warn '--- Stopping SAP HANA on local node ---'
        Yast::Popup.Feedback('Please wait', 'Stopping SAP HANA on local node') do
          HANAUpdater::Hana.stop(sap_sys.hana_sid, node: :local)
        end
        # register local system
        log.warn '--- Registering local HANA instance for SR ---'
        Yast::Popup.Feedback('Please wait', 'Registering local HANA instance as secondary') do
          HANAUpdater::Hana.sr_register_secondary(
            sap_sys.hana_sid,
            sap_sys.hana_inst,
            sap_sys.master.local.running_on.site,
            sap_sys.master.remote.running_on.name,
            sap_sys.master.local.running_on.instance_attributes['srmode'],
            sap_sys.clone.local.running_on.instance_attributes['op_mode'],
            node: :local
          )
        end
        # start HANA to apply SR settings
        log.warn '--- Starting SAP HANA on local node ---'
        Yast::Popup.Feedback('Please wait', 'Starting SAP HANA on local node') do
          HANAUpdater::Hana.start(sap_sys.hana_sid, node: :local)
        end
      end
      log.warn '--- Cleaning up cluster resources ---'
      Yast::Popup.Feedback('Please wait', 'Cleaning up cluster resources') do
        HANAUpdater::System.resource_cleanup(sap_sys.vip.id)
        HANAUpdater::System.resource_cleanup(sap_sys.clone.id)
        HANAUpdater::System.resource_cleanup(sap_sys.master.id)
        sleep 5
      end
      log.warn '--- Setting resources to maintenance mode ---'
      Yast::Popup.Feedback('Please wait', 'Disabling maintenance mode for cluster resources') do
        HANAUpdater::System.resource_maintenance(sap_sys.master.id, :off)
        HANAUpdater::System.resource_maintenance(sap_sys.clone.id, :off)
        HANAUpdater::System.resource_maintenance(sap_sys.vip.id, :off)
        sleep 10
      end
    end

    def check_system_replication(system_id, remote_site, opts = { node: :local })
      loop do
        rc, explanation = HANAUpdater::Hana.sr_check_status(system_id,
          remote_site, node: opts[:node])
        case rc
        when 10, 11
          log.error "--- systemReplicationStatus.py reports status #{rc} '#{explanation}'"
          raise SystemReplicationException,
            "systemReplicationStatus.py reports status #{rc} '#{explanation}'"
        when 12, 13, 14
          log.warn "--- systemReplicationStatus.py reports status #{rc} '#{explanation}'. Will wait"
          sleep 10
        when 15
          log.warn '--- systemReplicationStatus.py reports status 15 (Active)'\
                   ' (instances are in sync)'
          return true
        else
          log.error "--- Unexpected status returned from systemReplicationStatus.py: rc=#{rc}"
          raise SystemReplicationException,
            "Unexpected status returned from systemReplicationStatus.py: rc=#{rc}"
        end
      end
      true
    end
  end
end
