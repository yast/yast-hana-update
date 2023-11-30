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

Yast.import 'OSRelease'

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

    # Set resource maintenance on or off
    # @return stdout and stderr in one string, process exit status
    def resource_maintenance(resource_id, action = :on)
      raise "#{self.class}.#{__callee__}: Action #{action} is not supported" \
        unless [:on, :off].include?(action)
      cmd = 'crm', 'resource', 'maintenance', resource_id, action.to_s
      exec_get_output(*cmd)
    end

    # Set node maintenance on or off
    # @return stdout and stderr in one string, process exit status
    def node_maintenance(node_id, action = :on)
      raise "#{self.class}.#{__callee__}: Action #{action} is not supported" \
        unless [:on, :off].include?(action)
      cmd = 'crm', 'node', action == :on ? 'maintenance' : 'ready', node_id
      exec_get_output(*cmd)
    end

    def stonith_enabled(action = :on)
      raise "#{self.class}.#{__callee__}: Action #{action} is not supported" \
        unless [:on, :off].include?(action)
      cmd = 'crm', 'configure', 'property',
            action == :on ? 'stonith-enabled=true' : 'stonith-enabled=false'
      exec_get_output(*cmd)
    end

    def cluster_service(action = :stop, opts = { node: :local })
      raise "#{self.class}.#{__callee__}: Action #{action} is not supported" \
        unless [:stop, :start].include?(action)
      # Stop corosync, it will stop pacemaker, too
      # Start pacemaker, it will start corosync as a dep
      cmd = if action == :stop
              %w(systemctl stop corosync)
            else
              %w(systemctl start pacemaker)
            end
      if opts[:node] == :local
        log.debug "--- #{self.class}.#{__callee__}: executing command #{cmd} ---"
        out, status = exec_get_output(*cmd)
        log.debug "--- #{self.class}.#{__callee__}: return:"\
                  " status=#{status.exitstatus}, out=#{out} ---"
      else
        log.debug "--- #{self.class}.#{__callee__}: executing command"\
                  " #{cmd} on node #{opts[:node]} ---"
        out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node], *cmd)
        log.debug "--- #{self.class}.#{__callee__}: return: status=#{status} ---"
      end
      [out, status]
    end

    # Cleanup resource errors
    # @return stdout and stderr in one string, process exit status
    def resource_cleanup(resource_id)
      # TODO: what about the future version? (16.x)
      verb = Yast::OSRelease.ReleaseVersion.start_with?('15') ? 'refresh' : 'cleanup'
      cmd = 'crm', 'resource', verb, resource_id
      exec_get_output(*cmd)
    end

    # Execute SAPHanaSR-showAttr and parse its output
    def saphanasr_attributes(sid)
      cmd = 'SAPHanaSR-showAttr', "--sid=#{sid}", "--format=script"
      out, status = exec_get_output(*cmd)
      return nil if status.exitstatus != 0
      head    = []
      values  = {}
      lines   = []
      out.each_line do |line|
        next unless line.start_with?('Hosts')
        tmp = /Hosts\/(.*)\/(.*)="(.*)"/.match(line)
        head << tmp[2] unless head.include?(tmp[2])
        values[tmp[1]] = {} if values[tmp[1]].nil?
        values[tmp[1]][tmp[2]] = tmp[3]
      end
      lines << head
      values.each_key do |host|
        line = []
        head.each { |key| line << values[host][key] }
        lines << line
      end
      lines
    end

    # Force resource action
    # @param resource_id [String] resource ID
    # @param action [Symbol] action to force (:start, :stop, :check)
    # @param opts [Hash] `{node: :local}` or `{node: 'uname01'}`
    def resource_force(resource_id, action, opts = { node: :local })
      raise ArgumentError, "#{self.class}.#{__callee__}: Action #{action} is not supported" \
        unless [:start, :stop, :check].include?(action)
      cmd = 'crm_resource', "--force-#{action}", '--resource', resource_id
      if opts[:node] == :local
        log.debug "--- #{self.class}.#{__callee__}: executing command #{cmd} ---"
        out, status = exec_get_output(*cmd)
        log.debug "--- #{self.class}.#{__callee__}: return:"\
                  " status=#{status.exitstatus}, out=#{out} ---"
      else
        log.debug "--- #{self.class}.#{__callee__}: executing command"\
                  " #{cmd} on node #{opts[:node]} ---"
        out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node], *cmd)
        log.debug "--- #{self.class}.#{__callee__}: return: status=#{status} ---"
      end
      [out, status]
    end

    def mount_nfs(source, opts = { node: :local })
      log.debug "--- called #{self.class}.#{__callee__}(#{source}, #{opts}) ---"
      if opts[:node] == :local
        local = Dir.mktmpdir('hana')
        log.debug "--- #{self.class}.#{__callee__}: created tmp directory #{local}"
      else
        tmp_cmd = 'mktemp', '-d'
        log.debug "--- #{self.class}.#{__callee__}: executing command"\
                  " #{tmp_cmd} on node #{opts[:node]} ---"
        out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node], *tmp_cmd)
        unless status.exitstatus == 0
          log.error 'Could not create a temporary directory for the NFS mount'
          log.error "returned status=#{status}, out=#{out}"
          raise HANAUpdater::Exceptions::NFSMountException, "Could not create a temporary "\
            "directory for the NFS mount. Subprocess exit status "\
            "#{status.exitstatus}, output=#{out}"
        end
        local = out.strip
      end
      log.debug "--- #{self.class}.#{__callee__}: created a temporary directory #{local} ---"
      cmd = 'mount', source, local
      if opts[:node] == :local
        out, status = exec_get_output(*cmd)
        log.debug "--- #{self.class}.#{__callee__}: mount retuned with #{out}, #{status} ---"
        unless status.exitstatus == 0
          log.error "--- #{self.class}.#{__callee__}: Could not mount the NFS share on the"\
            " local node: returned status=#{status.exitstatus}, out=#{out}"
          Dir.rmdir(local)
          log.debug "--- #{self.class}.#{__callee__}: removed tmp directory #{local}"
          raise HANAUpdater::Exceptions::NFSMountException, "Could not mount NFS share #{source}"\
            " on the local node. Subprocess status #{status.exitstatus}, output: #{out}"
        end
      else
        out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node], *cmd)
        unless status.exitstatus == 0
          log.error "--- #{self.class}.#{__callee__}: Could not mount the NFS share on "\
            "node #{opts[:node]}: returned status=#{status.exitstatus}, out=#{out}"
          cmd = 'rmdir', local
          out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node], *cmd)
          log.debug "--- #{self.class}.#{__callee__}: remove remote tmp directory #{local}"\
            " on node #{opts[:node]}: status #{status.exitstatus}"
          raise HANAUpdater::Exceptions::NFSMountException, "Could not mount NFS share #{source}"\
            " on node #{opts[:node]}. Subprocess exit status #{status.exitstatus}, output: #{out}"
        end
      end
      local
    end

    def unmount_nfs(path)
      log.debug "--- called #{self.class}.#{__callee__}(#{path}) ---"
      cmd = 'umount', path
      out, status = exec_get_output(*cmd)
      log.debug "--- #{self.class}.#{__callee__}: umount retuned with #{out}, #{status} ---"
      status.exitstatus == 0
    end

    def recursive_copy(source, target, hana_sid, opts = { node: :local })
      log.debug "--- called #{self.class}.#{__callee__}(#{source}, #{target}, #{opts}) ---"
      source_ = File.join(source, '.')
      if opts[:node] == :local
        FileUtils.mkdir_p(target) unless Dir.exist?(target)
        # FileUtils.cp_r(source_, target) :: takes way too long, make a system call instead
        out, status = HANAUpdater::System.exec_get_output('cp', '-far', source_, target)
        unless status.exitstatus == 0
          log.error "Cannot copy update medium: status=#{status}, out=#{out}"
          return false
        end
        out, status = HANAUpdater::System.exec_get_output('chown', '-R',
          "#{hana_sid.downcase}adm:sapsys", target)
        unless status.exitstatus == 0
          log.error "Cannot chown copied update medium: status=#{status}, out=#{out}"
          return false
        end
        return true
      else
        status = HANAUpdater::SSH.rexec_wait(opts[:node], 'test', '-d', target)
        unless status.exitstatus == 0
          log.warn "--- #{self.class}.#{__callee__}: target directory "\
                   "#{target} does not exist on node #{opts[:node]} ---"
          out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node], 'mkdir', '-p', target)
          unless status.exitstatus == 0
            log.error "Cannot create target directory #{target} on node"\
                      " #{opts[:node]}: status=#{status}, out=#{out}"
            return false
          end
        end
        out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node], 'cp',
          '-far', source_, target)
        unless status.exitstatus == 0
          log.error "Cannot copy update medium #{source_} to #{target}: #{status}, #{out}"
          return false
        end
        out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node], 'chown', '-R',
          "#{hana_sid.downcase}adm:sapsys", target)
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
