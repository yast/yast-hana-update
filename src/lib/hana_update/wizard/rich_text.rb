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
# Summary: SAP HANA updater in a SUSE cluster: Base Rich Text view
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
# require 'hana_update/exceptions'

module HANAUpdater
  module Wizard
    # Simple RichText page
    class RichText < BaseWizardPage
      def initialize(opts={})
        super(nil)
        @allow_skip = opts[:allow_skip] || false
      end

      def run(title, contents, help, allow_back=true, allow_next=true)
        base_rich_text(title, contents, help, allow_back, allow_next)
        if @allow_skip
          Yast::Wizard.SetBackButton(:skip, '&Skip')
        end
        input = Yast::UI.UserInput
        # Restore the "back button"
        Yast::Wizard.SetBackButton(:back, '&Back') if @allow_skip
        input
      end
    end
  end
end
