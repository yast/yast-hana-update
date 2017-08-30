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
    class MediaSelectionPage < BaseWizardPage
      def initialize(model)
        super(model)
      end

      def set_contents
        super
        Yast::Wizard.SetContents(
          _('Update medium'),
          base_layout_with_label(
            _('Mount and copy SAP HANA update medium?'),
            VBox(
              RadioButtonGroup(Id(:rbg),
                VBox(
                  Left(RadioButton(Id(:rb_manual), Opt(:notify), 'Do not mount an update medium', true)),
                  Left(RadioButton(Id(:rb_auto), Opt(:notify), 'Mount an update medium on all hosts', false))
                )
              ),
              TextEntry(Id(:hana_medium), 'NFS share:'),
              Left(CheckBox(Id(:copy_medium), Opt(:notify), 'Copy update medium to a local path')),
              TextEntry(Id(:copy_path), 'Local path:')
            )
          ),
          Helpers.load_help('stub'),
          true,
          true
        )
      end

      def can_go_next?
        @model.validate(:nfs_share)
      end

      def refresh_view
        super
        log.debug "Refreshing MediaSelectionPage: :rb_auto is #{value(:rb_auto)}"
        # handle radiobuttons and stuff
        log.debug "--- #{self.class}.#{__callee__} : refresh, params #{@model.nfs_share} ---"
        
        flag = @model.mount_nfs
        set_value(:rb_manual, !flag)
        set_value(:rb_auto, flag)
        set_value(:hana_medium, flag, :Enabled)
        set_value(:hana_medium, @model.nfs_source)
        set_value(:copy_medium, flag, :Enabled)
        set_value(:copy_medium, @model.copy_medium)
        set_value(:copy_path, flag && @model.copy_medium, :Enabled)
        set_value(:copy_path, @model.nfs_copy_path)
      end

      def update_model
        @model.mount_nfs = value(:rb_auto)
        @model.nfs_source = value(:hana_medium)
        @model.copy_medium = value(:copy_medium)
        @model.nfs_copy_path = value(:copy_path)
        log.debug "--- #{self.class}.#{__callee__} : nfs_share=#{@model.nfs_share.inspect} ---"
      end

      def handle_user_input(input, event)
        log.info "--- #{self.class}.#{__callee__} : Handling user input=#{input.inspect}, event=#{event.inspect} ---"
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
        when :hana_medium
          log.info "--- #{self.class}.#{__callee__} : Unexpected user input=#{input.inspect}, event=#{event.inspect} ---"
        else
        log.warn "--- #{self.class}.#{__callee__} : Unexpected user "\
        "input=#{input.inspect}, event=#{event.inspect} ---"
        end
      end
    end
  end
end
