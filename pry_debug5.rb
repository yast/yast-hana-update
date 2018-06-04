# Debugging
require 'pry'
require 'yaml'
require 'rexml/document'
require 'rexml/xpath'

ENV['Y2DIR'] = File.expand_path('../src', __FILE__)

require 'yast'
require 'hana_update/hana'
require 'hana_update/cluster'
require 'hana_update/ssh'
require 'hana_update/system'
require 'hana_update/shell_commands'
include HANAUpdater::ShellCommands

# hanas = HANAUpdater::Hana.discover()

# puts "HANA discovered? #{!hanas.empty?}"

# unless hanas.empty?

# end

# puts "HANA XXX:10 is running? #{HANAUpdater::Hana.check_hdb_daemon_running('XXX', 10)}"

# HANAUpdater::Cluster.test = true
# cls = HANAUpdater::Cluster
# # out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
# doc = REXML::Document.new(File.read('crm_mon_r_as_xml.xml'))
c = HANAUpdater::Cluster
c.update_state
if c.warnings.length > 0
    puts "WARNINGS:"
    puts c.warnings
end
if !c.groups.empty?
    node = c.groups.first.master.primitives.first.running_on
    f = c.groups.first
    s = c.groups[1]
end


def get_keys(sid)
    sap_admin_user = "#{sid.downcase}adm"
    out, status = su_exec_get_output(sap_admin_user, "echo $DIR_INSTANCE")
    unless status.exitstatus == 0
        log.error "Cannot get $DIR_INSTANCE from #{sap_admin_user}'s environment. rc=#{status.exitstatus}, out=#{out.strip}"
        raise "Cannot get $DIR_INSTANCE from #{sap_admin_user}'s environment." 
    end
    dir_instance = out.strip
    file_list = [
        "#{dir_instance}/../global/security/rsecssfs/data/SSFS_#{sid.upcase}.DAT",
        "#{dir_instance}/../global/security/rsecssfs/key/SSFS_#{sid.upcase}.KEY"
    ]
    unless file_list.all? {|fpath| File.exists?(fpath)}
        log.error "Could not locate the SSFS files for HANA. Expected locations were: #{file_list}"
        raise "Cannot locate the SSFS files for HANA."
    end
    file_list.each do |file_path|
      begin
        SapHA::System::SSH.instance.copy_file_to(file_path, secondary_host_name, password)
      rescue SSHException => e
        NodeLogger.error "Could not copy HANA PKI SSFS file #{file_path}"
        NodeLogger.output e.message
      else
        NodeLogger.info "Copied HANA PKI SSFS file #{file_path} to node #{secondary_host_name}"
      end          
    end
end


binding.pry


puts nil