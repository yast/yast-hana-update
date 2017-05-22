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
# Summary: SUSE High Availability Setup for SAP Products: Base List Selection view
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
# require 'hana_update/helpers'
# require 'sap_ha/exceptions'

module HANAUpdater
  module Wizard
    # Simple List Selection page
    class ListSelection < BaseWizardPage
      def initialize
        super(nil)
      end

      def run(title, message, list_contents, help, allow_back, allow_next)
        base_list_selection(title, message, list_contents, help, allow_back, allow_next)
        ret = Yast::UI.WaitForEvent
        return :next unless ret # allow for debugging
        # Allow for double-clicking the item in the list
        while ret['ID'] == :selection_box
          return :next if ret['EventReason'] == 'Activated'
          ret = Yast::UI.WaitForEvent
        end
        ret['ID']
      end
    end
  end
end
from sklearn.preprocessing import LabelEncoder