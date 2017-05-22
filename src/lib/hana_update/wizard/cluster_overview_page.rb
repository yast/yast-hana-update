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
# Summary: SUSE High Availability Setup for SAP Products: Cluster Nodes Configuration Page
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'hana_update/wizard/base_wizard_page'
require 'hana_update/cluster3'

module HANAUpdater
  module Wizard
    # Cluster Overview Page
    class ClusterOverviewPage < BaseWizardPage
      def initialize(model)
        super(model)
        @show_errors = true
        @can_continue = true
        # HANAUpdater::Cluster.update_state
      end

      def set_contents
        super
        Yast::Wizard.SetContents(
          _('Cluster overview'),
          base_layout_with_label(
            _('Select the system for update'),
            VBox(
              ReplacePoint(Id(:rp_content), Empty())
            )
          ),
          Helpers.load_help('stub'),
          true,
          true
        )
      end

      def before_refresh
        Yast::Popup.Feedback('Please wait', 'Querying cluster state') do
          begin
            HANAUpdater::Cluster.update_state # TODO: move somewhere            
          rescue RuntimeError => e
            raise AbortGUILoop.new(e.message, :abort)
          end

        end
      end

      def can_go_next?
        # return true if @model.no_validators
        # return false unless @my_model.configured?
        # Yast::Popup.Feedback('Please wait', 'Checking SSH connection') do
        #   unless check_ssh_connectivity
        #     @show_errors = false
        #     return false
        #   end
        # end
        # true
        @can_continue
      end

      def show_errors?
        # old = @show_errors
        # @show_errors = true
        # old
        @show_errors
      end

      def refresh_view
        super
        # continue, contents = HANAUpdater::Cluster.cluster_overview
        # contents = HANAUpdater::Cluster.get_resource_table
        contents = @model.hana_sys_table_items
        # if !continue
        #   Yast::UI.ReplaceWidget(Id(:rp_content), RichText(Helpers.load_help('no_cluster')))
        #   @can_continue = false
        #   Yast::Wizard.DisableNextButton
        # else
        Yast::UI.ReplaceWidget(Id(:rp_content), hana_systems_table)
        set_value(:hana_systems_table, contents, :Items)
        item_id = value(:hana_systems_table)
        sys_name = contents[item_id][2]
        set_value(:sys_descr, "Selected HANA system: #{sys_name}")
        # end
      end

      def hana_systems_table
        VBox(
          Table(
            Id(:hana_systems_table),
            Opt(:keepSorting, :notify, :immediate),
            # Header(_('Host name'), _('System'), _('Site name'), _('HANA version'), _('RA role')),
            Header(_('Host name'), _('SID'), _('Inst.'), _('Site name'), _('HANA version'), _('RA role')),
            []
          ),
          MinSize(55, 1, Label(Id(:sys_descr), ''))
        )
      end

      def update_model
        @model.select_hana_system(value(:hana_systems_table))
      end

      def handle_user_input(input, event)
        case input
        when :hana_systems_table
          if event['EventReason'] == 'SelectionChanged'
            item_id = value(:hana_systems_table)
            sys_name = @model.hana_sys_table_items[item_id][2]
            set_value(:sys_descr, "Selected system: #{sys_name}")
          end
        when :edit_node
          update_model
          edit_node
        when :node_definition_table
          update_model
          edit_node if event['EventReason'] == 'Activated'
        when :append_hosts
          @my_model.append_hosts = value(:append_hosts)
        else
          super
        end
      end

      # def edit_node
      #   item_id = value(:node_definition_table)
      #   values = node_configuration_popup(@my_model.nodes[item_id])
      #   if !values.nil? && !values.empty?
      #     @my_model.update_node(item_id, values)
      #     refresh_view
      #   end
      # end

      # def node_configuration_popup(values)
      #   log.debug "--- #{self.class}.#{__callee__} --- "
      #   base_popup(
      #     "Configuration for node #{values[:node_id]}",
      #     @my_model.method(:node_validator),
      #     MinWidth(15, InputField(Id(:host_name), 'Host name:', values[:host_name] || "")),
      #     MinWidth(15, InputField(Id(:ip_ring1), 'IP in ring #1:', values[:ip_ring1] || "")),
      #     @my_model.number_of_rings == 2 ? MinWidth(15, InputField(Id(:ip_ring2),
      #       'IP in ring #2:', values[:ip_ring2] || "")) : Empty(),
      #     # InputField(Id(:node_id), 'Node ID:', values[:node_id] || "")
      #   )
      # end

      # def check_ssh_connectivity
      #   @my_model.other_nodes.each do |ip|
      #     begin
      #       SapHA::System::SSH.instance.check_ssh(ip)
      #     rescue SSHAuthException => e
      #       log.error e.message
      #       password = password_prompt("Password is required for node #{ip}:")
      #       return false if password.nil?
      #       begin
      #         SapHA::System::SSH.instance.check_ssh_password(ip, password)
      #       rescue SSHAuthException => e
      #         # Yast::Popup.Error(e.message)
      #         show_message(e.message, 'Error')
      #         return false
      #       rescue SSHException => e
      #         # Yast::Popup.Error(e.message)
      #         show_message(e.message, 'Error')
      #         return false
      #       else
      #         SapHA::System::SSH.instance.copy_keys_to(ip, password)
      #       end
      #     rescue SSHException => e
      #       # Yast::Popup.Error(e.message)
      #       show_message(e.message, 'Error')
      #       return false
      #     end
      #     true
      #   end
      # end
    end
  end
end
