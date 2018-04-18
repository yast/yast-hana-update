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
# Summary: SAP HANA updater in a SUSE cluster: Cluster Nodes Configuration Page
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
      end

      def set_contents
        super
        Yast::Wizard.SetContents(
          _('Step 1 of 7. Select an SAP HANA system'),
          base_layout_with_label(
            _('Select the system to update'),
            VBox(
              ReplacePoint(Id(:rp_content), Empty())
            )
          ),
          Helpers.load_help('select_system'),
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
          rescue Exceptions::ClusterConfigurationError => e
            raise AbortGUILoop.new(e.message, :noclu)
          end
          if !HANAUpdater::Cluster.warnings.empty?
            html_message = "<ul>" +
              HANAUpdater::Cluster.warnings.uniq.map { |el| "<li>#{el}</li>" }.join("\n") + "</ul>"
            show_message(html_message, 'Warning')
          end
        end
      end

      def refresh_view
        super
        Yast::UI.ReplaceWidget(Id(:rp_content), hana_systems_table)
        set_value(:hana_systems_list, @model.hana_sids, :Items)
        selected_id = value(:hana_systems_list, :CurrentItem)
        log.debug "--- #{self.class}.#{__callee__}: "\
                  " @model.hana_sids=#{@model.hana_sids.inspect} --- "
        log.debug "--- #{self.class}.#{__callee__} :: selected_id=#{selected_id.inspect} --- "
        sys = @model.get_system_by_sid(selected_id)
        set_value(:hana_system_table, @model.hana_sys_table_items(sys), :Items)
      end

      def hana_systems_table
        VBox(
          MinHeight(3,
            SelectionBox(
              Id(:hana_systems_list),
              Opt(:keepSorting, :notify, :immediate),
              'Available SAP HANA Systems:',
              []
            )
                   ),
          Left(Label('Selected System:')),
          MinHeight(10,
            Table(
              Id(:hana_system_table),
              Opt(:keepSorting, :notify, :immediate),
              Header('Host Name', 'Site Name', 'SAP HANA Version', 'Resource Role'),
              []
            )
                   )
        )
      end

      def update_model
        # contents = @model.hana_sys_table_items
        item_id = value(:hana_systems_list, :CurrentItem)
        log.debug "--- #{self.class}.#{__callee__} :: current item is #{item_id.inspect} --- "
        @model.select_hana_system(item_id)
      end

      def handle_user_input(input, event)
        case input
        when :hana_systems_list
          if event['EventReason'] == 'SelectionChanged'
            selected_id = value(:hana_systems_list, :CurrentItem)
            sys = @model.get_system_by_sid(selected_id)
            set_value(:hana_system_table, @model.hana_sys_table_items(sys), :Items)
          end
        else
          super
        end
      end
    end
  end
end
