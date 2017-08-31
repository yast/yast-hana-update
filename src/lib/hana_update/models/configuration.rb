# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE Linux GmbH, Nuernberg, Germany.
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
# Summary: SUSE High Availability Setup for SAP Products: Base configuration class
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
# require 'sap_ha/exceptions'
# require 'sap_ha/semantic_checks'
require 'hana_update/node_logger'
require 'hana_update/helpers'
require 'hana_update/cluster'

module HANAUpdater
  # Base class for component configuration
  class Configuration
    include Yast::Logger
    attr_reader   :no_validators, :system
    attr_accessor :nfs_share, :hana_instance, :hana_system

    def initialize
      @no_validators = false
      @nfs_share = {mount: false, source: '', copy_medium: false, nfs_copy_path: ''}
      @hana_system_list = []
      @system = nil
    end

    def debug=(value)
      @no_validators = value
    end

    def nfs_source=(value)
      @nfs_share[:source] = value
    end

    def nfs_source
      @nfs_share[:source]
    end

    def mount_nfs=(value)
      @nfs_share[:mount] = value
    end

    def mount_nfs
      @nfs_share[:mount]
    end

    def copy_medium
      @nfs_share[:copy_medium]
    end

    def copy_medium=(value)
      @nfs_share[:copy_medium] = value
    end

    def nfs_copy_path=(value)
      @nfs_share[:nfs_copy_path] = value
    end

    def nfs_copy_path
      @nfs_share[:nfs_copy_path]
    end

    def validate(component, mode)
      case component
      when :nfs_share
        true
      end
    end

    def hana_sids
      # HANAUpdater::Cluster.groups.map {|g| "System #{g.hana_sid}, Instance #{g.hana_inst}" }
      l = HANAUpdater::Cluster.groups.map {|g| [g.hana_sid, "System #{g.hana_sid}, Instance #{g.hana_inst}"] }
      HANAUpdater::Helpers.itemize_list(l, false)
    end

    def get_system_by_sid(sid)
      HANAUpdater::Cluster.groups.find {|g| g.hana_sid == sid}
    end

    def hana_sys_table_items(group)
      l = group.master.primitives.map do |prim|
        if prim.running_on.nil?
          host_name = '<not running>'
          site_name = '<N/A>'
          version = '<N/A>'
          rsc_role = prim.role
          rsc_role += ' (unmanaged)' if prim.managed?
        else
          host_name = prim.running_on.name
          host_name += ' (this host)' if prim.running_on.localhost?
          site_name = prim.running_on.instance_attributes['site']
          version = prim.running_on.transient_attributes['version'] # TODO: fetch it if not available in the cluster
          rsc_role = prim.role
          rsc_role += ' (unmanaged)' if prim.managed?
        end
        [host_name, site_name, version, rsc_role]
      end
      HANAUpdater::Helpers.itemize_list(l)
    end

    def select_hana_system(sid)
      log.debug "--- #{self.class}.#{__callee__}(sid=#{sid.inspect}) --- "
      @system = get_system_by_sid(sid)
    end

    def validate_share(verbosity)
      # TODO: implement
    end

    def validate_system
      errors = []
      if @system.master.local.nil?
        errors << "This wizard can only handle active (i.e., running and managed) SAP HANA instances"
      elsif @system.master.local.role != 'Slave'
        errors << "This wizard has to be run on the secondary SAP HANA node"
      elsif !@system.all_managed?
        errors << "Some resources belonging to the SAP HANA SR group are not managed"
        errors << "This wizard can only handle active (i.e., running and managed) SAP HANA instances"
      end
      errors
    end
  end
end
