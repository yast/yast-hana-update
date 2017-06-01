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
require 'hana_update/cluster'

module HANAUpdater
  module Wizard
    # Cluster Overview Page
    class ClusterOverviewPage < BaseWizardPage
      def initialize(model)
        super(model)
        @show_errors = true
        @can_continue = true
        @page_validator = model.method(:validate_system)
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
            HANAUpdater::Cluster.update_state
          rescue RuntimeError => e
            raise AbortGUILoop.new(e.message, :abort)
          end

        end
      end

      def refresh_view
        super
        contents = @model.hana_sys_table_items
        Yast::UI.ReplaceWidget(Id(:rp_content), hana_systems_table)
        set_value(:hana_systems_table, contents, :Items)
        item_id = value(:hana_systems_table)
        sys_name = contents[item_id][1]
        set_value(:sys_descr, "Selected HANA system: #{sys_name}")
      end

      def hana_systems_table
        VBox(
          Table(
            Id(:hana_systems_table),
            Opt(:keepSorting, :notify, :immediate),
            Header(_('System ID'), _('Instance'), _('Nodes')),
            []
          ),
          MinSize(55, 1, Label(Id(:sys_descr), ''))
        )
      end

      def update_model
        contents = @model.hana_sys_table_items
        item_id = value(:hana_systems_table)
        @model.select_hana_system(contents[item_id][1], contents[item_id][2])
      end

      def handle_user_input(input, event)
        case input
        when :hana_systems_table
          if event['EventReason'] == 'SelectionChanged'
            item_id = value(:hana_systems_table)
            sys_name = @model.hana_sys_table_items[item_id][2]
            set_value(:sys_descr, "Selected system: #{sys_name}")
          end
        else
          super
        end
      end
    end
  end
end
