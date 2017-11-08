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
# Summary: SAP HANA updater in a SUSE cluster: YaST client
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

module HANAUpdater
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
          'ws_start' => 'welcome_screen',
          'welcome_screen' => {
              abort: :abort,
              next: 'cluster_overview',
              back: :back
          },
          'cluster_overview' => {
              abort: :abort,
              next: 'update_medium',
              back: :back
          },
          'update_medium' => {
              abort: :abort,
              next: 'update_plan_local',
              back: :back
          },
          'update_plan_local' => {
              abort: :abort,
              next: 'update_site_local',
              back: :back
          },
          'update_site_local' => {
              abort: :abort,
              next: 'update_plan_remote',
              back: :back
          },
          'update_plan_remote' => {
              abort: :abort,
              next: 'update_site_remote',
              back: :back
          },
          'update_site_remote' => {
              abort: :abort,
              next: 'restore_cluster_state',
              back: :back
          },
          'restore_cluster_state' => {
              abort: :abort,
              next: 'summary',
              back: :back
          },
          'summary' => {
              abort: :abort,
              cancel: :abort,
              finish: :ws_finish
          }
      }

      @yast_aliases = {
          'welcome_screen' => -> {welcome_screen},
          'cluster_overview' => -> {cluster_overview_page},
          'update_medium' => -> {update_medium_page},
          'update_plan_local' => -> {update_plan_page(:local)},
          'update_plan_remote' => -> {update_plan_page(:remote)},
          'update_site_local' => -> {update_hana_page(:local)},
          'update_site_remote' => -> {update_hana_page(:remote)},
          'restore_cluster_state' => -> {update_plan_page(:restore)},
          'summary' => -> {show_summary}
      }

      @configuration = HANAUpdater::Configuration.new
    end

    def main
      textdomain('hana-update')
      @configuration.debug = true if WFM.Args.include?('dbg')
      if Yast::WFM.Args.include? 'skipto'
        step_ix = Yast::WFM.Args.index('skipto') + 1
        @yast_sequence['ws_start'] = Yast::WFM.Args[step_ix]
      end
      if Yast::WFM.Args.include? 'setsys'
        step_ix = Yast::WFM.Args.index('setsys') + 1
        HANAUpdater::Cluster.update_state
        @configuration.select_hana_system(Yast::WFM.Args[step_ix].upcase)
      end
      Yast::Wizard.CreateDialog
      Yast::Wizard.SetDialogTitle('SUSE SAP HANA Cluster Update')
      begin
        Sequencer.Run(@yast_aliases, @yast_sequence)
      ensure
        Yast::Wizard.CloseDialog
      end
    end

    def welcome_screen
      Wizard::RichText.new.run(
          'Welcome',
          HANAUpdater::Helpers.load_help('welcome_note'),
          '',
          false,
          true
      )
    end

    def cluster_overview_page
      Wizard::ClusterOverviewPage.new(@configuration).run
    end

    def update_medium_page
      Wizard::MediaSelectionPage.new(@configuration).run
    end

    def update_plan_page(part)
      input = Wizard::UpdatePlanPage.new(@configuration, part).run
      if input == :next
        Executor.instance.execute_update_plan(part, @configuration)
      elsif input == :skip
        return :next
      end
      input
    end

    def update_hana_page(part)
      input = Wizard::UpdateHanaPage.new(@configuration).run(part)
      return :next if input == :skip
      input
    end

    def show_summary
      Wizard::SummaryPage.new(@configuration).run
    end
  end
end
