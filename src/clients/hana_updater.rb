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
# Summary: HANA Cluster Updater: HANA configuration
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'hana_update/helpers'
require 'hana_update/hana'
require 'hana_update/cluster3'
require 'hana_update/wizard/base_wizard_page'
require 'hana_update/wizard/cluster_overview_page'
require 'hana_update/wizard/media_selection'
require 'hana_update/wizard/rich_text'
require 'hana_update/exceptions'
require 'hana_update/models/configuration'

module Yast
  class HanaUpdaterClass < Yast::Client
    Yast.import 'UI'
    Yast.import 'Wizard'
    Yast.import 'Sequencer'
    Yast.import 'Popup'
    include Yast::UIShortcuts
    include Yast::Logger
    # include HANAUpdater::Exceptions

    def initialize
      @yast_sequence = {
        "ws_start"       => "welcome_screen",
        "welcome_screen" => {
          abort: :abort,
          next:  'cluster_overview',
          back:  :back
        },
        "cluster_overview"  => {
          abort: :abort,
          next:  'update_medium',
          back:  :back
        },
        'update_medium'  => {
          abort: :abort,
          next:  'update_plan_local',
          back:  :back
        },
        'update_plan_local'  => {
          abort: :abort,
          next:  'update_site_local',
          back:  :back
        },
        'update_site_local'  => {
          abort: :abort,
          next:  'update_plan_remote',
          back:  :back
        },
        'update_plan_remote'  => {
          abort: :abort,
          next:  'update_site_remote',
          back:  :back
        },
        'update_site_remote'  => {
          abort: :abort,
          next:  'finish',
          back:  :back
        },
        'finish'         => {
          abort:  :abort,
          cancel: :abort,
          back:   :back,
          next:   :ws_finish
        }
      }

      @yast_aliases = {
        'welcome_screen' => -> { welcome_screen },
        'cluster_overview'  => -> { cluster_overview },
        'update_medium'  => -> { update_medium },
        'update_plan_local'  => -> { update_plan(:local) },
        'update_plan_remote'  => -> { update_plan(:remote) },
        'update_site_local'  => -> { update_site(:local) },
        'update_site_remote'  => -> { update_site(:remote) },
        'finish'         => -> { show_summary }
      }

      @configuration = HANAUpdater::Configuration.new
    end

    def main
      textdomain 'hana-update'
      @configuration.debug = true if WFM.Args.include?('tst')
      Wizard.CreateDialog
      Wizard.SetDialogTitle("SUSE HANA Cluster Update")
      begin
        Sequencer.Run(@yast_aliases, @yast_sequence)
      ensure
        Wizard.CloseDialog
      end
    end

    def welcome_screen
      HANAUpdater::Wizard::RichText.new.run(
        'Welcome',
        HANAUpdater::Helpers.load_help('welcome_note'),
        '',
        true,
        true
      )
    end

    # def cluster_check
    #   hana_instances = 0
    #   hana_info = []
    #   local_hana = HANAUpdater::Hana.discover
    #   if !local_hana.empty?
    #     hana_instances = local_hana.length
    #     first_hana = local_hana.first
    #   end
    #   begin
    #     cluster_up = HANAUpdater::Cluster.cluster_up?
    #     hana_resources = HANAUpdater::Cluster.hana_resources4
    #     hana_primary = hana_resources.find { |node| node.sr_state == 'PRIM' }
    #     if hana_primary.nil?
    #       replication_on = false
    #     else
    #       hana_secondary = (hana_resources - [hana_primary]).first
    #       replication_on = hana_secondary.sr_state == 'SOK'
    #     end
    #   rescue HANAUpdater::UserError => e
    #     log.error "Cluster status error: #{e.message}"
    #     cluster_up = false
    #     replication_on = false
    #   end
    #   can_continue = cluster_up && replication_on
    #   @hana_primary = hana_primary
    #   @hana_secondary = hana_secondary
    #   @mount_point = 'nfs://f102.suse.de/'

    #   HANAUpdater::Wizard::RichText.new.run(
    #     'System Check',
    #     HANAUpdater::Helpers.render_template('tmpl_cluster_status.erb', binding),
    #     '',
    #     true,
    #     can_continue
    #   )
    # end

    def cluster_overview
      HANAUpdater::Wizard::ClusterOverviewPage.new(@configuration).run
    end

    def update_medium
      HANAUpdater::Wizard::MediaSelectionPage.new(@configuration).run
    end

    # def update_medium
    #   HANAUpdater::Wizard::RichText.new.run(
    #     'Update plan',
    #     HANAUpdater::Helpers.render_template('tmpl_update_plan.erb', binding),
    #     '',
    #     true,
    #     true
    #   )
    # end

    def update_plan(part)
      begin
        content = HANAUpdater::Helpers.render_template('tmpl_update_plan.erb', binding)
      rescue HANAUpdater::Exceptions::TemplateRenderException => e
        log.error "#{e}: #{e.renderer_message}"
        abort
      end
      HANAUpdater::Wizard::RichText.new.run(
        "Update plan (#{part} node)",
        content,
        '',
        true,
        true
      )
    end

    def update_site(node)
      # resource = HANAUpdater::Cluster.find_resource_by_system(@configuration.)
      resource = HANAUpdater::Cluster.selected_system
      
      begin
        content = HANAUpdater::Helpers.render_template('tmpl_update_site.erb', binding)
      rescue HANAUpdater::Exceptions::TemplateRenderException => e
        log.error "#{e}: #{e.renderer_message}"
        abort
      end
      HANAUpdater::Wizard::RichText.new.run(
        "Update site #{site_name}",
        content,
        '',
        true,
        true
      )
    end

    def show_summary
      Yast::Wizard.SetContents(
        'Summary',
        RichText('Here is the summary of the update procedure'),
        '',
        true, true
      )
      Yast::UI.UserInput
    end
  end

  HanaUpdaterClass.new.main
end
