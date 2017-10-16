#
# spec file for package yast2-hana-update
#
# Copyright (c) 2017 SUSE LINUX GmbH, Nuernberg, Germany.
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


Name:           yast2-hana-update
Version:        0.9.0
Release:        0
BuildArch:      noarch

Source0:        %{name}-%{version}.tar.bz2
Source1:        %{name}-rpmlintrc

Requires:       yast2
Requires:       yast2-ruby-bindings
# for opening URLs
Requires:       xdg-utils
# for handling the SSH client
Requires:       SAPHanaSR
Requires:       expect
Requires:       openssh
Requires:       crmsh

BuildRequires:  update-desktop-files
BuildRequires:  yast2
BuildRequires:  yast2-devtools
BuildRequires:  yast2-packager
BuildRequires:  yast2-ruby-bindings
BuildRequires:  rubygem(%{rb_default_ruby_abi}:rspec)
BuildRequires:  rubygem(%{rb_default_ruby_abi}:yast-rake)

Summary:        SUSE HANA Cluster Update
License:        GPL-2.0
Group:          System/YaST
Url:            http://www.suse.com

%description
A YaST2 module to update SAP HANA software within a SUSE Cluster

%prep
%setup -n %{name}-%{version}

%check
rake test:unit

%build

%install
mkdir -p %{buildroot}%{yast_dir}/data/hana_update/
mkdir -p %{buildroot}%{yast_vardir}/hana_update/
mkdir -p %{yast_scrconfdir}

rake install DESTDIR="%{buildroot}"
# wizard help files
install -m 644 data/*.html %{buildroot}%{yast_dir}/data/hana_update/
# ruby templates
install -m 644 data/*.erb %{buildroot}%{yast_dir}/data/hana_update/
# SSH invocation wrapper
install -m 755 data/check_ssh.expect %{buildroot}%{yast_dir}/data/hana_update/

%files
%defattr(-,root,root)
%doc %yast_docdir
%yast_desktopdir
%yast_clientdir
%yast_libdir
%{yast_dir}/data/hana_update/
%{yast_vardir}/hana_update/

%changelog
