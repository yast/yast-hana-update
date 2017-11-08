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
# Summary: SAP HANA updater in a SUSE cluster: Update Summary Page
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
# require 'hana_update/exceptions'

module HANAUpdater
  module Wizard
    # Update Summary Page
    class SummaryPage < BaseWizardPage
      def initialize(configuration)
        super(configuration)
      end

      def run
        hana_instances = @model.hana_update_overview
        attr_output = HANAUpdater::System.saphanasr_attributes(@model.system.hana_sid)
        if Yast::UI.TextMode
          unless hana_instances.nil?
            hana_instances = hana_instances.map(&:values)
            hana_instances.insert(0, ['Host Name', 'Site Name', 'Original Version', 'New Version'])
            hana_instances = HANAUpdater::Helpers.array_to_table(hana_instances)
          end
          attr_output = HANAUpdater::Helpers.array_to_table(attr_output) unless attr_output.nil?
        end
        contents = HANAUpdater::Helpers.render_template('summary', binding)
        base_rich_text('Update Summary', contents, '', false, true)
        Yast::Wizard.SetNextButton(:finish, '&Finish')
        Yast::UI.UserInput
      end
    end
  end
end
