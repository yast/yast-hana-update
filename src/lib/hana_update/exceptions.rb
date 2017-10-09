module HANAUpdater
  module Exceptions

    class BaseException < StandardError
    end

    # Errors to display in GUI
    class UserError < StandardError
      attr_reader :level
      WARNING = 2
      ERROR = 3
      CRITICAL = 4

      def initialize(msg, level = ERROR)
        prefix = {2 => 'Warning', 3 => 'Error', 4 => 'Critical'}.fetch(level, 'Info')
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

  end
end
