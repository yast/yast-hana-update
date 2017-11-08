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
# Summary: SAP HANA updater in a SUSE cluster
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

module HANAUpdater
  module Exceptions
    # Base Exception class
    class BaseException < StandardError
    end

    # Errors to display in GUI
    class UserError < StandardError
      attr_reader :level
      WARNING = 2
      ERROR = 3
      CRITICAL = 4

      def initialize(msg, level = ERROR)
        prefix = { 2 => 'Warning', 3 => 'Error', 4 => 'Critical' }.fetch(level, 'Info')
        my_msg = "#{prefix}: #{msg}"
        super(my_msg)
        @level = level
      end
    end

    # Exception to interrupt GUI loop processing
    class AbortGUILoop < RuntimeError
      attr_reader :sequencer_sym

      def initialize(msg, sequencer_sym)
        super(msg)
        @sequencer_sym = sequencer_sym
      end
    end

    # Exception that passes the ERB renderer error text
    class TemplateRenderException < StandardError
      attr_accessor :renderer_message
    end

    class SSHException < BaseException
    end

    class SSHConnectionException < SSHException
    end

    class SSHAuthException < SSHException
    end

    class SSHPassException < SSHException
    end

    class SSHKeyException < SSHException
    end

    class ClusterConfigurationError < StandardError
    end
  end
end
