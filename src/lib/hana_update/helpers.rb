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
# Summary: SAP HANA updater in a SUSE cluster: common routines
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>
# Authors: Peter Varkoly <varkoly@suse.com>

require "yast/i18n"
require 'erb'
require 'tmpdir'
require 'hana_update/exceptions'

module HANAUpdater
  # Common routines
  class HelpersClass
    include Singleton
    include ERB::Util
    include Yast::Logger
    include Yast::I18n
    include HANAUpdater::Exceptions

    attr_reader :rpc_server_cmd

    FILE_DATE_TIME_FORMAT = '%Y%m%d_%H%M%S'.freeze

    def initialize
      textdomain "hana-update"
      @storage = {}
      if ENV['Y2DIR'] # tests/local run
        @data_path = 'data/'
        @var_path = File.join(Dir.tmpdir, 'yast-hana-update-tmp')
        begin
          Dir.mkdir(@var_path)
        rescue StandardError => e
          log.debug "Cannot create temporary directory: #{e.message}"
        end
      else # production
        @data_path = '/usr/share/YaST2/data/hana_update'
        @var_path = '/var/lib/YaST2/hana_update'
      end
    end

    # Render an ERB template by its name
    def render_template(basename, binding)
      file_name = 'tmpl_' + basename + (Yast::UI.TextMode ? '_con' : '') + '.erb'
      full_path = data_file_path(file_name)
      unless @storage.key? file_name
        template = ERB.new(read_file(full_path), nil, '-')
        @storage[file_name] = template
      end
      begin
        return @storage[file_name].result(binding)
      rescue StandardError => e
        log.error("Error while rendering template '#{full_path}': #{e.message}")
        exc = TemplateRenderException.new("Error rendering template '#{file_name}'.")
        exc.renderer_message = e.message
        raise exc
      end
    end

    def array_to_table(lines)
      max_len = lines.map { |l| l.map(&:length) }.transpose.map(&:max)
      lines.insert(1, max_len.map { |len| '-' * len })
      lines_just = []
      lines.each do |ln|
        a = []
        ln.each_with_index { |el, ix| a << el.ljust(max_len[ix]) }
        lines_just << a
      end
      lines_just.map { |l| l.join(' ') }.join("\n")
    end

    # Load the help file by its name
    def load_help(basename)
      file_name = "help_#{basename}.html"
      unless @storage.key? file_name
        full_path = File.join(@data_path, file_name)
        # TODO: apply the CSS
        contents = read_file(full_path)
        @storage[file_name] = contents
      end
      @storage[file_name]
    end

    # Get the path to the file given its name
    def data_file_path(basename)
      File.join(@data_path, basename)
    end

    def var_file_path(basename)
      File.join(@var_path, basename)
    end

    def itemize_list(l, use_indices = true)
      require 'yast'
      if use_indices
        l.each_with_index.map { |e, i| Yast::Term.new(:item, Yast::Term.new(:id, i), *e) }
      else
        l.each.map { |e| Yast::Term.new(:item, Yast::Term.new(:id, e[0]), *e[1..e.length]) }
      end
    end

    # Write a file to /var/lib/YaST2/sap_ha
    # Use it for logs and intermediate configuration files
    def write_var_file(basename, data, options = {})
      basename = timestamp_file(basename, options[:timestamp])
      file_path = var_file_path(basename)
      File.open(file_path, 'wb') do |fh|
        fh.write(data)
      end
      file_path
    end

    def write_file(path, data)
      begin
        File.open(path, 'wb') do |fh|
          fh.write(data)
        end
      rescue RuntimeError => e
        log.error "Error writing file #{path}: #{e.message}"
        return false
      end
      true
    end

    def open_url(url)
      require 'yast'
      Yast.import 'UI'
      Yast::UI.BusyCursor
      system("xdg-open #{url}")
      sleep 5
      Yast::UI.NormalCursor
    end

    def timestamp_file(basename, timestamp = nil)
      return basename if timestamp.nil?
      ext = File.extname(basename)
      name = File.basename(basename, ext)
      "#{name}_#{Time.now.strftime("%Y%m%d_%H%M%S")}#{ext}"
    end

    def version_comparison(version_target, version_current, cmp = '>=')
      Gem::Dependency.new('', cmp + version_target).match?('', version_current)
    rescue StandardError => e
      log.error "HANA version comparison failed: target=#{version_target},"\
                " current=#{version_current}, cmp=#{cmp}."
      log.error "Gem::Dependency.match? :: #{e.message}"
      return false
    end

    private

    # Read file's contents
    def read_file(path)
      File.read(path)
    rescue Errno::ENOENT => e
      log.error("Could not find file '#{path}': #{e.message}.")
      raise format(_("Program data could not be found (%s). Please reinstall the package.") % path)
    rescue Errno::EACCES => e
      log.error("Could not access file '#{path}': #{e.message}.")
      raise format(_("Program data could not be accessed (%s). Please reinstall the package.") % path)
    end
  end

  Helpers = HelpersClass.instance
end
