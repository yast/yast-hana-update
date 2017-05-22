#
# Rake file
#
# Copyright (c) 2016 SUSE Linux GmbH, Nuernberg, Germany.
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

require "yast/rake"
require "packaging"

Yast::Tasks.configuration do |conf|
  conf.skip_license_check << /.*desktop$/
  conf.skip_license_check << /.*erb$/
  conf.skip_license_check << /.*yaml$/
  conf.skip_license_check << /.*yml$/
  conf.skip_license_check << /.*html$/
  conf.skip_license_check << /.*rpmlintrc$/
  conf.skip_license_check << /pry_debug.rb/
  conf.skip_license_check << /make_package.sh/
  conf.skip_license_check << /srhook.py.tmpl/
  conf.exclude_files << /pry_debug.rb/
  conf.exclude_files << /.rubocop.yml/
  conf.exclude_files << /TODO.md/
  conf.exclude_files << /doc/
  conf.exclude_files << /make_package.sh/
  conf.exclude_files << /test/
end

desc "Run unit tests with coverage."
task "coverage" do
  files = Dir["**/test/**/*_{spec,test}.rb"]
  sh "export COVERAGE=1; rspec --color --format doc '#{files.join("' '")}'" unless files.empty?
  sh "xdg-open coverage/index.html"
end

Packaging.configuration do |conf|
  conf.obs_project = "home:imanyugin:hana-updater"
  conf.package_name = "yast2-hana-updater"
  conf.obs_api = "https://api.suse.de/"
  # conf.obs_target = "SLE_12_SP1"
  conf.obs_target = "SLE_12_SP2"
end

Rake::Task["check:committed"].clear

# namespace :test do
#   desc "Runs unit tests."
#   task "unit" do
#     files = Dir["**/test/**/*_{spec,test}.rb"]
#     sh "rspec --color --format doc '#{files.join("' '")}'" unless files.empty?
#   end
# end
