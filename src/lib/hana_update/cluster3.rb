require 'yast'
require 'rexml/document'
require 'rexml/xpath'
require 'hana_update/shell_commands'
require 'hana_update/exceptions'
require 'hana_update/hana'
require 'hana_update/ssh'
require 'socket'

module HANAUpdater
  class Node
    attr_reader :cached, :id, :name, :attributes

    def initialize(node_xml, crm_mon, hana_sid, remote_version = false)
      node_xml.attributes.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
      @attributes = {}
      REXML::XPath.each(crm_mon, '//crm_mon/node_attributes/node[@name=$node_name]/attribute',
                        {}, "node_name" => @name) do |attr|
        att_name = attr.attributes['name']
        if att_name.start_with?("hana_#{hana_sid.downcase}")
          att_name = att_name[9..att_name.length]
        elsif att_name.start_with?("lpa_#{hana_sid.downcase}")
          att_name = 'lpa_lpt'
        else
          next
        end
        @attributes[att_name] = attr.attributes['value']
      end
      if !@attributes.key?('version')
        if localhost?
          @attributes['version'] = HANAUpdater::Hana.version(hana_sid)
        elsif remote_version
          remote_cmd = 'su -l xxxadm HDB version'
          out, status = SSH.run_command2(@name, remote_cmd)
          raise "Could not get output of remote command #{remote_cmd} on node #{@name}" \
            unless status.exitstatus == 0
          match = /version:\s+(\d+.\d+.\d+.\d+.\d+)/.match(out)
          @attributes['version'] = match.captures.first
        end
      end
    end

    def localhost?
      @name == Socket.gethostname
    end

    def to_s
      @name + (localhost? ? ' (this node)' : '')
    end
  end

  class PriResource
    attr_reader :active, :blocked, :failed, :failure_ignored, :id, :managed,
                :nodes_running_on, :orphaned, :resource_agent, :role, :attributes,
                :hana_sid, :hana_ino

    def initialize(rsc_node, cib, crm_mon)
      rsc_node.attributes.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
      @hana_sid = get_cib_inst_attrib(cib, 'SID')
      @hana_ino = get_cib_inst_attrib(cib, 'InstanceNumber')
      # TODO: check that nodes_running_on.length == 1
      @nodes_running_on = []
      # binding.pry
      rsc_node.elements.each('node') do |nd|
        @nodes_running_on << Node.new(nd, crm_mon, @hana_sid)
      end
    end

    def system_name
      "#{@hana_sid}/#{@hana_ino}"
    end

    private

    def get_cib_inst_attrib(cib, aname)
      attr_id = "#{@id}-instance_attributes-#{aname}"
      attributes = REXML::XPath.match(cib, '//nvpair[@id=$aid]', {}, {'aid'=> attr_id})
      raise "Error parsing CIB XML: found #{attributes.length} "\
        "matches for attribute #{attr_id}" unless attributes.length == 1
      attributes[0].attributes['value']
    end
  end

  class ClusterClass
    include Singleton
    include ShellCommands
    include Yast::Logger

    attr_reader :resources

    RESOURCE_TYPE = 'ocf::suse:SAPHana'.freeze

    def initialize
      @resources = []
    end

    def update_state
      crm_mon = get_crm_mon
      cib_status = get_cib
      hana_resources = REXML::XPath.match(crm_mon,
        '//crm_mon/resources/clone/resource[@resource_agent=$ra_type and @orphaned="false"]', {},
        'ra_type'=>RESOURCE_TYPE)
      @resources = hana_resources.map { |e| PriResource.new(e, cib_status, crm_mon) }
    end

    def find_resource_by_system(system_id)
      @resources.find { |r| r.hana_sid == system_id }
    end
    # private

    # Read and parse output of crm_mon
    def get_crm_mon
      out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
      # out = File.read('new_xml/crm_mon_fake.xml')
      # TODO: log the output here
      raise "Could not connect to cluster: #{out}" if status.exitstatus != 0
      return REXML::Document.new(out)
    end

    # Read and parse output of cibadmin -Ql
    def get_cib
      out, status = exec_outerr_status('cibadmin', '-Q', '-l')
      # TODO: log the output here
      raise "Could not connect to cluster: #{out}" if status.exitstatus != 0
      return REXML::Document.new(out)
    end
  end

  Cluster = ClusterClass.instance
end
