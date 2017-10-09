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
# Summary: SAP HANA updater in a SUSE cluster: In-memory logger class
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'singleton'
require 'logger'
require 'stringio'
require 'socket'

module HANAUpdater
  # Log info messages, warnings and errors into memory
  class NodeLoggerClass
    include Singleton
    include Yast::Logger

    attr_reader :node_name

    def initialize
      @fd = StringIO.new
      @logger = Logger.new(@fd)
      @logger.level = Logger::INFO
      @node_name = Socket.gethostname
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        date = datetime.strftime('%Y-%m-%d %H:%M:%S')
        severity = 'OUTPUT' if severity == 'ANY'
        "[#{@node_name}] #{date} #{severity.rjust(6)}: #{msg}\n"
      end
      @highest_level = Logger::INFO
    end

    # Append command's stdout/stderr to the log
    # @param [String] str raw output
    def output(str)
      return unless str
      str = str.strip
      str.split("\n").each {|line| log.unknown(line.strip)}
    end

    # Use debug mode
    def set_debug
      @logger.level = Logger::DEBUG
    end

    # Return log as text
    def text
      @fd.flush
      @fd.string
    end

    # Return log as <br>'ed text for ncurses mode
    def text_br
      @fd.flush
      @fd.string.split("\n").join("\n<br>")
    end

    # Return log as HTML
    def html
      to_html(text)
    end

    # Import log from another node
    # @param txt [String] other node's log
    def import(txt)
      @fd.write(txt)
    end

    # Append a summary line to the log
    def summary
      txt = text
      if txt =~ /FATAL:/
        @logger.error 'Overall status: RED. Setup was halted due to a fatal error.'
      elsif txt =~ /ERROR:/
        @logger.error 'Overall status: RED. There were errors during the setup.'
      elsif txt =~ /WARN:/
        @logger.warn 'Overall status: YELLOW. There were warnings during the setup.'
      else
        # elsif txt ~= /INFO:/
        @logger.info 'Overall status: GREEN. There were no errors.'
      end
    end

    # Convert text log to an HTML representation
    def to_html(txt)
      time_rex = '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
      rules = [
          {rex: /^\[(.*)\] (#{time_rex})\s+(OUTPUT): (.*)$/, color: '#808080'}, # gray
          {rex: /^\[(.*)\] (#{time_rex})\s+(DEBUG): (.*)$/, color: '#808080'}, # gray
          {rex: /^\[(.*)\] (#{time_rex})\s+(INFO): (.*)$/, color: '#009900'}, # green
          {rex: /^\[(.*)\] (#{time_rex})\s+(WARN): (.*)$/, color: '#e6b800'}, # yellow
          {rex: /^\[(.*)\] (#{time_rex})\s+(ERROR): (.*)$/, color: '#800000'}, # error
          {rex: /^\[(.*)\] (#{time_rex})\s+(FATAL): (.*)$/, color: '#800000'}, # fatal error
      ]
      lines = txt.split("\n").map do |line|
        rule = rules.find {|r| r[:rex].match(line)}
        if rule
          node, time, level, message = rule[:rex].match(line).captures
          if level == 'OUTPUT'
            "<font color=\"\#a6a6a6\">[#{node}]</font> #{message}"
          else
            "<font color=\"\#a6a6a6\">[#{node}] #{time}</font> "\
            "<font color=\"#{rule[:color]}\"><b>#{level.rjust(6, " ")}</b></font>: #{message}"
          end
        else
          line
        end
      end
      "<html> <head> <style> code { font-family: \"Nimbus Mono L\", \"Monospace\", monospace; }
       </style> </head> <body> <code> #{lines.join("<br>\n")} </code> </body> </html>"
    end

    # Shorthands for logging

    # Log a general fatal error
    def showstopper
      @logger.fatal('Interrupting configuration process due to earlier errors.')
    end

    # Log the status of an operation and, optionally, its output
    # @param [Boolean] status
    # @param [String] msg_if_true
    # @param [String] msg_if_false
    # @param [String] stdout
    def log_status(status, msg_if_true, msg_if_false, stdout = nil, log_output_on_success = false)
      if status
        log.info(msg_if_true)
        output(stdout) if log_output_on_success
      else
        log.error(msg_if_false)
        output(stdout) if stdout
      end
      status
    end

    private

    def method_missing(method, *args, &block)
      unless [:info, :warn, :error, :debug, :unknown, :fatal].include? method
        log.error "Called a non-existing method #{method} on SapHA::NodeLoggerClass"
        return
      end
      log.send(method, *args, &block)
      @logger.send(method, *args, &block)
    end
  end

  NodeLogger = NodeLoggerClass.instance
end
