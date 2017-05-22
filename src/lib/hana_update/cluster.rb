require 'rexml/document'
require 'rexml/xpath'
require 'hana_update/shell_commands'
require 'hana_update/exceptions'
require 'hana_update/hana'
require 'hana_update/ssh'
require 'hana_update/helpers'
require 'socket'
# schema is
# /usr/share/pacemaker/crm_mon.rng

module HANAUpdater

  class XMLHelperClass
    def initialize(attributes)
      attributes.each do |k, v|
        my_key = k.sub('-', '_')
        my_key = "@#{my_key}".to_sym
        instance_variable_set(my_key, transform_value(v))
      end
    end

    private

    def transform_value(v)
      # check boolean
      return v == 'true' if v == 'true' || v == 'false'
      begin
        return Integer(v)
      rescue ArgumentError
        return v
      end
      v
    end
  end

  class ClusterClass
    include Singleton
    include ShellCommands

    class ClusterNode < XMLHelperClass
      attr_reader :node_name, :id, :online, :standby, :maintenance, :pending, :unclean

      def set_hana_resource(node)
      end
    end

    class ClusterState
      attr_accessor :cluster_maintenance

      def initialize
        @cluster_maintenance = false
        @nodes = []
      end
    end

    class ResourceC
      attr_reader :node, :sr_state, :site_name, :vhost, :remote_vhost, :ra_state, :hana_version,
        :rep_mode, :op_mode
      @@field_desc = {
        node:         'Node Name',
        sr_state:     'System Replication State',
        site_name:    'Site Name',
        vhost:        'HANA Virtual Host',
        remote_vhost: 'HANA Remote Host',
        ra_state:     'Cluster Resource State',
        hana_version: 'HANA Version',
        rep_mode:     'Replication Mode',
        op_mode:      'Operation Mode'
      }
      def initialize(node_name, crm_attrs)
        @node = node_name
        # TODO: check the SID
        @sr_state = crm_attrs.fetch('hana_xxx_sync_state', '?')
        @site_name = crm_attrs.fetch('hana_xxx_site', '?')
        @vhost = crm_attrs.fetch('hana_xxx_vhost', '?')
        @remote_vhost = crm_attrs.fetch('hana_xxx_remoteHost', '?')
        @ra_state = crm_attrs.fetch('hana_xxx_clone_state', '?')
        @hana_version = crm_attrs.fetch('hana_xxx_version', '?')
        @rep_mode = crm_attrs.fetch('hana_xxx_srmode', '?')
        @op_mode = crm_attrs.fetch('hana_xxx_op_mode', 'N/A')
        reinit_version
      end

      def self.field_description(fld)
        @@field_desc[fld.to_s[1..-1].to_sym]
      end

      def field_description(fld)
        @@field_desc[fld.to_s[1..-1].to_sym]
      end

      private

      def reinit_version
        # TODO: check the SID
        if @hana_version == '?' && localhost?
          @hana_version = HANAUpdater::Hana.version('XXX')
        else
          out, status = SSH.run_command2(@node, 'su -l xxxadm HDB version')
          match = /version:\s+(\d+.\d+.\d+.\d+.\d+)/.match(out)
          @hana_version = match.captures.first
        end
      end

      def localhost?
        @node == Socket.gethostname
      end
    end


    # Provide a cluster overview nicely rendered into HTML page
    def cluster_overview
      l = [['hana01', 'NDB/00', 'WDF', '?', 'Master'], ['hana02', 'NDB/00', 'ROT', '?', 'Slave']]
      l = l.map { |e| e[0] }
      cont = HANAUpdater::Helpers.itemize_list(l)
      begin
        continue = cluster_up?
      rescue HANAUpdater::UserError => e
        continue = false
        log.error "Error connecting to the cluster management system: #{e.message}"
        # cont << e.message
      end
      return continue, cont
    end

    # Check if cluster is up
    # Return true if cluster services are up. Raise HANAUpdater::UserError with detailed error
    # description otherwise.
    def cluster_up?
      status = exec_status('which', 'crm')
      raise UserError.new("Could not find the `crm_mon` binary. Cannot proceed.",
        UserError::CRITICAL) unless status.exitstatus == 0
      err, status = exec_outerr_status('crm_mon', '-r1')
      raise UserError, "Could not connect to cluster "\
        "(exit code #{status.exitstatus}): #{err.strip}." unless status.exitstatus == 0
      true
    end

    def hana_resources
      out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
      raise UserError.new("Could not get the CRM configuration: #{out}.",
        UserError::CRITICAL) unless status.exitstatus == 0
      doc = REXML::Document.new(out)
      resources = REXML::XPath.match(doc, '//resource').select do |res|
        res.attributes['resource_agent'] == "ocf::suse:SAPHana" ||
          res.attributes['resource_agent'] == "ocf::suse:SAPHanaTopology"
      end
      resources.map(&:attributes)
    end

    def hana_resources2
      # This method does not show correct situation:
      # when HANA is stopped on hana02, it only returns one running instance on hana01
      # (see fail_r.xml and fail_rn.xml)
      out, status = exec_outerr_status('crm_mon', '-rn', '--as-xml')
      raise UserError.new("Could not get the CRM configuration: #{out}.",
        UserError::CRITICAL) unless status.exitstatus == 0
      doc = REXML::Document.new(out)
      resources = []
      doc.elements.each('crm_mon/nodes/node') do |node|
        hana_rsc = node.elements.find { |r| r.attributes['resource_agent'] == 'ocf::suse:SAPHana' }
        next if hana_rsc.nil?
        hana_attr = hana_rsc.attributes.to_h
        hana_attr["resource_id"] = hana_attr.delete("id")
        hana_attr.merge!(node.attributes)
        hana_attr["node_id"] = hana_attr.delete("id")
        # add the values from the node-specific attributes
        node_attrs = REXML::XPath.first(doc, '/crm_mon/node_attributes/node[@name=$node_name]', {}, {"node_name" => hana_attr['name']})
        unless node_attrs.nil?
          node_attrs.elements.select { |e| e.attributes['name'].start_with?'hana' }.each do |a|
            hana_attr[a.attributes['name']] = a.attributes['value']
          end
        end
        resources << hana_attr
      end
      resources
    end

    def hana_resources3
      out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
      raise UserError.new("Could not get the CRM configuration: #{out}.",
        UserError::CRITICAL) unless status.exitstatus == 0
      doc = REXML::Document.new(out)
      # match all multistate resources that have a child SAPHana  resource
      resources = REXML::XPath.match(doc, '/crm_mon/resources/clone[@multi_state="true" && .resource[@resource_agent="ocf::suse:SAPHana"]]')
    end

    def hana_resources4
      out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
      raise UserError.new("Could not get the CRM configuration: #{out}.",
        UserError::CRITICAL) unless status.exitstatus == 0
      doc = REXML::Document.new(out)
      resources = []
      # loop through all HANA nodes
      REXML::XPath.each(doc,
        '/crm_mon/node_attributes/node[.attribute[starts-with(@name, "hana")]]') do |node|
        node_name = node.attribute('name').value
        node_attrs = Hash[ node.elements.map { |e| [e.attribute('name').value,
          e.attribute('value').value] }]
        r = ResourceC.new(node_name, node_attrs)
        resources << r
      end
      resources
    end

    def hana_resources5
      # Query the CIB via cibadmin -Ql (as in SAPHanaSR-showAttr)
      out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
      raise UserError.new("Could not get the CRM configuration: #{out}.",
        UserError::CRITICAL) unless status.exitstatus == 0
      doc = REXML::Document.new(out)
      resources = []
        # '/cib/configuration/nodes/node[./instance_attributes/nvpair/attribute[starts-with(@name, "hana")]]') do |node|
        #'/cib/configuration/nodes/node[/instance_attributes/nvpair[attribute[starts-with(@name, "hana")]]') do |node|
      REXML::XPath.each(doc, '/cib/configuration/nodes/node[.instance_attributes/nvpair[starts-with(@name, "hana")]]') do |node|
        node_name = node.attribute('name').value
        node_attrs = Hash[ node.elements.map { |e| [e.attribute('name').value,
          e.attribute('value').value] }]
        r = ResourceC.new(node_name, node_attrs)
        resources << r
      end
      resources
    end

    def cluster_check
      out, status = exec_outerr_status('crm_mon', '-r', '--as-xml')
      raise UserError.new("Could not get the CRM configuration: #{out}.",
        UserError::CRITICAL) unless status.exitstatus == 0
      doc = REXML::Document.new(out)
      nodes = []
      REXML::XPath.each(doc, '/crm_mon/nodes/node') do |nd|
        nodes << ClusterNode.new(nd.attributes)
      end

      nodes
    end

    def hana_overview
      nodes = hana_resources4
      primary = nodes.find { |node| node.sr_state == 'PRIM'}
      no_primary = false
      if primary.nil?
        # we don't have a primary in the cluster, something is wrong
        primary = nodes.first
        no_primary = true
      end
      # TODO: rescue here
      secondary = (nodes - [primary]).first

      puts "HANA System Replication".center(80)
      puts "-"*80
      fmt_string = no_primary ? "%49s <??> %25s\n" : "%49s ===> %25s\n"
      printf fmt_string, primary.node.rjust(25), secondary.node.ljust(25)
      puts "-"*80
      instvars = primary.instance_variables
      instvars.each do |ivn|
        # 20 for title, 3 space, 15 value, 6 spaces, 15 value
        printf "%21s | %25s  ||  %25s\n", ResourceC.field_description(ivn),
          primary.instance_variable_get(ivn), secondary.instance_variable_get(ivn)
      end
      true
    end

    def maintenance_mode(node_name, on = true)
      if on
        out, status = exec_outerr_status('crm', 'node', 'maintenance', node_name)
      else
        out, status = exec_outerr_status('crm', 'node', 'ready', node_name)
      end
      return status.exitstatus == 0
    end
  end

  Cluster = ClusterClass.instance
end
