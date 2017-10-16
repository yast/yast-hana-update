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
# Summary: SAP HANA updater in a SUSE cluster: Cluster Update Page
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
# require 'hana_update/exceptions'

module HANAUpdater
  module Wizard
    # Cluster Update Page
    class UpdatePlanPage < BaseWizardPage
      attr_accessor :part
      def initialize(config, part)
        @part = part
        super(config)
      end

      def set_contents
        step_no = {local: 3, remote: 5, restore: 7}[@part] || '?'
        short_descr = {local: 'local node', remote: 'remote node', restore: 'restore cluster state'}[@part] || '?'
        content, help = render
        base_rich_text(
            "Step #{step_no} of 7. Update plan (#{short_descr})",
            content,
            help,
            true,
            true
        )
        Yast::Wizard.SetBackButton(:skip, '&Skip')
      end

      def after_main_loop
        log.debug "--- called #{self.class}.#{__callee__}.after_main_loop ---"
        Yast::Wizard.SetBackButton(:back, '&Back')
      end

      def render
        group = model.system
        local = group.master.local
        remote = group.master.remote
        file_name = case @part
                      when :local, :remote
                        'update_plan'
                      when :restore
                        'restore_cluster'
                      else
                        raise ArgumentError, "Unknown part #{@part}"
                    end
        begin
          content = HANAUpdater::Helpers.render_template(file_name, binding)
        rescue HANAUpdater::Exceptions::TemplateRenderException => e
          log.error "#{e}: #{e.renderer_message}"
          abort
        end
        help = Helpers.load_help('update_plan')
        return content, help
      end

      def handle_user_input(input, event)
        case input
          when 'revert_sync_direction'
            model.revert_sync_direction = !model.revert_sync_direction
            content, _help = render
            set_value(:rtext, content)
          else
            log.warn "--- #{self.class}.#{__callee__} : Unexpected user input=#{input}, event=#{event} ---"
        end
      end
    end
  end
end
