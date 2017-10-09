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
# Summary: SAP HANA updater in a SUSE cluster: shell commands wrapper
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'open3'
require 'timeout'

module HANAUpdater
  # HANA configuration routines
  module ShellCommands
    include Yast::Logger

    # Fake process status for testing purposes
    class FakeProcessStatus
      attr_reader :exitstatus
      def initialize(rc)
        @exitstatus = rc
      end
    end

    # Execute command and return its status
    # @return [Process::Status]
    def exec_get_status(*command)
      log.debug "--- called #{self.class}.#{__callee__}(#{command}) ---"
      log.info "Executing command #{command}"
      status = Open3.popen3(*command) { |_, _, _, wait_thr| wait_thr.value }
      log.debug "--- called #{self.class}.#{__callee__}: command returned '#{status}' ---"
      status
    end

    # Execute command and return ist output (both stdout and stderr) and status
    # @return [[String, string]] stdout_and_stderr, status
    def exec_get_output(*params)
      log.debug "--- called #{self.class}.#{__callee__}(#{params}) ---"
      log.info "Executing command #{params}"
      out, status = Open3.capture2e(*params)
      out.split("\n").each { |ln| log.debug "--- OUT: #{ln}"}
      log.debug "--- called #{self.class}.#{__callee__}: command returned '#{status}' ---"
      return out, status
    rescue SystemCallError => e
      return ["System call failed with ERRNO=#{e.errno}: #{e.message}", FakeProcessStatus.new(1)]
    end


    # Execute command as user _user_name_ and return its output (stdout & stderr) and status
    # @return [[String, String]] [stdout_and_stderr, status]
    def su_exec_get_output(user_name, *params)
      log.info "Executing #{params} as user #{user_name}"
      out, status = Open3.capture2e('su', '-lc', params.join(' '), user_name)
      out.split("\n").each { |ln| log.debug "--- OUT: #{ln}"}
      log.debug "--- called #{self.class}.#{__callee__}: command returned '#{status}' ---"
      return out, status
    rescue SystemCallError => e
      return ["System call failed with ERRNO=#{e.errno}: #{e.message}", FakeProcessStatus.new(1)]
    end

    # Execute command as user _user_name_ and return its output and status
    # Do not log the command
    # @return [[String, String]] [stdout_and_stderr, status]
    def su_exec_get_output_no_echo(user_name, *params)
      Open3.capture2e('su', '-lc', params.join(' '), user_name)
    rescue SystemCallError => e
      return ["System call failed with ERRNO=#{e.errno}: #{e.message}", FakeProcessStatus.new(1)]
    end
  end
end
