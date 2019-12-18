# SAP HANA updater

A YaST module that updates HANA within a SUSE cluster

## Organizational

**FATE request #320368:** *Allow easy update of SAP HANA software when operated within a SUSE HA cluster*

[![Travis Build](https://travis-ci.org/yast/yast-hana-update.svg?branch=master)](https://travis-ci.org/yast/yast-hana-update)
[![Jenkins Build](http://img.shields.io/jenkins/s/https/ci.opensuse.org/yast-hana-update-master.svg)](https://ci.opensuse.org/view/Yast/job/yast-hana-update-master/)
[![Code Climate](https://codeclimate.com/github/yast/yast-hana-update/badges/gpa.svg)](https://codeclimate.com/github/yast/yast-hana-update)
[![Coverage Status](https://coveralls.io/repos/yast/yast-hana-update/badge.png)](https://coveralls.io/r/yast/yast-hana-update)

## Execution

Run on a cluster node running *secondary* SAP HANA instance and follow the on-screen instructions.

## Feature scope

This module handles the cluster side of things during a SAP HANA software update. It makes sure the cluster's policy engine does not interrupt the update process, and handles resource lifecycle during the maintenance procedure.

The guide to follow is SAP's **How to Perform System Replication for SAP HANA** ([version 5.4 covering HANA 2.0 SPS02](https://www.sap.com/documents/2017/07/606a676e-c97c-0010-82c7-eda71af511fa.html)), section *Near Zero Downtime Upgrade and Maintenance*. The module has been built around this guide.
