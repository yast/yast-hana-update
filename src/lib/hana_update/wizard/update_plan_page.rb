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
    # Simple RichText page
    class UpdatePlanPage < BaseWizardPage
      def initialize(config)
        super(config)
      end

      def run(part)
        group = model.system
        local = group.master.local
        remote = group.master.remote
        step_no = {local: 3, remote: 5, restore: 7}[part] || '?'
        content, help = render(part, binding)
        base_rich_text(
            "Step #{step_no} of 7. Update plan (#{part} node)",
            content,
            help,
            true,
            true
        )
        Yast::Wizard.SetBackButton(:skip, '&Skip')
        input = Yast::UI.UserInput
        # Restore the "back button"
        Yast::Wizard.SetBackButton(:back, '&Back')
        input
      end

      def render(part, binding_)
        file_name = case part
                      when :local, :remote
                        'tmpl_update_plan.erb'
                      when :restore
                        'tmpl_restore_cluster.erb'
                      else
                        raise ArgumentError, "Unknown part #{part}"
                    end
        begin
          content = HANAUpdater::Helpers.render_template(file_name, binding_)
        rescue HANAUpdater::Exceptions::TemplateRenderException => e
          log.error "#{e}: #{e.renderer_message}"
          abort
        end
        help = '' # TODO: write help
        return content, help
      end
    end
  end
end
