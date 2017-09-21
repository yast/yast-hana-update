# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE Linux GmbH, Nuremberg, Germany.
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
    class UpdateSummaryPage < BaseWizardPage
      def initialize(config)
        super(config)
      end

      def run

        resource = model.system.master.send(part)
        node = resource.running_on
        hdblcm_link = "https://#{node.name}:1129/lmsl/HDBLCM/#{model.system.hana_sid}/index.html"
        begin

          content = HANAUpdater::Helpers.render_template('tmpl_update_site.erb', binding)
        rescue HANAUpdater::Exceptions::TemplateRenderException => e
          log.error "#{e}: #{e.renderer_message}"
          abort
        end
        begin
          help_msg = HANAUpdater::Helpers.render_template('tmpl_help_update_step.erb', binding)
        rescue HANAUpdater::Exceptions::TemplateRenderException => e
          log.error "#{e}: #{e.renderer_message}"
          abort
        end
        title = "Step #{step_no} of 7. Update node #{node.name}"
        base_rich_text(title, content, help_msg, true, true)
        Yast::UI.UserInput
      end
    end
  end
end
