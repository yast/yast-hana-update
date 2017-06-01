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
# Summary: SUSE High Availability Setup for SAP Products: Remote SSH invocation
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'fileutils'
require 'tmpdir'
require 'hana_update/helpers'
require 'hana_update/exceptions'
# require 'hana_update/node_logger'
require_relative 'shell_commands.rb'

module HANAUpdater
  # Remote SSH invocation
  class SystemClass
    include Singleton
    include ShellCommands
    include Yast::Logger
    # include SapHA::Exceptions

    def initialize
      log.debug "--- #{self.class}.#{__callee__} --- "
    end

    def resource_maintenance(resource_id, action=:on)
      cmd = ['crm',  'resource', 'maintenance', resource_id, action.to_s]
      out, status = exec_outerr_status(*cmd)
    end

    def mount_nfs(source)
      local = Dir.mktmpdir('hana')
      cmd = ['mount', source, local]
      out, status = exec_outerr_status(*cmd)
      local
    end
  end

  System = SystemClass.instance
end
