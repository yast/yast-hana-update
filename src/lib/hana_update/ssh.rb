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
require_relative 'shell_commands.rb'

module HANAUpdater
  # Remote SSH invocation
  class SSHClass
    include Singleton
    include ShellCommands
    include Exceptions
    include Yast::Logger
    # include SapHA::Exceptions

    def initialize
      log.debug "--- #{self.class}.#{__callee__} --- "
      @script_path = Helpers.data_file_path('check_ssh.expect')
    end

    # Check if we can initiate an SSH connection to the host without a password
    def check_ssh(host)
      log.info "--- #{self.class}.#{__callee__} --- "
      stat = exec_get_status('/usr/bin/expect', '-f', @script_path, 'check', host)
      check_status(stat, host)
    end

    # Check if we can initiate an SSH connection to the host using the specified password
    def check_ssh_password(host, password)
      log.info "--- #{self.class}.#{__callee__} --- "
      stat = exec_get_status('/usr/bin/expect', '-f', @script_path, 'check', host, password)
      check_status(stat, host)
    end

    def rexec(host, *cmd)
      log.info "--- called #{self.class}.#{__callee__}(#{host}, #{cmd}) ---"
      exec_get_status('ssh', '-o', 'StrictHostKeyChecking=no', '-f', "root@#{host}", *cmd)
    end

    def rexec_get_output(host, *cmd)
      log.info "--- called #{self.class}.#{__callee__}(#{host}, #{cmd}) ---"
      exec_get_output('ssh', '-o', 'StrictHostKeyChecking=no', '-f', "root@#{host}", *cmd)
    end

    # Execute command on the host remotely via SSH
    # Wait for the process to finish, return exit status
    def rexec_wait(host, *cmd)
      log.info "--- called #{self.class}.#{__callee__}(#{host}, #{cmd}) ---"
      ret = exec_get_status('ssh', '-o', 'StrictHostKeyChecking=no', "root@#{host}", *cmd)
      log.debug "--- #{self.class}.#{__callee__}: #{host} returned #{ret} ---"
      ret
    end

    # Execute command on the host remotely via SSH
    # Wait for the process to finish, return its stderr & stdout and the exit status
    def rexec_wait_get_output(host, *cmd)
      log.info "--- called #{self.class}.#{__callee__}(#{host}, #{cmd}) ---"
      out, ret = exec_get_output('ssh', '-o', 'StrictHostKeyChecking=no', "root@#{host}", *cmd)
      log.debug "--- #{self.class}.#{__callee__}: #{host} returned #{ret}, #{out} ---"
      [out, ret]
    end

    # Copy file from this host to the same path at the target host
    def copy_file_to(file_path, host, password = '')
      stat = exec_get_status("/usr/bin/expect", "-f", @script_path,
        "copy-file", host, password, file_path)
      check_status(stat, host)
    end

    private

    # Check the status and react accordingly
    def check_status(stat, host)
      case stat.exitstatus
      when 0
        return true
      when 5 # timeout
        raise SSHException, "Could not connect to #{host}: Connection time out"
      when 10
        raise SSHAuthException, "Could not execute a command on the remote node #{host}:"\
                                " Password is required"
      when 11
        raise SSHPassException, "Could not execute a command on the remote node #{host}:"\
                                " Password is incorrect"
      when 51
        raise SSHException, "Could not connect to #{host}: Remote host reset the connection"
      when 52
        raise SSHException, "Could not connect to #{host}: Cannot resolve the host"
      when 53
        raise SSHException, "Could not connect to #{host}: No route to host"
      when 54
        raise SSHException, "Could not connect to #{host}: Connection refused"
      when 55
        raise SSHException, "Could not connect to #{host}: Unknown connection error."
      else
        log.error "Could not connect to #{host}: check_ssh returned rc=#{stat.exitstatus}"
        raise SSHException, "Could not connect to #{host} (rc=#{stat.exitstatus})."
      end
    end
  end

  SSH = SSHClass.instance
end
