# SAP HANA updater

[![Workflow Status](https://github.com/yast/yast-hana-update/workflows/CI/badge.svg?branch=master)](
https://github.com/yast/yast-hana-update/actions?query=branch%3Amaster)
[![Jenkins Status](https://ci.opensuse.org/buildStatus/icon?job=yast-yast-hana-update-master)](
https://ci.opensuse.org/view/Yast/job/yast-yast-hana-update-master/)
[![Coverage Status](https://img.shields.io/coveralls/yast/yast-hana-update.svg)](https://coveralls.io/r/yast/yast-hana-update?branch=master)

A YaST module that updates HANA within a SUSE cluster

## Organizational

**FATE request #320368:** *Allow easy update of SAP HANA software when operated within a SUSE HA cluster*

## Execution

Run on a cluster node running *secondary* SAP HANA instance and follow the on-screen instructions.

## Feature scope

This module handles the cluster side of things during a SAP HANA software update. It makes sure the cluster's policy engine does not interrupt the update process, and handles resource lifecycle during the maintenance procedure.

The guide to follow is SAP's **How to Perform System Replication for SAP HANA** ([version 5.4 covering HANA 2.0 SPS02](https://www.sap.com/documents/2017/07/606a676e-c97c-0010-82c7-eda71af511fa.html)), section *Near Zero Downtime Upgrade and Maintenance*. The module has been built around this guide.
