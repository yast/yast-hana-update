#
# Rake file
#
# Copyright (c) 2017 SUSE Linux GmbH, Nuremberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#

require 'yast/rake'
require 'packaging'

Yast::Tasks.configuration do |conf|
  conf.skip_license_check << /.*desktop$/
  conf.skip_license_check << /.*erb$/
  conf.skip_license_check << /.*yaml$/
  conf.skip_license_check << /.*yml$/
  conf.skip_license_check << /.*html$/
  conf.skip_license_check << /.*rpmlintrc$/
  conf.exclude_files << /pry_debug.*.rb/
  conf.exclude_files << /.rubocop.yml/
  conf.exclude_files << /TODO.md/
  conf.exclude_files << /doc/
  conf.exclude_files << /make_package.sh/
  conf.exclude_files << /test/
  conf.exclude_files << /cluster2.rb/
  conf.exclude_files << /package/
  conf.exclude_files << /test.sh/
  conf.exclude_files << /debug.sh/
  conf.exclude_files << /run/
end

desc 'Run unit tests with coverage.'
task 'coverage' do
  files = Dir['**/test/**/*_{spec,test}.rb']
  sh "export COVERAGE=1; rspec --color --format doc '#{files.join("' '")}'" unless files.empty?
  sh 'xdg-open coverage/index.html'
end

Packaging.configuration do |conf|
  conf.obs_project = 'home:imanyugin:hana_update'
  conf.package_name = 'yast2-hana-update'
  conf.obs_api = 'https://api.suse.de/'
  conf.obs_target = 'SLE_12_SP3'
end

Rake::Task['check:committed'].clear
Rake::Task['check:license'].clear

# namespace :test do
#   desc "Runs unit tests."
#   task "unit" do
#     files = Dir["**/test/**/*_{spec,test}.rb"]
#     sh "rspec --color --format doc '#{files.join("' '")}'" unless files.empty?
#   end
# end
