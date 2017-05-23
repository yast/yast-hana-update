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
require 'hana_update/cluster3'

module HANAUpdater
  # Base class for component configuration
  class Configuration
    include Yast::Logger
    # include SapHA::Exceptions
    attr_reader   :no_validators, :selected_system
    attr_accessor :nfs_share, :hana_instance, :hana_system

    def initialize
      @no_validators = false
      @nfs_share = nil
      @hana_system_list = []
      @selected_system = nil
    end

    def debug=(value)
      @no_validators = value
    end

    def hana_sys_table_items      
      lst = HANAUpdater::Cluster.resources.map do |r|
        node = r.running_on
        if node.nil?
          ['<stopped>', r.hana_sid, r.hana_ino, 'N/A', 'N/A', r.role]
        else
          [node.to_s, r.hana_sid, r.hana_ino, node.attributes['site'],
              node.attributes['version'] || 'N/A', r.role]
        end
      end
      @hana_system_list = lst
      HANAUpdater::Helpers.itemize_list(lst)
    end

    def select_hana_system(id)
      log.debug "--- #{self.class}.#{__callee__}(id=#{id.inspect}) --- "
      @selected_system = HANAUpdater::Cluster.resources[id].hana_sid
    end

    # def get_resource(role)
    #   HANAUpdater::Cluster.resources.find {|r| r.hana_sid == @selected_system && r.role == role}
    # end
    def get_resource(role)
      if role == :local
        HANAUpdater::Cluster.resources.find {|r| r.hana_sid == @selected_system && r.running_on.localhost? }
      else
        HANAUpdater::Cluster.resources.find {|r| r.hana_sid == @selected_system && !r.running_on.localhost? }
      end
    end

    def validate_share(verbosity)

    end

  end
end
