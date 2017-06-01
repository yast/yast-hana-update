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
  class SSHClass
    include Singleton
    include ShellCommands
    include Yast::Logger
    # include SapHA::Exceptions

    def initialize
      log.debug "--- #{self.class}.#{__callee__} --- "
      @script_path = Helpers.data_file_path('check_ssh.expect')
      @ssh_user_dir = File.join(Dir.home, '.ssh')
      #reinit_identities
      #create_user_identities unless check_user_identities
      #authorize_own_keys
    end

    def reinit_identities
      @user_identities = Dir.glob(File.join(@ssh_user_dir, "id_{rsa,dsa,ecdsa,ed25519}"))
      @user_pubkeys = Dir.glob(File.join(@ssh_user_dir, "id_{rsa,dsa,ecdsa,ed25519}.pub"))
    end

    # Check if we can initiate an SSH connection to the host without a password
    def check_ssh(host)
      log.info "--- #{self.class}.#{__callee__} --- "
      stat = exec_status("/usr/bin/expect", "-f", @script_path, "check", host)
      check_status(stat, host)
    end

    # Check if we can initiate an SSH connection to the host using the specified password
    def check_ssh_password(host, password)
      log.info "--- #{self.class}.#{__callee__} --- "
      stat = exec_status("/usr/bin/expect", "-f", @script_path, "check", host, password)
      check_status(stat, host)
    end

    # Copy SSH keys from the host
    def copy_keys_from_(host, password, path)
      stat = exec_status("/usr/bin/expect", "-f", @script_path,
        "copy", host, password, path.to_s)
      check_status(stat, host)
    end

    def check_user_identities
      !@user_identities.empty? && @user_identities.all? { |p| File.readable? p }
    end

    # Creates user keys locally
    def create_user_identities(overwrite = false)
      if overwrite
        ::FileUtils.rm @user_identities
        ::FileUtils.rm @user_pubkeys
      end
      rc = exec_status("/usr/bin/ssh-keygen", "-f", File.join(@ssh_user_dir, "id_rsa"), "-P", "")
      unless rc.exitstatus == 0
        log.error "Calling ssh-keygen failed: exit code #{rc}"
        raise SSHException, "Could not create user identities"
      end
      reinit_identities
    end

    # Copy own SSH identities to the specified host using the password
    def copy_keys_to(host, password)
      result = true
      stat = exec_status("/usr/bin/expect", "-f", @script_path, "copy-id", host, password)
      check_status(stat, host)
      ssh_dir = File.join(Dir.home, '.ssh')
      @user_identities.each do |key|
        out, stat = exec_outerr_status('scp', key, "#{host}:#{key}")
        if stat.exitstatus == 0
          log.info "Copied SSH key #{key} to host #{host}."
        else
          log.error "Could not copy SSH key #{key} to host #{host}: #{out}."
          result = false
        end
      end
      @user_pubkeys.each do |key|
        out, stat = exec_outerr_status('scp', key, "#{host}:#{key}")
        if stat.exitstatus == 0
          log.info "Copied SSH public key #{key} to host #{host}."
        else
          log.error "Could not copy public SSH key #{key} to host #{host}: #{out}."
          result = false
        end
      end
      ak = File.join(ssh_dir, 'authorized_keys')
      out, stat = exec_outerr_status('scp', ak, "#{host}:#{ak}")
      if stat.exitstatus == 0
        log.info "Copied 'authorized_keys' to host #{host}."
      else
        log.error "Could not copy 'authorized_keys' to host #{host}: #{out}."
        result = false
      end
      stat = exec_status("/usr/bin/expect", "-f", @script_path,
                         "authorize", host, password)
      NodeLogger.log_status(result, "Copied SSH keys to node #{host}",
        "Could not copy SSH keys to node #{host}")
    end

    # Copy SSH keys from the host to the local machine
    # @param password [String] SSH password or "''" for an empty string
    def copy_keys_from(host, overwrite = false, password = "")
      # Create the .shh directory
      log.info "SSH::copy_keys(#{host}, overwrite=#{overwrite})"
      begin
        ssh_dir = File.join(Dir.home, '.ssh')
        Dir.mkdir(ssh_dir, 0700)
      rescue Errno::EEXIST
        log.debug "#{ssh_dir} already exists"
      end
      # Create a temporary directory for the keys
      tmpdir = Dir.mktmpdir('sap-ha-keys-')
      log.debug "Created tmp directory #{tmpdir}"
      log.info "Retrieving SSH keys from node #{host}"
      begin
        copy_keys_from_(host, password, tmpdir)
      rescue SSHException => e
        log.error e.to_s
        ::FileUtils.rm_rf tmpdir
        raise e
      end
      keys_copied = 0
      Dir.glob(File.join(tmpdir, "id_{rsa,dsa,ecdsa,ed25519}")) do |source_path|
        basename = File.basename(source_path)
        log.info "Copied key #{basename}"
        target_path = File.join(ssh_dir, basename)
        if File.exist?(target_path) && !overwrite
          log.info "Key #{basename} was skipped, as #{target_path} already exists."
          next
        end
        ::FileUtils.mv source_path, target_path
        keys_copied += 1
        source_pub_key = source_path + '.pub'
        target_pub_key = target_path + '.pub'
        if File.exist? source_pub_key
          ::FileUtils.mv source_pub_key, target_pub_key, force: true
          authorize_key target_pub_key
        else
          log.err "Public key #{source_pub_key} wasn't found."
        end
      end
      log.info "Copied #{keys_copied} keys."
      ::FileUtils.rm_rf tmpdir
      # make sure the target host has its own keys in authorized_keys
      stat = exec_status("/usr/bin/expect", "-f", @script_path, "authorize", host, password)
      if stat.exitstatus != 0
        log.error "Executing ha-cluster-init ssh_remote on host #{host} failed"
      end
    end

    def run_rpc_server(host)
      stat = exec_status("ssh", "-o", "StrictHostKeyChecking=no", "-f", "root@#{host}",
        SapHA::Helpers.rpc_server_cmd)
      check_status(stat, host)
    end

    def run_command(host, *cmd)
      exec_status("ssh", "-o", "StrictHostKeyChecking=no", "-f", "root@#{host}", *cmd)
    end

    def run_command2(host, *cmd)
      exec_outerr_status("ssh", "-o", "StrictHostKeyChecking=no", "-f", "root@#{host}", *cmd)
    end
    
    private

    def authorize_own_keys
      @user_pubkeys.each { |p| authorize_key p }
    end

    def authorize_key(path)
      auth_keys_path = File.join(@ssh_user_dir, 'authorized_keys')
      if exec_status("grep", "-q", "-s", path, auth_keys_path.to_s).exitstatus != 0
        log.info "Adding key #{path} to #{auth_keys_path}"
        key = File.read(path)
        File.open(auth_keys_path, mode: 'a') do |fh|
          fh << "\n"
          fh << key
        end
      end
      true
    end

    # Check the status and react accordingly
    def check_status(stat, host)
      case stat.exitstatus
      when 0
        return true
      when 5 # timeout
        raise SSHException, "Could not connect to #{host}: Connection time out"
      when 10
        raise SSHAuthException, "Could not execute a remote command on #{host}: Password is required"
      when 11
        raise SSHPassException, "Could not execute a remote command on #{host}: Password is incorrect"
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
