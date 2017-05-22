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
    class MediaSelectionPage < BaseWizardPage
      def initialize(model)
        super(model)
      end

      def set_contents
        super
        Yast::Wizard.SetContents(
          _('Update medium'),
          base_layout_with_label(
            _('Provide a HANA update medium'),
            HBox(
              TextEntry(Id(:hana_medium), 'NFS share:')
            )
          ),
          Helpers.load_help('stub'),
          true,
          true
        )
      end

      def can_go_next?
        # return true if @model.no_validators
        # @model.validate_comm_layer(:silent)
        true
      end

      def refresh_view
        super
        set_value(:hana_medium, @model.nfs_share)
      end

      def update_model
        @model.nfs_share = value(:hana_medium)
      end

      # def handle_user_input(input, event)
      #   case input
      #   when :hana_systems_table
      #     if event['EventReason'] == 'SelectionChanged'
      #       item_id = value(:hana_systems_table)
      #       sys_name = @model.hana_sys_table_items[item_id][2]
      #       set_value(:sys_descr, "Selected system: #{sys_name}")
      #     end
      #   when :edit_node
      #     update_model
      #     edit_node
      #   when :node_definition_table
      #     update_model
      #     edit_node if event['EventReason'] == 'Activated'
      #   when :append_hosts
      #     @my_model.append_hosts = value(:append_hosts)
      #   else
      #     super
      #   end
      # end


    end
  end
end
