# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE Linux GmbH, Nuernberg, Germany.
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
      @nfs_share = {}
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

    def hana_sys_table_items
      l = HANAUpdater::Cluster.groups.map do |g|
        # sort nodes by RA role alphabetically, i.e., Master, Slave, Stopped
        node_list = g.master.primitives.map { |e| [e.running_on.name, e.mon_attr['role']] }
        node_list = node_list.sort_by { |e| e[1] }.map { |e| e[0] }
        [g.hana_sid, g.hana_inst, node_list.join(', ')]
      end
      HANAUpdater::Helpers.itemize_list(l)
    end

    def select_hana_system(sid, ino)
      log.error "--- #{self.class}.#{__callee__}(sid=#{sid}, ino=#{ino}) --- "
      @system = HANAUpdater::Cluster.get_system(sid, ino)
    end

    def validate_share(verbosity)
      # TODO: implement
    end

    def validate_system
      errors = []
      errors << "This wizard has to be run on the secondary HANA node" unless @system.master.local.mon_attr['role'] == 'Slave'
      errors
    end
  end
end
