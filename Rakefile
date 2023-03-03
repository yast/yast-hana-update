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

Yast::Tasks.submit_to :sle15sp5
require 'packaging'

Yast::Tasks.configuration do |conf|
  conf.skip_license_check << /.*desktop$/
  conf.skip_license_check << /.*erb$/
  conf.skip_license_check << /.*yaml$/
  conf.skip_license_check << /.*md$/
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
