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
require 'y2hanaupdate'

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
      # if WFM.Args.include? 'skipto'
      #   step_ix = WFM.Args.index('skipto') + 1
      #   @yast_sequence['ws_start'] = WFM.Args[step_ix]
      # end
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
      input = HANAUpdater::Wizard::RichText.new(allow_skip: true).run(
        "Update plan (#{part} node)",
        content,
        '',
        true,
        true
      )
      if input == :next
        if part == :local
          # put resources to maintenance mode
          Yast::Popup.Feedback('Please wait', 'Setting resources to maintenance mode') do
            HANAUpdater::System.resource_maintenance(group.master.id, :on)
            HANAUpdater::System.resource_maintenance(group.clone.id, :on)
            HANAUpdater::System.resource_maintenance(group.vip.id, :on)
          end
          # TODO: this is not necessary?
          # stop HANA on local node
          Yast::Popup.Feedback('Please wait', 'Stopping HANA on local node') do          
            HANAUpdater::Hana.hdb_stop(group.hana_sid)
          end
          # break replication
          Yast::Popup.Feedback('Please wait', 'Breaking system replication') do          
            HANAUpdater::Hana.disable_secondary(group.hana_sid.downcase)
          end
          # mount update medium
          # TODO: only if requested!
          Yast::Popup.Feedback('Please wait', 'Mounting update medium') do
            local_nfs_path = HANAUpdater::System.mount_nfs(@configuration.nfs_source)
            @configuration.nfs_share[part] = local_nfs_path
          end
        elsif part == :remote
            # TODO: what kind of omode should we use here?
            # operation modes for system replication:
            # > delta_datashipping [def]
            # > logreplay
            # TODO: get from cluster attribute hana_<SID>_op_mode
          Yast::Popup.Feedback('Please wait', 'Stopping HANA on local node') do
            HANAUpdater::Hana.hdb_stop(group.hana_sid)
          end
          Yast::Popup.Feedback('Please wait', 'Registering local HANA instance for SR') do
            # cmd_line = HANAUpdater::Hana.enable_secondary_cmd(group.hana_sid, local.running_on.site,
            #   remote.running_on.name, group.hana_inst, local.running_on.instance_attributes['srmode'],
            #   'delta_datashipping')
            # HANAUpdater::SSH.run_command(remote.running_on.name, cmd_line)
            HANAUpdater::Hana.enable_secondary(group.hana_sid, local.running_on.site,
              remote.running_on.name, group.hana_inst, local.running_on.instance_attributes['srmode'],
              'delta_datashipping')
          end
          Yast::Popup.Feedback('Please wait', 'Starting HANA on local node') do
            HANAUpdater::Hana.hdb_start(group.hana_sid)
          end
          # TODO: here we need to wait until replication is finished
          Yast::Popup.Feedback('Please wait', 'Taking over to local site') do
            HANAUpdater::Hana.takeover(group.hana_sid)
          end
        end
      elsif input == :skip
        return :next          
      end
      input
    end

    def update_site(part)
      resource = @configuration.system.master.send(part)
      node = resource.running_on
      hdblcm_link = "https://#{node.name}:1129/lmsl/HDBLCM/#{@configuration.system.hana_sid}/index.html"
      # TODO: check node.nil?
      nfs_share_local = @configuration.nfs_share[part]
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
        elsif input == :skip
          return :next          
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
