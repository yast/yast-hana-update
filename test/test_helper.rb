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

require 'etc'
require 'ostruct'

# Set the paths
ENV['Y2DIR'] = File.expand_path('../../src', __FILE__)

if ENV["COVERAGE"]
  require "simplecov"

  # additionally use the LCOV format for on-line code coverage reporting at CI
  if ENV["CI"] || ENV["COVERAGE_LCOV"]
    require "simplecov-lcov"

    SimpleCov::Formatter::LcovFormatter.config do |c|
      c.report_with_single_file = true
      # this is the default Coveralls GitHub Action location
      # https://github.com/marketplace/actions/coveralls-github-action
      c.single_report_path = "coverage/lcov.info"
    end

    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::LcovFormatter
    ]
  end

  src_location = File.expand_path("../src", __dir__)
  # track all ruby files under src
  SimpleCov.track_files("#{src_location}/**/*.rb")

  SimpleCov.start do
    add_filter "/test/"
  end
end

# configure RSpec
RSpec.configure do |config|
  config.mock_with :rspec do |c|
    # https://relishapp.com/rspec/rspec-mocks/v/3-0/docs/verifying-doubles/partial-doubles
    c.verify_partial_doubles = true
  end
end

require 'yast'

def build_service?
  Etc.getlogin == 'abuild'
end

def user_root?
  Process.uid == 0
end

def test_file(name)
  File.read("#{File.dirname(__FILE__)}/data/#{name}")
end

def expect_syscall(opts = { type: :status })
  raise ArgumentError, 'You have to specify :cmd to test_syscall' if opts[:cmd].nil?
  raise ArgumentError, ':type should be either :status or :output' \
    unless [:status, :output].include? opts[:type]
  case opts[:type]
  when :status
    method = :popen3
    ret = double('ExitStatus', exitstatus: opts[:rc])
  when :output
    method = :capture2e
    ret = [opts[:output] || '', double('ExitStatus', exitstatus: opts[:rc])]
  else
    raise ArgumentError
  end
  expect(Open3).to receive(method).with(*opts[:cmd]).and_return(ret)
end

class Constants
  attr_reader :system, :local, :remote, :replication_modes, :operation_modes, :resources

  def initialize
    @system = OpenStruct.new(id: 'PRD', instance: '00', user: 'prdadm')
    @local = OpenStruct.new(host_name: 'hana01', site_name: 'NUREMBERG')
    @remote = OpenStruct.new(host_name: 'hana02', site_name: 'PRAGUE')
    @operation_modes = %w(delta_datashipping logreplay logreplay_readaccess)
    @replication_modes = %w(syncmem sync async)
    @resources = { msl: 'msl_SAPHana_PRD_HDB00', cln: 'cln_SAPHanaTopology_PRD_HDB00',
      vip: 'rsc_ip_PRD_HDB00' }
  end
end
