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
# Summary: SAP HANA updater in a SUSE cluster
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'hana_update/node_logger'
require 'hana_update/shell_commands'
require 'hana_update/exceptions'
require 'hana_update/ssh'

module HANAUpdater
  # HANA configuration routines
  class HanaClass
    include Singleton
    include ShellCommands

    # Start HANA
    # @param [String] system_id  SAP SID of the HANA instance
    # @param [Hash] opts
    # @return [Boolean]
    def start(system_id, opts = { node: :local })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = %w(HDB start)
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      s = NodeLogger.log_status(status.exitstatus == 0,
        "Started HANA #{system_id}", "Could not start HANA #{system_id}, will retry.", out)
      return true if s
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      NodeLogger.log_status(status.exitstatus == 0,
        "Started HANA #{system_id}", "Could not start HANA #{system_id}, bailing out.", out)
    end

    # Stop HANA
    # @param [String] system_id  SAP SID of the HANA instance
    # @param [Object] opts
    def stop(system_id, opts = { node: :local })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = %w(HDB stop)
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      s = NodeLogger.log_status(status.exitstatus == 0,
        "Stopped HANA #{system_id}", "Could not stop HANA #{system_id}, will retry.", out)
      return true if s
      out, status = su_exec_get_output(user_name, *command)
      NodeLogger.log_status(status.exitstatus == 0,
        "Stopped HANA #{system_id}", "Could not stop HANA #{system_id}, bailing out.", out)
    end

    # Get HANA version as string
    # @param [String] system_id SAP SID of the HANA instance
    # @return [String, nil] version string or nil on failure
    def version(system_id, opts = { node: :local })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = %w(HDB version)
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      unless status.exitstatus == 0
        NodeLogger.error('Could not retrieve HANA version, assuming legacy version')
        NodeLogger.output(out)
        return nil
      end
      match = /version:\s+(\d+.\d+.\d+.\d+.\d+)/.match(out)
      return nil if match.nil?
      match.captures.first
    end

    # Enable System Replication on the primary HANA instance
    # @param [String] system_id HANA System ID
    # @param [String] site_name HANA site name of the primary instance
    # @param [Hash] opts
    def sr_enable_primary(system_id, site_name, opts = { node: :local })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{site_name}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = ['hdbnsutil', '-sr_enable', "--name=#{site_name}"]
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      NodeLogger.log_status(status.exitstatus == 0,
        "Enabled HANA (#{system_id}) System Replication on the primary site #{site_name}",
        "Could not enable HANA (#{system_id}) System Replication on the primary site #{site_name}",
        out)
    end

    # Disable System Replication on the primary HANA instance
    # @param [String] system_id HANA System ID
    # @param [Hash] opts
    def sr_disable_primary(system_id, opts = { node: :local })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = %w(hdbnsutil -sr_disable)
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      NodeLogger.log_status(status.exitstatus == 0,
        "Successfully disabled HANA System Replication for system #{system_id} on primary site",
        "Could not disable HANA System Replication for system #{system_id} on primary site",
        out)
    end

    # Enable System Replication on the secondary HANA instance
    # @param system_id [String] HANA System ID
    # @param site_name [String] HANA site name of the secondary instance
    # @param host_name_primary [String] host name of the primary node
    # @param instance [String] instance number of the primary
    # @param rmode [String] replication mode
    # @param omode [String] operation mode
    # rubocop:disable Metrics/ParameterLists
    def sr_register_secondary(system_id, instance, site_name, host_name_primary,
      rmode, omode, opts = { node: :local })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{site_name},"\
        " #{host_name_primary}, #{instance}, #{rmode}, #{omode}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      version = version(system_id, node: opts[:node])
      rmode_string = if HANAUpdater::Helpers.version_comparison('1.00.120', version)
                       "--replicationMode=#{rmode}"
                     else
                       "--mode=#{rmode}"
                     end
      omode_string = if HANAUpdater::Helpers.version_comparison('1.00.110', version)
                       "--operationMode=#{omode}"
                     end
      command = 'hdbnsutil', '-sr_register', "--remoteHost=#{host_name_primary}",
                "--remoteInstance=#{instance}", rmode_string, omode_string,
                "--name=#{site_name}"
      command.reject!(&:nil?)
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      NodeLogger.log_status(status.exitstatus == 0,
        "Registered site #{site_name} (#{system_id}) as secondary site to"\
          " primary on host #{host_name_primary}",
        "Could not register site #{site_name} (#{system_id}) as secondary to"\
          " primary on host #{host_name_primary}",
        out)
    end

    # Disable System Replication on the secondary HANA instance
    def sr_unregister_secondary(system_id, primary_site, opts = { node: :local })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{primary_site}, #{opts})"
      user_name = "#{system_id.downcase}adm"
      command = 'hdbnsutil', '-sr_unregister'
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      NodeLogger.log_status(status.exitstatus == 0,
        "Un-registered secondary site from primary #{primary_site}",
        "Could not un-register secondary site from primary #{primary_site}",
        out)
    end

    # Check status of System Replication
    # Note: should be only called on the primary
    def sr_check_status(system_id, remote_site, opts = { node: :local })
      log.debug "--- called #{self.class}.#{__callee__}(#{system_id}, #{remote_site}, #{opts})"
      # apparently, the error is not fatal an can be recovered automatically by HANA
      user_name = "#{system_id.downcase}adm"
      rc_text = { 10 => 'No HANA SR', 11 => 'Fatal Error', 12 => 'Unknown',
                        13 => 'Initializing', 14 => 'Syncing', 15 => 'Active' }
      command = 'HDBSettings.sh', 'systemReplicationStatus.py', "--site=#{remote_site}"
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      # # TODO: shall we return simply TRUE here or the actual exit status?
      NodeLogger.log_status(status.exitstatus == 15,
        'SAP HANA System Replication status: instances are in sync (rc=15)',
        "SAP HANA System Replication status: #{rc_text[status]} (rc=#{status.exitstatus})",
        out)
      [status.exitstatus, rc_text[status.exitstatus]]
    end

    # Perform HANA SR take-over to the secondary instance
    # @param [String] system_id HANA System ID
    # @param [Hash] opts
    def sr_takeover(system_id, opts = { node: :local })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = 'hdbnsutil', '-sr_takeover'
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      NodeLogger.log_status(status.exitstatus == 0,
        "Took over HANA #{system_id} to local site",
        "Could not take-over HANA (#{system_id}) to local site", out)
    end

    # Check if the specified sercure store key exists for the defined system
    # @param system_id [String] HANA System ID
    def check_secure_store(system_id, opts = { node: :local, key: 'SRTAKEOVER' })
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      regex = /^KEY (\w+)$/
      user_name = "#{system_id.downcase}adm"
      command = %w(hdbuserstore list)
      out, status = wrap_system_call(command, user_name: user_name, node: opts[:node])
      unless status.exitstatus == 0
        log.error "Could not get the list of keys in the HANA secure user store"\
          " (status=#{status.exitstatus}): #{out}"
        return false
      end
      keys = out.scan(regex).flatten
      keys.include?(opts[:key])
    end

    # Copy PKI SSFS key files from current host to the target_hostname
    # This is required during a HANA upgrade from 1.0 to 2.0
    # @param system_id [String] HANA System ID
    # @param target_hostname [String] Target host's name
    def copy_ssfs_keys(system_id, target_hostname)
      sap_admin_user = "#{system_id.downcase}adm"
      out, status = su_exec_get_output(sap_admin_user, "echo $DIR_INSTANCE")
      unless status.exitstatus == 0
        log.error "Cannot get $DIR_INSTANCE from #{sap_admin_user}'s environment. \
          rc=#{status.exitstatus}, out=#{out.strip}"
        raise "Cannot get $DIR_INSTANCE from #{sap_admin_user}'s environment."
      end
      dir_instance = out.strip
      file_list = [
        "#{dir_instance}/../global/security/rsecssfs/data/SSFS_#{system_id.upcase}.DAT",
        "#{dir_instance}/../global/security/rsecssfs/key/SSFS_#{system_id.upcase}.KEY"
      ]
      unless file_list.all? { |fpath| File.exist?(fpath) }
        log.error "Could not locate the SSFS files for HANA. \
          Expected locations were: #{file_list}"
        raise "Cannot locate the SSFS files for HANA."
      end
      file_list.each do |file_path|
        begin
          HANAUpdater::SSH.copy_file_to(file_path, target_hostname)
        rescue HANAUpdater::Exceptions::SSHException => e
          log.error "Could not copy HANA PKI SSFS file #{file_path}"
          log.error e.message
          raise "Could not copy HANA PKI SSFS file #{file_path}: #{e.message}"
        else
          log.warn "-- Copied HANA PKI SSFS file #{file_path} to node #{target_hostname} --"
        end
      end
    end

    private

    def wrap_ssh_su_call(user_name, cmd)
      ['su', '-lc', '"' + cmd.join(' ') + '"', user_name]
    end

    def wrap_system_call(command, opts = {})
      raise 'Required option opts[:user_name] was ommitted' if opts[:user_name].nil?
      raise 'Required option opts[:node] was ommitted' if opts[:node].nil?
      if opts[:node] == :local
        out, status = su_exec_get_output(opts[:user_name], *command)
      elsif opts[:node].is_a?(String) && !opts[:node].empty?
        out, status = HANAUpdater::SSH.rexec_wait_get_output(opts[:node],
          *wrap_ssh_su_call(opts[:user_name], command))
      else
        raise 'Required option opts[:node] has to be :local or a valid hostname'
      end
      [out, status]
    end
  end # HanaClass

  Hana = HanaClass.instance
end # namespace HANAUpdater
