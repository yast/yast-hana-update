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
require 'hana_update/cluster'
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
          next:  'restore_cluster_state',
          back:  :back
        },
        'restore_cluster_state'  => {
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
        'restore_cluster_state'  => -> { restore_cluster },
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

    def cluster_overview
      HANAUpdater::Wizard::ClusterOverviewPage.new(@configuration).run
    end

    def update_medium
      HANAUpdater::Wizard::MediaSelectionPage.new(@configuration).run
    end

    def update_plan(part)
      group = @configuration.system
      local = group.master.local
      remote = group.master.remote
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
      resource = @configuration.system.master.send(node)
      node = resource.running_on
      hdblcm_link = "https://#{node.name}:1129/lmsl/HDBLCM/#{@configuration.system.hana_sid}/index.html"
      # TODO: check node.nil?
      nfs_share_local = '/tmp/dummy/share/change/me'
      begin
        content = HANAUpdater::Helpers.render_template('tmpl_update_site.erb', binding)
      rescue HANAUpdater::Exceptions::TemplateRenderException => e
        log.error "#{e}: #{e.renderer_message}"
        abort
      end
      input = HANAUpdater::Wizard::RichText.new.run(
        "Update site #{node.name}",
        content,
        '',
        true,
        true
      )
      while true
        log.error "UPDATE_SITE: input=#{input.inspect}"
        if input == 'hdblcm_web'
          HANAUpdater::Helpers.open_url(hdblcm_link)
        else
          return input
        end
        input = Yast::UI.UserInput
      end
    end

    def restore_cluster
      group = @configuration.system
      local = group.master.local
      remote = group.master.remote
      begin
        content = HANAUpdater::Helpers.render_template('tmpl_restore_cluster.erb', binding)
      rescue HANAUpdater::Exceptions::TemplateRenderException => e
        log.error "#{e}: #{e.renderer_message}"
        abort
      end
      input = HANAUpdater::Wizard::RichText.new.run(
        "Restore original cluster state",
        content,
        '',
        true,
        true
      )
    end

    def show_summary
      Yast::Wizard.SetContents(
        'Summary',
        RichText('HANA was successfully updated'),
        '',
        true, true
      )
      Yast::UI.UserInput
    end
  end

  HanaUpdaterClass.new.main
end
