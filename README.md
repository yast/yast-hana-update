# SAP HANA updater

A YaST module that updates HANA within a SUSE cluster

## Organizational

**FATE request #320368:** *Allow easy update of SAP HANA software when operated within a SUSE HA cluster*

## Execution

Run on a cluster node running *secondary* SAP HANA instance and follow the on-screen instructions.

## Feature scope

This module handles the cluster side of things during a SAP HANA software update. It makes sure the cluster's policy engine does not interrupt the update process, and handles resource lifecycle during the maintenance procedure.