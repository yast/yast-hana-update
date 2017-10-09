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

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start
end

require 'yast'

def build_service?
  Etc.getlogin == "abuild"
end

def user_root?
  Process.uid == 0
end

def test_file(name)
  File.read("#{File.dirname(__FILE__)}/data/#{name}")
end

class Constants
  attr_reader :system, :local, :remote, :replication_modes, :operation_modes
  def initialize
    @system = OpenStruct.new(id: 'PRD', instance: '00', user: 'prdadm')
    @local = OpenStruct.new(host_name: 'hana01', site_name: 'NUREMBERG')
    @remote = OpenStruct.new(host_name: 'hana02', site_name: 'PRAGUE')
    @operation_modes = %w(delta_datashipping logreplay logreplay_readaccess)
    # @operation_modes = {delta: 'delta_datashipping', log: 'logreplay', logr: 'logreplay_readaccess'}
    @replication_modes = %w(syncmem sync async)
    # @replication_modes = {sm: 'syncmem', s: 'sync', a: 'async'}
  end
end