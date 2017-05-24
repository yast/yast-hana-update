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
                :running_on, :orphaned, :resource_agent, :role, :attributes,
                :hana_sid, :hana_ino, :msl_id

    def initialize(resource_xml, cib, crm_mon)
      @msl_id = resource_xml.parent.attributes['id']
      resource_xml.attributes.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
      @hana_sid = get_cib_inst_attrib(cib, 'SID')
      @hana_ino = get_cib_inst_attrib(cib, 'InstanceNumber')
      
      @running_on = nil
      # binding.pry
      nodes = resource_xml.get_elements('node')
      if nodes.length > 1
        rsc_id = rsc_node.attributes['id']
        nodes_str = nodes.map{|n| n.attributes['name']}.join(',')
        raise "Resource #{rsc_id} is running on more than one node: #{nodes_str}"
      elsif nodes.length == 1
        @running_on = Node.new(nodes.first, crm_mon, @hana_sid)
      end
    end

    def system_name
      "#{@hana_sid}/#{@hana_ino}"
    end

    def node
      return nil if @running_on.nil?
      @running_on.name
    end

    def site
      return nil if @running_on.nil?
      @running_on.attributes['site']
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

  class Node
    attr_reader :name, :id, :cached
    def initialize(mon_xml_node)
      mon_xml_node.attributes.each { |k, v| instance_variable_set("@#{k}", v) }
    end
  end

  class PrmResource
    attr_reader :mon_attr, :inst_attr, :id
    def initialize(mon_xml_node, cib_xml_node)
      @mon_attr = Hash[mon_xml_node.attributes.map { |k, v| [k, v] }]
      @id = @mon_attr['id']
      # mon_xml_node.attributes.each { |k, v| instance_variable_set("@#{k}", v) }
      # only primitives can be running
      if self.class == PrmResource
        @running_on = Node.new(mon_xml_node.elements['node'])
      end
      # binding.pry
      if !cib_xml_node.nil?
        # binding.pry
        ia = cib_xml_node.elements['instance_attributes']
        unless ia.nil?
          @inst_attr = Hash[
            ia.get_elements('nvpair').map {|e| [e.attributes['name'], e.attributes['value']] }]
        end
      end
    end
  end

  class ClnResource < PrmResource
    attr_reader :primitives
    def initialize(mon_xml_node, cib_xml_node)
      super
      @primitives = mon_xml_node.get_elements('resource').map do |rsc|
        primitive_cib = cib_xml_node.get_elements('primitive').first
        PrmResource.new(rsc, primitive_cib)
      end
    end
  end

  class MslResource < ClnResource
    def master
      @primitives.find { |pri| pri.mon_attr['role'] == 'Master' }
    end

    def slave
      @primitives.find { |pri| pri.mon_attr['role'] == 'Slave' }
    end
  end

  class ResourceGroup
    def initialize(mon_xml, cib_xml, msl_mon)
      rsc_id = msl_mon.elements['resource'].attributes['id'] 
      msl_cib = REXML::XPath.first(cib_xml, '//cib/configuration/resources/master[@id=$aid]', nil, 'aid' => msl_mon.attributes['id'])
      z = REXML::XPath.first(cib_xml, '//nvpair[@id=$aid]', {},
        'aid'=>"#{rsc_id}-instance_attributes-SID")
      sid = z.attributes['value']
      # now find a clone for the same SID
      cln_cib = REXML::XPath.first(cib_xml, 
        '//cib/configuration/resources/clone[./primitive/instance_attributes'\
        '/nvpair[@name="SID" and @value=$sid]]', nil, 'sid' => sid)
      cln_mon = REXML::XPath.first(mon_xml,
        '//crm_mon/resources/clone[@id = $sid]', nil, 'sid' => cln_cib.attributes['id']
        )
      @clone = ClnResource.new(cln_mon, cln_cib)
      @master = MslResource.new(msl_mon, msl_cib)
      # binding.pry
      vip_colocation = REXML::XPath.first(cib_xml, 
        '/cib/configuration/constraints/rsc_colocation[@with-rsc=$msl_id and @with-rsc-role="Master"]',
        nil, 'msl_id'=>msl_mon.attributes['id']
        )
      vip_id = vip_colocation.attributes['rsc']
      vip_mon = REXML::XPath.first(mon_xml,
        '//crm_mon/resources/resource[@id=$vip_id]', nil, 'vip_id'=>vip_id)
      vip_cib = REXML::XPath.first(cib_xml, '//cib/configuration/resources/primitive[@id=$vip_id]', 
        nil, 'vip_id'=>vip_id)
      @vip = PrmResource.new(vip_mon, vip_cib)
      # binding.pry
      @hana_sid = @master.primitives.first.inst_attr['SID']
    end
  end

  class ClusterClass
    include Singleton
    include ShellCommands
    include Yast::Logger

    attr_reader :groups

    MSL_RESOURCE_TYPE = 'ocf::suse:SAPHana'.freeze
    CLN_RESOURCE_TYPE = 'ocf::suse:SAPHanaTopology'.freeze

    def initialize
      @groups = []
    end

    def update_state
      crm_mon = get_crm_mon
      cib_status = get_cib
      matches = []
      msl_mons = REXML::XPath.match(crm_mon, 
        '//crm_mon/resources/clone[./resource[@resource_agent=$ra_type and @orphaned="false"]]',
        {}, 'ra_type'=>MSL_RESOURCE_TYPE
      )
      @groups = msl_mons.map {|msl_mon| ResourceGroup.new(crm_mon, cib_status, msl_mon) }
      end
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
