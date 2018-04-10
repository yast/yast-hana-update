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
# Summary: SAP HANA updater in a SUSE cluster: Update Media Selection Page
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'hana_update/wizard/base_wizard_page'
require 'hana_update/cluster'

module HANAUpdater
  module Wizard
    # Cluster Overview Page
    class MediaSelectionPage < BaseWizardPage
      def initialize(model)
        super(model)
        @page_validator = -> { model.validate(:nfs_share, :verbose) }
      end

      def set_contents
        super
        Yast::Wizard.SetContents(
          _('Step 2 of 7. Update medium'),
          base_layout(
            VBox(
              VSpacing(1),
              Left(CheckBox(Id(:hana1to2), Opt(:notify), 
                _('This is a HANA 1.0 to HANA 2.0 &upgrade'))),
              VSpacing(1),
              Left(Label(_('Mount and copy SAP HANA update medium?'))),
              RadioButtonGroup(Id(:rbg),
                VBox(
                  Left(RadioButton(Id(:rb_manual), Opt(:notify),
                    'Do not mount an update medium', true)),
                  Left(RadioButton(Id(:rb_auto), Opt(:notify),
                    'Mount an update medium on all hosts', false))
                )
                              ),
              TextEntry(Id(:hana_medium), 'NFS share:'),
              Left(CheckBox(Id(:copy_medium), Opt(:notify), 'Copy update medium locally')),
              TextEntry(Id(:copy_path), 'Local path:'),
              VSpacing(Opt(:vstretch))
            )
          ),
          Helpers.load_help('media_selection'),
          true,
          true
        )
      end

      def can_go_next?
        model.validate(:nfs_share, :silent)
      end

      def refresh_view
        super
        log.debug "--- #{self.class}.#{__callee__} : refresh, params #{model.nfs_share} ---"
        flag = model.nfs.should_mount?
        set_value(:rb_manual, !flag)
        set_value(:rb_auto, flag)
        set_value(:hana_medium, flag, :Enabled)
        set_value(:hana_medium, model.nfs.source)
        set_value(:copy_medium, flag, :Enabled)
        set_value(:copy_medium, model.nfs.copy_medium?)
        set_value(:copy_path, flag && model.nfs.copy_medium?, :Enabled)
        set_value(:copy_path, model.nfs.copy_path)
        set_value(:hana1to2, model.hana1to2)
      end

      def update_model
        log.debug "--- called #{self.class}.#{__callee__} ---"
        model.nfs.should_mount = value(:rb_auto)
        model.nfs.source = value(:hana_medium)
        model.nfs.copy_medium = value(:copy_medium)
        model.nfs.copy_path = value(:copy_path)
        model.hana1to2 = value(:hana1to2)
        log.debug "--- #{self.class}.#{__callee__} : nfs_share=#{model.nfs.inspect} ---"
      end

      def handle_user_input(input, event)
        log.info "--- #{self.class}.#{__callee__}:"\
                 " Handling user input=#{input.inspect}, event=#{event.inspect} ---"
        case input
        when :rb_manual
          set_value(:hana_medium, false, :Enabled)
          set_value(:copy_medium, false, :Enabled)
          set_value(:copy_path, false, :Enabled)
        when :rb_auto
          set_value(:hana_medium, true, :Enabled)
          set_value(:copy_medium, true, :Enabled)
          set_value(:copy_path, value(:copy_medium), :Enabled)
        when :copy_medium
          set_value(:copy_path, value(:copy_medium), :Enabled)
        else
          log.warn "--- #{self.class}.#{__callee__}:"\
                   " Unexpected user input=#{input.inspect}, event=#{event.inspect} ---"
        end
      end
    end
  end
end
