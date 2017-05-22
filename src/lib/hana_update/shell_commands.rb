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
# Summary: SUSE HANA Updater: shell commands wrapper
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
    def exec_status(*command)
      log.info "Executing command #{command}"
      Open3.popen3(*command) { |_, _, _, wait_thr| wait_thr.value }
    end

    # # Execute command and return its status and output (stdout)
    # # @return [[Process::Status, String]]
    # def exec_output_status(*command)
    #   log.info "Executing command #{command}"
    #   Open3.capture2(*command)
    # end

    # Execute command and return ist output (both stdout and stderr) and status
    # @return [[String, string]] stdout_and_stderr, status
    def exec_outerr_status(*params)
      log.info "Executing command #{params}"
      Open3.capture2e(*params)
    rescue SystemCallError => e
      return ["System call failed with ERRNO=#{e.errno}: #{e.message}", FakeProcessStatus.new(1)]
    end

  #   def exec_outerr_status_stdin(*params, stdin_data)
  #     log.info "Executing command #{params}"
  #     Open3.capture2e(*params, stdin_data: stdin_data)
  #   rescue SystemCallError => e
  #     return ["System call failed with ERRNO=#{e.errno}: #{e.message}", FakeProcessStatus.new(1)]
  #   end

  #   # Pipe the commands and return the common status
  #   # @return [Boolean] success
  #   def pipe(*commands)
  #     log.info "Executing commands #{commands}"
  #     stats = Open3.pipeline(*commands)
  #     stats.all? { |s| s.exitstatus == 0 }
  #   end

    # Execute command as user _user_name_ and return its output (stdout & stderr) and status
    # @return [[String, String]] [stdout_and_stderr, status]
    def su_exec_outerr_status(user_name, *params)
      log.info "Executing #{params} as user #{user_name}"
      Open3.capture2e('su', '-lc', params.join(' '), user_name)
    rescue SystemCallError => e
      return ["System call failed with ERRNO=#{e.errno}: #{e.message}", FakeProcessStatus.new(1)]
    end

  #   # Execute command as user _user_name_ and return its output and status
  #   # Do not log the command
  #   # @return [[String, String]] [stdout_and_stderr, status]
  #   def su_exec_outerr_status_no_echo(user_name, *params)
  #     Open3.capture2e('su', '-lc', params.join(' '), user_name)
  #   rescue SystemCallError => e
  #     return ["System call failed with ERRNO=#{e.errno}: #{e.message}", FakeProcessStatus.new(1)]
  #   end

  #   def pipeline(cmd1, cmd2)
  #     Open3.pipeline_r(cmd1, cmd2, {err: "/dev/null"}) { |out, wait_thr| out.read }
  #   end
  end
end
