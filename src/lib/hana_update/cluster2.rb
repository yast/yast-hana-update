require 'rexml/document'
require 'rexml/xpath'
require 'hana_update/shell_commands'
require 'hana_update/exceptions'
require 'hana_update/hana'
require 'hana_update/ssh'
require 'socket'
# schema is
# /usr/share/pacemaker/crm_mon.rng

module HANAUpdater
  class ClusterResource
    def initialize(id)
      @id = id
    end

    def update
    end
    def move(to_node)
      # crm_resource --quiet --move -r 'rsc_ip_XXX_HDB00' --node='hana02'
    end
  end

  class ClusterNode
    attr_reader :name, :id, :hana_role, :is_maintenance
    # TODO need <SID>
    def initialize(primitive, xml)
      a = primitive.attributes
      @primitive_id = a['id']
      @hana_role = a['role']
      @id = primitive.elements['node'].attributes['id']
      node = xml.elements["/crm_mon/nodes/node[@id='#{@id}']"]
      @name = node.attributes['name']
      @is_maintenance = node.attributes['maintenance']
      # TODO: maintenance here could be of three different types:
      #
      # Cluster-wide:
      # <cib><configuration><crm_config><cluster_property_set id="cib-bootstrap-options">
      # <nvpair name="maintenance-mode" value="false" id="cib-bootstrap-options-maintenance-mode"/>
      #
      # On resource level in CIB:
      # <master id="msl_SAPHana_XXX_HDB00">
      #  <meta_attributes id="msl_SAPHana_XXX_HDB00-meta_attributes">
      #    <nvpair id="msl_SAPHana_XXX_HDB00-meta_attributes-maintenance" name="maintenance" value="true"/>
      #
      # On node-level:
      # <crm_mon>
      #   <summary>
      #      <cluster_options stonith-enabled="true" symmetric-cluster="true" no-quorum-policy="stop" maintenance-mode="false" />
      #
      # <nodes>
      #    <node name="hana01" id="1084777749" online="true" standby="false" standby_onfail="false" maintenance="false" pending="false" unclean="false" shutdown="false" expected_up="true" is_dc="true" resources_running="4" type="member" />
      #

    end

    def update(xml)/
      node = xml.elements["/crm_mon/nodes/node[@id='#{@id}']"]
      raise StandardError("Wrong XML used for update") if node.nil?
      @is_maintenance = node.attributes['maintenance']
    end

    def maintenance_mode(val)
      if val
        # put to maintenance mode
        # crm_attribute -t nodes -N 'hana01' -n maintenance -v 'on'
      else
        # crm_attribute -t nodes -N 'hana01' -n maintenance -v 'off'
      end
    end

    def stop_hana
      # su - <SID>adm HDB stop
    end

    def start_hana
    end

    def is_hana_running
      # 
    end
  end

  class ClusterState
    RESOURCE_TYPE='ocf::suse:SAPHana'

    attr_reader :nodes
    def initialize(cib_xml_fn, crm_mon_xml_fn)
      @cib_xml = cib_xml_fn.call
      @crm_mon_xml = crm_mon_xml_fn.call
      init_from_crm_mon
      init_from_cib
    end

    def master_node
      @nodes.select { |e| e.hana_role == 'Master' }
    end

    def update
      # get new crm_mon_xml
      hana_resources = REXML::XPath.match(@crm_mon_xml,
        '//crm_mon/resources/clone/resource[@resource_agent=$ra_type and @orphaned="false"]', {},
        {'ra_type'=>RESOURCE_TYPE})
      raise StandardError("Found #{hana_resources.length} resources of type #{RESOURCE_TYPE}, expected 2.") if hana_resources.length != 2
      @nodes = hana_resources.map do |e|
        ClusterNode.new(e, @crm_mon_xml)
      end
    end

    private

    def init_from_crm_mon
      hana_resources = REXML::XPath.match(@crm_mon_xml,
        '//crm_mon/resources/clone/resource[@resource_agent=$ra_type and @orphaned="false"]', {},
        {'ra_type'=>RESOURCE_TYPE})
      raise StandardError("Found #{hana_resources.length} resources of type #{RESOURCE_TYPE}, expected 2.") if hana_resources.length != 2
      @nodes = hana_resources.map do |e|
        ClusterNode.new(e, @crm_mon_xml)
      end
      @msl_id = hana_resources.first.parent.attributes['id']
      @rsc_id = hana_resources.first.attributes['id']
    end

    def init_from_cib
      col = REXML::XPath.match(@cib_xml, '/cib/configuration/constraints/rsc_colocation').select do |c|
        c.attributes['rsc-role'] == 'Started' and
          c.attributes['with-rsc'] == @msl_id and 
          c.attributes['with-rsc-role'] == 'Master'
      end
      @ip_address = col.first.attributes['rsc'] unless col.first.nil?
      # get the SAP System ID
      msl_attributes = REXML::XPath.match(@cib_xml, "//cib/configuration/resources/master/primitive[@id='#{@rsc_id}']/instance_attributes")
      @sid = msl_attributes.first.elements['nvpair[@name="SID"]'].attributes['value']
      @instance = msl_attributes.first.elements['nvpair[@name="InstanceNumber"]'].attributes['value']
    end

  end

  class ClusterClass
    include Singleton
    include ShellCommands

    attr_accessor :test

    def initialize
      @test = false
    end

    def get_crm_mon
      unless @test
        out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
        raise StandardError("Could not connect to cluster: #{out}") if status.exitstatus != 0
        return out
      else
        REXML::Document.new(File.read('crm_mon_r_as_xml.xml'))
      end
    end

    def get_cib
      unless @test
        out, status = exec_outerr_status('cibadmin', '-Q', '-l')
        raise StandardError("Could not connect to cluster: #{out}") if status.exitstatus != 0
        return out
      else
        REXML::Document.new(File.read('cibadmin_Ql.xml'))
      end
    end

    def get_hana_state()
      ClusterState.new(lambda {get_cib} , lambda {get_crm_mon})
    end

  end
  Cluster = ClusterClass.instance
end
