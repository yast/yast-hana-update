#!/bin/bash

TMP_DIR=/tmp/rpm_diff

function die() {
    local msg=${1:-"Something went wrong"}
    local level=${2:-"\e[31mError\e[39m"}
    local rc_=${3:-1}
    echo -e "$level: $msg"
    exit $rc_
}

function usage(){
    echo -e "Usage: $(basename $0) <package_name> [file_name]"
}

function check_package(){
    rpm -qi $RPM_NAME > /dev/null 2>&1
    return $?
}

function verify_package(){
    rpm -V $RPM_NAME
    return $?
}

function show_diff(){
:
}

if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
    echo -e "\e[31mError:\e[39m Incorrect arguments."
    usage
    exit 1
fi

RPM_NAME=$1
FILE_NAME=$2

echo "Checking package '$RPM_NAME'..."
check_package
rc=$?
if [[ $rc -ne 0  ]]; then
    die "Package $RPM_NAME is not installed or was not found"
fi
changes=$(verify_package)
rc=$?
if [[ $rc -eq 0 ]]; then
    echo "Package $RPM_NAME is not modified"
    exit 0
else
    echo "Package $RPM_NAME is modified"
    echo
    echo $changes
    echo
    show_diff
fi