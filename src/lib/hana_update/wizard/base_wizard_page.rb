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
# Summary: SUSE High Availability Setup for SAP Products: Base YaST Wizard page
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
# require 'sap_ha/helpers'
require 'hana_update/exceptions'
# require 'sap_ha/semantic_checks'

Yast.import 'Wizard'

module HANAUpdater
  module Wizard
    # Base Wizard page class
    class BaseWizardPage
      Yast.import 'UI'
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include HANAUpdater::Exceptions

      attr_accessor :model

      INPUT_WIDGETS = [:InputField, :TextEntry, :Password, :CheckBox, :SelectionBox,
                       :MultiLineEdit].freeze
      WRAPPING_WIDGETS = { MinWidth: 1, MinHeight: 1, MinSize: 2, Left: 0 }.freeze

      # Initialize the Wizard page
      def initialize(model)
        log.debug "--- called #{self.class}.#{__callee__} ---"
        @model = model
      end

      # Set the Wizard's contents, help and the back/next buttons
      def set_contents
        log.debug "--- called #{self.class}.#{__callee__} ---"
      end

      # GUI waiting screen before the first GUI refresh
      def before_refresh
      end
      
      # Refresh the view, populating the values from the model
      def refresh_view
      end

      # Refresh model, populating the values from the view
      def update_model
      end

      # Return true if the user can proceed to the next screen
      # Use this if additional verification of the data is needed
      def can_go_next?
        true
      end

      # Show the error dialog if model validation failed?
      def show_errors?
        true
      end

      # Handle custom user input
      # @param input [Symbol]
      def handle_user_input(input, event)
        log.warn "--- #{self.class}.#{__callee__} : Unexpected user "\
        "input=#{input.inspect}, event=#{event.inspect} ---"
      end

      # Set the contents of the Wizard's page and run the event loop
      def run
        log.debug "--- #{self.class}.#{__callee__} ---"
        begin
          set_contents
          before_refresh
          refresh_view
          main_loop
        rescue AbortGUILoop => e
          log.error "GUI loop was interrupted: #{e.message}"
          show_message(e.message, 'Error')
          # return whatever was passed in the exception to the Sequencer
          e.sequencer_sym
        end
      end

      protected

      # Run the main input processing loop
      # Ideally, this method should not be redefined (if we lived in a perfect world)
      def main_loop
        log.debug "--- #{self.class}.#{__callee__} ---"
        loop do
          log.debug "--- #{self.class}.#{__callee__} ---"
          event = Yast::Wizard.WaitForEvent
          log.error "--- #{self.class}.#{__callee__}: event=#{event} ---"
          input = event["ID"]
          case input
          # TODO: return only :abort, :cancel and :back from here. If the page needs anything else,
          # it should redefine the main_loop
          when :back, :cancel, :join_cluster
            # @model.write_config if input == :abort || input == :cancel
            update_model
            return input
          when :abort
            return input            
          when :next, :summary
            update_model
            return input if can_go_next?
            show_dialog_errors(@page_validator.call) if show_errors?
          else
            handle_user_input(input, event)
          end
        end
      end

      private

      # Create a Wizard page with just a RichText widget on it
      # @param title [String]
      # @param contents [Yast::UI::Term]
      # @param help [String]
      # @param allow_back [Boolean]
      # @param allow_next [Boolean]
      def base_rich_text(title, contents, help, allow_back, allow_next)
        Yast::Wizard.SetContents(
          title,
          base_layout(
            RichText(contents)
          ),
          help,
          allow_back,
          allow_next
        )
      end

      # Create a Wizard page with a simple list selection
      # @param title [String]
      # @param message [String]
      # @param list_contents [Array[String]]
      # @param help [String]
      # @param allow_back [Boolean]
      # @param allow_next [Boolean]
      def base_list_selection(title, message, list_contents, help, allow_back, allow_next)
        Yast::Wizard.SetContents(
          title,
          base_layout_with_label(
            message,
            SelectionBox(Id(:selection_box), Opt(:vstretch, :notify), '', list_contents)
          ),
          help,
          allow_back,
          allow_next
        )
      end

      # Obtain a property of a widget
      # @param widget_id [Symbol]
      # @param property [Symbol]
      def value(widget_id, property = :Value)
        unless Yast::UI.WidgetExists(Id(widget_id))
          log.error "--- #{self.class}.#{__callee__}: widget with "\
            "ID=#{widget_id} does not exist ---"
        end
        Yast::UI.QueryWidget(Id(widget_id), property)
      end

      def set_value(widget_id, value, property = :Value)
        unless Yast::UI.WidgetExists(Id(widget_id))
          log.error "--- #{self.class}.#{__callee__}: widget with "\
            "ID=#{widget_id} does not exist ---"
        end
        Yast::UI.ChangeWidget(Id(widget_id), property, value)
      end

      # Base layout that wraps all the widgets
      def base_layout(contents)
        log.debug "--- #{self.class}.#{__callee__} ---"
        HBox(
          HSpacing(3),
          # HStretch(),
          contents,
          HSpacing(3)
          # HStretch()
        )
      end

      # Base layout that wraps all the widgets
      def base_layout_with_label(label_text, contents)
        log.debug "--- #{self.class}.#{__callee__} ---"
        base_layout(
          VBox(
            HSpacing(80),
            VSpacing(1),
            Left(Label(label_text)),
            VSpacing(1),
            contents,
            VSpacing(Opt(:vstretch))
          )
        )
      end

      # A dynamic popup showing the message and the widgets.
      # Runs the validators method to check user input
      # @param message [String] a message to display
      # @param validator [Lambda] validation routine
      # @param widgets [Array] widgets to show
      def base_popup(message, validator, *widgets)
        log.debug "--- #{self.class}.#{__callee__} ---"
        Yast::UI.OpenDialog(
          VBox(
            Yast::UI.TextMode ? Heading(message) : Label(message),
            *widgets,
            Yast::Wizard.CancelOKButtonBox
          )
        )
        loop do
          ui = Yast::UI.UserInput
          case ui
          when :ok
            # create a hash {widget_id: fileld_value} for the input widgets
            parameters = {}
            selected_widgets = widgets.select do |w|
              (INPUT_WIDGETS | WRAPPING_WIDGETS.keys).include? w.value
            end
            selected_widgets.each do |w|
              # if the actual widget is wrapped within a size widget, get the inner widget
              if WRAPPING_WIDGETS.keys.include? w.value
                w = w.params[WRAPPING_WIDGETS[w.value]]
              end
              id = w.params.find do |parameter|
                parameter.respond_to?(:value) && parameter.value == :id
              end.params[0]
              parameters[id] = Yast::UI.QueryWidget(Id(id), :Value)
            end
            log.debug "--- #{self.class}.#{__callee__} popup parameters: #{parameters} ---"
            if validator && !@model.no_validators
              ret = SemanticChecks.instance.check_popup(validator, parameters)
              unless ret.empty?
                show_dialog_errors(ret)
                next
              end
            end
            Yast::UI.CloseDialog
            return parameters
          when :cancel
            Yast::UI.CloseDialog
            return nil
          end
        end
      end

      # A dynamic popup showing the message and the widgets.
      # Runs the validators method to check user input
      # @param message [String] a message to display
      # @param validator [Lambda] validation routine
      # @param widgets [Array] widgets to show
      def base_popup_new(message, validator, handlers, *widgets)
        log.debug "--- #{self.class}.#{__callee__} ---"
        Yast::UI.OpenDialog(
          VBox(
            Yast::UI.TextMode ? Heading(message) : Label(message),
            *widgets,
            Yast::Wizard.CancelOKButtonBox
          )
        )
        loop do
          ui = Yast::UI.UserInput
          case ui
          when :ok
            # create a hash {widget_id: fileld_value} for the input widgets
            parameters = {}
            selected_widgets = widgets.select do |w|
              (INPUT_WIDGETS | WRAPPING_WIDGETS.keys).include? w.value
            end
            selected_widgets.each do |w|
              # if the actual widget is wrapped within a size widget, get the inner widget
              if WRAPPING_WIDGETS.keys.include? w.value
                w = w.params[WRAPPING_WIDGETS[w.value]]
              end
              id = w.params.find do |parameter|
                parameter.respond_to?(:value) && parameter.value == :id
              end.params[0]
              parameters[id] = Yast::UI.QueryWidget(Id(id), :Value)
            end
            log.debug "--- #{self.class}.#{__callee__} popup parameters: #{parameters} ---"
            if validator && !@model.no_validators
              ret = SemanticChecks.instance.check_popup(validator, parameters)
              unless ret.empty?
                show_dialog_errors(ret)
                next
              end
            end
            Yast::UI.CloseDialog
            return parameters
          when :cancel
            Yast::UI.CloseDialog
            return nil
          else
            handlers[ui].call() if !handlers.nil? && handlers[ui]
          end
        end
      end

      # Create a true/false combo box
      # @param id_ [Symbol] widget's ID
      # @param label [String] combo's label
      # @param true_ [Boolean] 'true' option is selected
      def base_true_false_combo(id_, label = '', true_ = true)
        ComboBox(Id(id_), Opt(:hstretch), label,
          [
            Item(Id(:true), 'true', true_),
            Item(Id(:false), 'false', !true_)
          ]
        )
      end

      # Prompt the user for the password
      # Do not use base_popup because it logs the input!
      # @param message [String] additional prompt message
      def password_prompt(message)
        Yast::UI.OpenDialog(
          VBox(
            Label(message),
            MinWidth(15, Password(Id(:password), 'Password:', '')),
            Yast::Wizard.CancelOKButtonBox
          )
        )
        ui = Yast::UI.UserInput
        case ui
        when :cancel
          Yast::UI.CloseDialog
          return nil
        when :ok
          pass = value(:password)
          Yast::UI.CloseDialog
          return nil if pass.empty?
          pass
        end
      end

      def show_dialog_errors(error_list, title = "Invalid input")
        log.error "--- #{self.class}.#{__callee__}: #{error_list} ---"
        html_str = "<p>Configuration is invalid or incomplete and the Wizard
          cannot proceed to the next step.</p><p>Please review the following warnings:</p>\n"
        html_str << "<ul>\n"
        html_str << error_list.uniq.map { |e| "<li>#{e}</li>" }.join("\n")
        html_str << "</ul>"
        Yast::Popup.LongText(title, RichText(html_str), 60, 17)
      end

      def show_message(message, title)
        Yast::Popup.LongText(title, RichText(message), 55, 10)
      end

      def two_widget_hbox(widget_one, widget_two, spacing = 2)
        HBox(
          HWeight(1, widget_one),
          HSpacing(spacing),
          HWeight(1, widget_two)
        )
      end
    end
  end
end
