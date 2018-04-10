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
# Summary: SAP HANA updater in a SUSE cluster: Base configuration class
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'hana_update/node_logger'
require 'hana_update/helpers'
require 'hana_update/cluster'
require 'hana_update/ssh'
require 'hana_update/system'
require 'hana_update/exceptions'

module HANAUpdater
  # Class holding settings for the NFS share
  class NFSSettings
    attr_writer :should_mount, :copy_medium
    attr_accessor :source, :copy_path, :mount_path

    def initialize
      @should_mount = false
      @source = ''
      @copy_medium = false
      @copy_path = ''
      @mount_path = ''
    end

    def should_mount?
      @should_mount
    end

    def copy_medium?
      @copy_medium
    end

    def validate(mode)
      return (mode == :verbose) ? [] : true unless @should_mount
      errors = []
      errors << 'NFS share path cannot be empty' if @source.empty?
      errors << 'Copy path cannot be empty' if @copy_path.empty? && @copy_medium
      if @source.start_with? 'nfs:'
        errors << 'NFS URLs are not supported. Please use the following format instead:'\
                  ' "servername:/path/to/share".'
      elsif !@source.include?(':')
        errors << 'Please use the following path format: "servername:/path/to/share".'
      end
      if errors.empty?
        begin
          mount_path = HANAUpdater::System.mount_nfs(@source, node: :local)
        rescue HANAUpdater::Exceptions::NFSMountException => e
          errors << e.message
        else
          HANAUpdater::System.unmount_nfs(mount_path)
        end
      end
      if mode == :verbose
        errors
      else
        !errors.empty?
      end
    end
  end

  # Base class for component configuration
  class Configuration
    include Yast::Logger
    attr_reader :no_validators, :system
    attr_accessor :nfs_share, :hana_instance, :hana_system, :revert_sync_direction,
                  :update_secondary
    attr_reader :nfs

    def initialize
      @no_validators = false
      @nfs = NFSSettings.new
      @hana_system_list = []
      @system = nil
      @revert_sync_direction = false # revert synchronization direction to the initial state
      @update_secondary = false
    end

    def debug=(value)
      @no_validators = value
    end

    def validate(component, mode)
      log.debug "-- #{self.class}.#{__callee__}(#{component}, #{mode})"
      case component
      when :nfs_share
        log.debug "-- #{self.class}.#{__callee__}: #{@nfs.inspect}"
        return @nfs.validate(mode)
      else
        log.error "Unknown component to validate: #{component.inspect}"
      end
    end

    def hana_sids
      l = HANAUpdater::Cluster.groups.map do |g|
        [g.hana_sid, "System #{g.hana_sid}, Instance #{g.hana_inst}"]
      end
      HANAUpdater::Helpers.itemize_list(l, false)
    end

    def get_system_by_sid(sid)
      HANAUpdater::Cluster.groups.find { |g| g.hana_sid == sid }
    end

    def hana_sys_table_items(group)
      return if group.nil?
      l = group.master.primitives.map do |prim|
        if prim.running_on.nil?
          host_name = '<not running>'
          site_name = '<N/A>'
          version = '<N/A>'
        else
          host_name = prim.running_on.name
          host_name += ' (this host)' if prim.running_on.localhost?
          site_name = prim.running_on.instance_attributes['site']
          node = prim.running_on.localhost? ? :local : host_name
          version = prim.running_on.transient_attributes['version'] ||
            HANAUpdater::Hana.version(group.hana_sid, node: node)
        end
        rsc_role = prim.role
        rsc_role += ' (unmanaged)' unless prim.managed?
        [host_name, site_name, version, rsc_role]
      end
      HANAUpdater::Helpers.itemize_list(l)
    end

    def hana_update_overview
      instances = []
      @system.master.primitives.each do |prim|
        ins = {}
        if prim.running_on.nil?
          ins[:host] = '<not running>'
          ins[:site] = '<N/A>'
          ins[:version_before] = '<N/A>'
          ins[:version_after] = '<N/A>'
        else
          ins[:host] = prim.running_on.name
          ins[:site] = prim.running_on.instance_attributes['site']
          ins[:version_before] = prim.running_on.transient_attributes['version']
          ins[:version_after] = if prim.running_on.localhost?
                                  HANAUpdater::Hana.version(@system.hana_sid)
                                else
                                  HANAUpdater::Hana.version(@system.hana_sid, node: ins[:host])
                                end
        end
        instances << ins
      end
      instances
    end

    def select_hana_system(sid)
      log.debug "--- #{self.class}.#{__callee__}(sid=#{sid.inspect}) --- "
      @system = get_system_by_sid(sid)
    end

    def validate_system
      log.debug "--- #{self.class}.#{__callee__} : system is #{@system.inspect} ---"
      errors = []
      if @system.nil?
        errors << 'Please select at least one SAP HANA system'
        return errors
      end
      if !@system.all_managed?
        errors << 'Some resources belonging to the SAP HANA SR group are not managed'
        errors << 'This wizard can only handle active (i.e., running and managed)'\
                  ' SAP HANA instances'
      elsif !@system.all_running?
        errors << 'Some resources belonging to the SAP HANA SR group are not started'
        errors << 'This wizard can only handle active (i.e., running and managed)'\
                  ' SAP HANA instances'
      elsif @system.master.local.role != 'Slave'
        errors << 'This wizard has to be run on the secondary SAP HANA node'
      end
      return errors if !errors.empty?
      # check connection to the remote node
      remote_node = @system.master.remote.running_on.name
      remote_accessible = false
      begin
        HANAUpdater::SSH.check_ssh(remote_node)
        remote_accessible = true
      rescue HANAUpdater::Exceptions::SSHException => e
        errors << "Could not connect to the remote node: #{e}"
      end
      # validate the SRTAKEOVER userstore key
      if !HANAUpdater::Hana.check_secure_store(@system.hana_sid)
        errors << "User store key 'SRTAKEOVER' was not found on the local node."
      end
      if remote_accessible && !HANAUpdater::Hana.check_secure_store(@system.hana_sid,
        node: remote_node, key: 'SRTAKEOVER')
        errors << "User store key 'SRTAKEOVER' was not found on the remote node."
      end
      errors
    end

    def execute_update_plan(part, ui_callback)
      if part == :local
        execute_local_update_plan(ui_callback)
      elsif part == :remote
        execute_remote_update_plan(ui_callback)
      else
        raise ArgumentError, "Unknown part #{part.inspect}"
      end
    end
  end
end
