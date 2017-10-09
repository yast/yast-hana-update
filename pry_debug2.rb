# Debugging
require 'pry'
require 'yaml'
require 'rexml/document'
require 'rexml/xpath'

ENV['Y2DIR'] = File.expand_path('../src', __FILE__)

require 'yast'
require 'hana_update/hana'
require 'hana_update/cluster'
require 'hana_update/ssh'
require 'hana_update/shell_commands'
include HANAUpdater::ShellCommands

# hanas = HANAUpdater::Hana.discover()

# puts "HANA discovered? #{!hanas.empty?}"

# unless hanas.empty?

# end

# puts "HANA XXX:10 is running? #{HANAUpdater::Hana.check_hdb_daemon_running('XXX', 10)}"

binding.pry

puts nil