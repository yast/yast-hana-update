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
# Summary: SAP HANA updater in a SUSE cluster: Remote SSH invocation
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'fileutils'
require 'tmpdir'
require 'hana_update/helpers'
require 'hana_update/exceptions'
require 'hana_update/ssh'
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
      cmd = 'crm',  'resource', 'maintenance', resource_id, action.to_s
      out, status = exec_outerr_status(*cmd)
    end

    # Force resource action
    # @param resource_id [String] resource ID
    # @param action [Symbol] action to force (:start, :stop, :check)
    # @param opts [Hash] {node: :local} or {node: 'uname01'}
    def resource_force(resource_id, action, opts={node: :local})
      cmd = '/usr/sbin/crm_resource', "--force-#{action.to_s}", '--resource', resource_id
      if opts[:node] == :local
        log.debug "--- #{self.class}.#{__callee__}: executing command #{cmd} ---"
        out, status = exec_outerr_status(*cmd)
        log.debug "--- #{self.class}.#{__callee__}: return: status=#{status.exitstatus}, out=#{out} ---"
      else
        log.debug "--- #{self.class}.#{__callee__}: executing command #{cmd} on node #{opts[:node]} ---"
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *cmd)
        log.debug "--- #{self.class}.#{__callee__}: return: status=#{status} ---"
      end
      return out, status
    end

    def mount_nfs(source, opts={node: :local})
      log.debug "--- called #{self.class}.#{__callee__}(#{source}, #{opts}) ---"
      if opts[:node] == :local
        local = Dir.mktmpdir('hana')
      else
        tmp_cmd = 'mktemp', '-d'
        log.debug "--- #{self.class}.#{__callee__}: executing command #{tmp_cmd} on node #{opts[:node]} ---"
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *tmp_cmd)
        unless status.exitstatus == 0
          log.error "Could not create a temporary directory for the NFS mount"
          log.error "returned status=#{status}, out=#{out}"
          return
        end
        local = out.strip
      end
      log.debug "--- #{self.class}.#{__callee__}: created a temporary directory #{local} ---"
      cmd = 'mount', source, local
      if opts[:node] == :local
        out, status = exec_outerr_status(*cmd)
        log.debug "--- #{self.class}.#{__callee__}: mount retuned with #{out}, #{status} ---"
      else
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *cmd)
        unless status.exitstatus == 0
          log.error "Could not mount the NFS share on node #{opts[:node]}"
          log.error "returned status=#{status}, out=#{out}"
          return
        end
      end
      local
    end

    def recursive_copy(source, target, hana_sid, opts={node: :local})
      log.debug "--- called #{self.class}.#{__callee__}(#{source}, #{target}, #{opts}) ---"
      source_ = File.join(source, '.')
      if opts[:node] == :local
        FileUtils.mkdir_p(target) unless Dir.exists?(target)
        # FileUtils.cp_r(source_, target) :: takes way too long, make a system call instead
        out, status = HANAUpdater::System.exec_outerr_status('cp', '-far', source_, target)
        unless status.exitstatus == 0
          log.error "Cannot copy update medium: status=#{status}, out=#{out}"
          return false
        end
        out, status = HANAUpdater::System.exec_outerr_status('chown', '-R', "#{hana_sid.downcase}adm:sapsys", target)
        unless status.exitstatus == 0
          log.error "Cannot chown copied update medium: status=#{status}, out=#{out}"
          return false
        end
        return true
      else
        status = HANAUpdater::SSH.run_command_wait(opts[:node], 'test', '-d', target)
        unless status.exitstatus == 0
          log.warn "--- #{self.class}.#{__callee__}: target directory #{target} does not exist on node #{opts[:node]} ---"
          out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], 'mkdir', '-p', target)
          unless status.exitstatus == 0
            log.error "Cannot create target directory #{target} on node #{opts[:node]}: status=#{status}, out=#{out}" 
            return false
          end
        end
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], 'cp', '-far', source_, target)
        unless status.exitstatus == 0
          log.error "Cannot copy update medium #{source_} to #{target}: #{status}, #{out}"
          return false
        end
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], 'chown', '-R', "#{hana_sid.downcase}adm:sapsys", target)
        unless status.exitstatus == 0
          log.error "Cannot chown copied update medium: status=#{status}, out=#{out}"
          return false
        end
      end
      true
    end
  end

  System = SystemClass.instance
end
