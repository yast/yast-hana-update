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
# require 'hana_update/exceptions'
# require 'hana_update/helpers'
require 'hana_update/node_logger'
require 'hana_update/shell_commands'

module HANAUpdater
  # HANA configuration routines
  class HanaClass
    include Singleton
    include ShellCommands

    SAP_SERVICES_PATH = '/usr/sap/sapservices'.freeze
    SAP_SERVICES_REGEXP = %r{
      # path to the profile contains the SID, instance number and the virtual host mapping
      .*pf=/.*/
      (?<sid>[A-Z][A-Z0-9][A-Z0-9])
      /(SYS/profile|profile)/
      \k<sid>_HDB(?<instance>[0-9][0-9])_(?<virtual_host>[^ ]+).*
      }x

    # Check if HBD daemon is running
    # @param system_id [String] SAP SID of the HANA instance
    # @param instance_number [String] HANA instance number
    def check_hdb_daemon_running(system_id, instance_number)
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{instance_number}) ---"
      procname = "hdb.sap#{system_id.upcase}_HDB#{instance_number}"
      _out, status = exec_outerr_status('pidof', procname)
      status.exitstatus == 0
    end

    def discover
      hanas = []
      if File.exist?(SAP_SERVICES_PATH)
        File.readlines(SAP_SERVICES_PATH).each do |line|
          match_data = SAP_SERVICES_REGEXP.match(line)
          hanas << Hash[match_data.names.map(&:to_sym).zip(match_data.captures)] if match_data
        end
      end
      hanas
    end

    # Start HANA by issuing the `HDB start` command as `<sid>adm` user
    # @param system_id [String] SAP SID of the HANA instance
    def start(system_id, opts={node: :local})
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = %w(HDB start)
      if opt[:node] == :local
        out, status = su_exec_outerr_status(user_name, *command)
      else
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *wrap_ssh_su_call(user_name, command))
      end
      s = NodeLogger.log_status(status.exitstatus == 0,
                                "Started HANA #{system_id}",
                                "Could not start HANA #{system_id}, will retry.",
                                out
      )
      return true if s
      out, status = su_exec_outerr_status(user_name, *command)
      NodeLogger.log_status(status.exitstatus == 0,
                            "Started HANA #{system_id}",
                            "Could not start HANA #{system_id}, bailing out.",
                            out
      )
    end

    # Get the HANA version as a string
    # @param system_id [String] SAP SID of the HANA instance
    # @return [String, nil] version string or nil on failure
    def version(system_id, opts={node: :local})
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = %w(HDB version)
      if opts[:node] == :local
        out, status = su_exec_outerr_status(user_name, *command)
      else
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *wrap_ssh_su_call(user_name, command))
      end
      unless status.exitstatus == 0
        NodeLogger.error('Could not retrieve HANA version, assuming legacy version')
        NodeLogger.output(out)
        return nil
      end
      match = /version:\s+(\d+.\d+.\d+.\d+.\d+)/.match(out)
      return nil if match.nil?
      match.captures.first
    end

    # Stop HANA by issuing the `HDB stop` command as `<sid>adm` user
    # @param system_id [String] SAP SID of the HANA instance
    def stop(system_id, opts=[node: :local])
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = %w(HDB stop)
      if opt[:node] == :local
        out, status = su_exec_outerr_status(user_name, *command)
      else
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *wrap_ssh_su_call(user_name, command))
      end
      s = NodeLogger.log_status(status.exitstatus == 0,
                                "Stopped HANA #{system_id}",
                                "Could not stop HANA #{system_id}, will retry.",
                                out
      )
      return true if s
      out, status = su_exec_outerr_status(user_name, *command)
      NodeLogger.log_status(status.exitstatus == 0,
                            "Stopped HANA #{system_id}",
                            "Could not stop HANA #{system_id}, bailing out.",
                            out
      )
    end

    # Enable System Replication on the primary HANA system
    # @param system_id [String] HANA System ID
    # @param site_name [String] HANA site name of the primary instance
    def sr_enable_primary(system_id, site_name, opts={node: :local})
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{site_name}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = ['hdbnsutil', '-sr_enable', "--name=#{site_name}"]
      if opts[:node] == :local
        out, status = su_exec_outerr_status(user_name, *command)
      else
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *wrap_ssh_su_call(user_name, command))
      end
      NodeLogger.log_status(status.exitstatus == 0,
                            "Enabled HANA (#{system_id}) System Replication on the primary site #{site_name}",
                            "Could not enable HANA (#{system_id}) System Replication on the primary site #{site_name}",
                            out
      )
    end

    # Enable System Replication on the secondary HANA system
    # @param system_id [String] HANA System ID
    # @param site_name [String] HANA site name of the secondary instance
    # @param host_name_primary [String] host name of the primary node
    # @param instance [String] instance number of the primary
    # @param rmode [String] replication mode
    # @param omode [String] operation mode
    def sr_register_secondary(system_id, instance, site_name, host_name_primary, rmode, omode, opts={node: :local})
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{site_name},"\
        " #{host_name_primary}, #{instance}, #{rmode}, #{omode}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      version = version(system_id, opts[:node])
      if HANAUpdater::Helpers.version_comparison('1.00.120', version)
        rmode_string = "--replicationMode=#{rmode}"
      else
        rmode_string = "--mode=#{rmode}"
      end
      if HANAUpdater::Helpers.version_comparison('1.00.110', version)
        omode_string = "--operationMode=#{omode}"
      else
        omode_string = nil
      end
      command = 'hdbnsutil', '-sr_register', "--remoteHost=#{host_name_primary}",
          "--remoteInstance=#{instance}", rmode_string, omode_string,
          "--name=#{site_name}"
      command.reject!(&:nil?)
      if opts[:node] == :local
        out, status = su_exec_outerr_status(user_name, *command)
      else
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *wrap_ssh_su_call(user_name, command))
      end
      NodeLogger.log_status(status.exitstatus == 0,
                            "Registered site #{site_name} (#{system_id}) as secondary site to primary on host #{host_name_primary}",
                            "Could not register site #{site_name} (#{system_id}) as secondary to primary on host #{host_name_primary}",
                            out
      )
    end

    # Form a command line for checking the System Replication status
    # @param system_id [String] HANA System ID
    def check_sys_replication_cmd(system_id)
      # TODO: provide parameter --site=REMOTESITENAME, so that the script filters all other stuff
      user_name = "#{system_id.downcase}adm"
      cmd = 'su', '-lc', '"HDBSettings.sh systemReplicationStatus.py"', user_name
      return cmd
    end

    # Enable System Replication on the secondary HANA system
    # @param system_id [String] HANA System ID
    # @param site_name [String] HANA site name of the secondary instance
    # @param host_name_primary [String] host name of the primary node
    # @param instance [String] instance number of the primary
    # @param rmode [String] replication mode
    # @param omode [String] operation mode
    def enable_secondary(system_id, site_name, host_name_primary, instance, rmode, omode)
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{site_name},"\
        " #{host_name_primary}, #{instance}, #{rmode}, #{omode}) ---"
      user_name = "#{system_id.downcase}adm"
      version = version(system_id)
      # Select an appropriate command-line switch for replication mode
      # Assume legacy `mode` by default (pre-SPS12)
      rmode_string = if HANAUpdater::Helpers.version_comparison('1.00.120', version)
                       "--replicationMode=#{rmode}"
                     else
                       "--mode=#{rmode}"
                     end
      omode_string = if HANAUpdater::Helpers.version_comparison('1.00.110', version)
                       "--operationMode=#{omode}"
                     else
                       nil
                     end
      command = ['hdbnsutil', '-sr_register', "--remoteHost=#{host_name_primary}",
                 "--remoteInstance=#{instance}", rmode_string, omode_string,
                 "--name=#{site_name}"].reject(&:nil?)
      out, status = su_exec_outerr_status(user_name, *command)
      NodeLogger.log_status(status.exitstatus == 0,
                            "Enabled HANA (#{system_id}) System Replication on the secondary host #{site_name}",
                            "Could not enable HANA (#{system_id}) System Replication on the secondary host",
                            out
      )
    end

    def takeover(system_id, opts={node: :local})
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{opts}) ---"
      user_name = "#{system_id.downcase}adm"
      command = 'hdbnsutil', '-sr_takeover'
      if opts[:node] == :local
        out, status = su_exec_outerr_status(user_name, *command)
      else
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *wrap_ssh_su_call(user_name, command))
      end
      NodeLogger.log_status(status.exitstatus == 0,
                            "Took over HANA #{system_id} to local site",
                            "Could not take-over HANA (#{system_id}) to local site",
                            out
      )
    end

    # Disable System Replication on the secondary (local) HANA system
    def disable_secondary(system_id, opts={node: :local})
      log.info "--- called #{self.class}.#{__callee__}(#{system_id} ---"
      user_name = "#{system_id.downcase}adm"
      command = %w(hdbnsutil -sr_unregister)
      if opts[:node] == :local
        out, status = su_exec_outerr_status(user_name, *command)
      else
        out, status = HANAUpdater::SSH.run_command_wait2(opts[:node], *wrap_ssh_su_call(user_name, command))
      end
      NodeLogger.log_status(status.exitstatus == 0,
                            "Disabled HANA (#{system_id}) System Replication on the secondary site",
                            "Could not disable HANA (#{system_id}) System Replication on the secondary site",
                            out
      )
    end

    def disable_primary_cmd(system_id)
      log.info "--- called #{self.class}.#{__callee__}(#{system_id} ---"
      user_name = "#{system_id.downcase}adm"
      command = 'su', '-lc', '"hdbnsutil -sr_unregister"', user_name
    end

    # List the keys out of the HANA secure user store
    # @param system_id [String] HANA System ID
    def check_secure_store(system_id)
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}) ---"
      regex = /^KEY (\w+)$/
      user_name = "#{system_id.downcase}adm"
      command = %w(hdbuserstore list)
      out, status = su_exec_outerr_status(user_name, *command)
      unless status.exitstatus == 0
        log.error "Could not get the list of keys in the HANA secure user store (status=#{status.exitstatus}): #{out}"
        return []
      end
      out.scan(regex).flatten
    end

    def set_secute_store(system_id, key_name, env, user_name, password)
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{key_name}, ...) ---"
      su_name = "#{system_id.downcase}adm"
      command = ['hdbuserstore', 'set', key_name, env, user_name, password]
      out, status = su_exec_outerr_status(su_name, *command)
      NodeLogger.log_status(status.exitstatus == 0,
                            "Successfully set key #{key_name} in the secure user store on system #{system_id}",
                            "Could not set key #{key_name} in the secure user store on system #{system_id}",
                            out
      )
    end

    # Execute an HDBSQL command
    # @param system_id [String] HANA System ID
    # @param user_name [String] HANA user name
    # @param instance number [String] HANA instance number
    # @param password [String] HANA password
    # @param environment [String] HANA host:port specification (can be empty)
    # @param statement [String] SQL statement
    def hdbsql_command(system_id, user_name, instance_number, password, environment, statement)
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{user_name},"\
        " #{instance_number}, password, #{environment}, #{statement}) ---"
      su_name = "#{system_id.downcase}adm"
      cmd = 'hdbsql', '-x', '-u', user_name, '-i', instance_number.to_s, '-p', password
      cmd << '-n' << environment unless environment.empty?
      cmd << '"' << statement.gsub('"', "\\\"") << '"'
      out, status = su_exec_outerr_status_no_echo(su_name, *cmd)
      if status.exitstatus != 0
        # remove the password from the command line
        pass_index = (cmd.index('-p') || 0) + 1
        cmd[pass_index] = '*' * cmd[pass_index].length
        NodeLogger.error "Error executing command #{cmd.join(' ')}"
        NodeLogger.output out
        return
      end
      out
    end

    # Execute an HDBSQL command
    # @param system_id [String] HANA System ID
    # @param user_name [String] HANA user name
    # @param instance_number [String] HANA instance number
    # @param password [String] HANA password
    # @param environment [String] HANA host:port specification (can be empty)
    # @param statement [String] SQL statement
    def check_system_replication(system_id, user_name, instance_number, password)
      log.info "--- called #{self.class}.#{__callee__}(#{system_id}, #{user_name},"\
        " #{instance_number}, password ---"
      su_name = "#{system_id.downcase}adm"
      cmd = 'hdbsql', '-x', '-u', user_name, '-i', instance_number.to_s, '-p', password, '-a', "-F';'"
      # cmd << '-n' << environment unless environment.empty?
      cmd << '"' << 'select host,secondary_host, volume_id, replication_status from M_SERVICE_REPLICATION' << '"'
      out, status = su_exec_outerr_status_no_echo(su_name, *cmd)
      if status.exitstatus != 0
        # remove the password from the command line
        pass_index = (cmd.index('-p') || 0) + 1
        cmd[pass_index] = '*' * cmd[pass_index].length
        NodeLogger.error "Error executing command #{cmd.join(' ')}"
        NodeLogger.output out
        return
      end
      out.split.map { |e| e.split(';').reject(&:empty?).map { |z| z.gsub('"', '') } }
    end

    private

    def wrap_ssh_su_call(user_name, cmd)
      ['su', '-lc', '"', cmd.join(' '), '"', user_name].join(' ')
    end
  end # HanaClass
  Hana = HanaClass.instance
end # namespace HANAUpdater
