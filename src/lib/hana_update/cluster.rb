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
    attr_reader :name, :id, :cached
    def initialize(mon_xml_node, cib_xml, sid)
      # print "Node(\nsid=#{sid},\nmon_xml_node=#{mon_xml_node},\ncib_xml_node=#{cib_xml}\n\n"
      mon_xml_node.attributes.each { |k, v| instance_variable_set("@#{k}", v) }
      @inst_attr = Hash[]
      name_prefix = "hana_#{sid.downcase}"
      REXML::XPath.each(cib_xml,
        '/cib/configuration/nodes/node[@id=$node_id]/instance_attributes/nvpair', nil,
        'node_id' => @id) do |z|
        # transform attribute names from hana_sid_* to *
        # and don't forget about lpt_sid_lpa
        name = z.attributes['name']
        name = name[name.rindex('_')+1..name.length()]
        value = z.attributes['value']
        @inst_attr[name] = value
      end
      
    end

    def localhost?
      @name == Socket.gethostname
    end

    def site
      @inst_attr['site']
    end
  end

  class PrmResource
    attr_reader :mon_attr, :inst_attr, :id, :running_on
    def initialize(sid, mon_xml_node, cib_xml_node)
      # print "PrmResource(\nsid=#{sid},\nmon_xml_node=#{mon_xml_node},\ncib_xml_node=#{cib_xml_node}\n\n"
      @mon_attr = Hash[mon_xml_node.attributes.map { |k, v| [k, v] }]
      @id = @mon_attr['id']
      # mon_xml_node.attributes.each { |k, v| instance_variable_set("@#{k}", v) }
      # only primitives can be running
      if self.class == PrmResource
        if !mon_xml_node.elements['node'].nil?
          # binding.pry
          @running_on = Node.new(mon_xml_node.elements['node'], cib_xml_node.root, sid)
        else
          @running_on = nil
        end
      end
      if !cib_xml_node.nil?
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
    def initialize(sid, mon_xml_node, cib_xml_node)
      # print "ClnResource(\nsid=#{sid},\nmon_xml_node=#{mon_xml_node},\ncib_xml_node=#{cib_xml_node}\n\n"
      super
      @primitives = mon_xml_node.get_elements('resource').map do |rsc|
        primitive_cib = cib_xml_node.get_elements('primitive').first
        PrmResource.new(sid, rsc, primitive_cib)
      end
    end

    # get local instance of the primitive
    def local
      @primitives.find { |pri| pri.running_on.localhost? }
    end

    def remote
      @primitives.find { |pri| !pri.running_on.localhost? }
    end
  end

  class MslResource < ClnResource
    def initialize(sid, mon_xml_node, cib_xml_node)
      # print "MslResource(\nsid=#{sid},\nmon_xml_node=#{mon_xml_node},\ncib_xml_node=#{cib_xml_node}\n\n"
      super
    end

    def master
      @primitives.find { |pri| pri.mon_attr['role'] == 'Master' }
    end

    def slave
      @primitives.find { |pri| pri.mon_attr['role'] == 'Slave' }
    end
  end

  class ResourceGroup
    attr_reader :master, :clone, :vip, :hana_sid, :hana_inst
    def initialize(mon_xml, cib_xml, msl_mon)
      rsc_id = msl_mon.elements['resource'].attributes['id']
      msl_cib = REXML::XPath.first(cib_xml, '//cib/configuration/resources/master[@id=$aid]',
        nil, 'aid' => msl_mon.attributes['id'])
      z = REXML::XPath.first(cib_xml, '//nvpair[@id=$aid]', {},
        'aid'=>"#{rsc_id}-instance_attributes-SID")
      sid = z.attributes['value']
      # now find a clone for the same SID
      cln_cib = REXML::XPath.first(cib_xml,
        '//cib/configuration/resources/clone[./primitive/instance_attributes'\
        '/nvpair[@name="SID" and @value=$sid]]', nil, 'sid' => sid)
      cln_mon = REXML::XPath.first(mon_xml,
        '//crm_mon/resources/clone[@id = $sid]', nil, 'sid' => cln_cib.attributes['id'])
      @clone = ClnResource.new(sid, cln_mon, cln_cib)
      @master = MslResource.new(sid, msl_mon, msl_cib)
      vip_colocation = REXML::XPath.first(cib_xml,
        '/cib/configuration/constraints/rsc_colocation[@with-rsc=$msl_id '\
        'and @with-rsc-role="Master"]', nil, 'msl_id'=>msl_mon.attributes['id'])
      vip_id = vip_colocation.attributes['rsc']
      vip_mon = REXML::XPath.first(mon_xml,
        '//crm_mon/resources/resource[@id=$vip_id]', nil, 'vip_id'=>vip_id)
      vip_cib = REXML::XPath.first(cib_xml,
        '//cib/configuration/resources/primitive[@id=$vip_id]', nil, 'vip_id'=>vip_id)
      @vip = PrmResource.new(sid, vip_mon, vip_cib)
      @hana_sid = sid
      @hana_inst = @master.primitives.first.inst_attr['InstanceNumber']
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
      msl_mons = REXML::XPath.match(crm_mon,
        '//crm_mon/resources/clone[./resource[@resource_agent=$ra_type and @orphaned="false"]]',
        {}, 'ra_type'=>MSL_RESOURCE_TYPE
                                   )
      @groups = msl_mons.map { |msl_mon| ResourceGroup.new(crm_mon, cib_status, msl_mon) }
    end

    def get_system(sid, ino)
      f = @groups.find { |g| g.hana_sid == sid && g.hana_inst == ino }
      if f.nil?
        log.error "Could not find HANA system with sid=#{sid} and ino=#{ino}"
        log.error @groups.map { |g| [g.hana_sid, g.hana_inst].join(":") }.join(", ")
      end
      f
    end
    
    private

    # Read and parse output of crm_mon
    def get_crm_mon
      out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
      # out = File.read('new_xml/crm_mon_fake.xml')
      # TODO: log the output here
      raise "Could not connect to cluster: #{out}" if status.exitstatus != 0
      REXML::Document.new(out)
    end

    # Read and parse output of cibadmin -Ql
    def get_cib
      out, status = exec_outerr_status('cibadmin', '-Q', '-l')
      # TODO: log the output here
      raise "Could not connect to cluster: #{out}" if status.exitstatus != 0
      REXML::Document.new(out)
    end
  end

  Cluster = ClusterClass.instance
end
