# Algorithm

[TOC]

This document describes the algorithm of updating HANA software in SUSE HA cluster.

See [FATE #320368](https://fate.suse.com/320368).

## Initial configuration

|    Parameter    |               Value               |
|-----------------|-----------------------------------|
| HANA SID             | XXX                               |
| HANA Instance        | 00                                |
| Initial version | 1.0 SPS10, 1.00.102.02.1446663129 |
| Upgrade to      | 1.0 SPS12, 1.00.122.06.1485334242 |


| Hostname | HANA Site |  SR mode  |
|----------|-----------|-----------|
| hana01   | WDF       | primary   |
| hana02   | ROT       | secondary |

SR state on `hana01`:

    hana01:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~
    mode: primary
    site id: 1
    site name: WDF

    Host Mappings:
    ~~~~~~~~~~~~~~
    hana01 -> [WDF] hana01
    hana01 -> [ROT] hana02
    done.

SR state on `hana02`:

    hana02:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~

    mode: sync
    site id: 2
    site name: ROT
    active primary site: 1

    re-setup replication: hdbnsutil -sr_register --name=ROT --mode=sync --remoteHost=hana01 --remoteInstance=00

    Host Mappings:
    ~~~~~~~~~~~~~~

    hana02 -> [WDF] hana01
    hana02 -> [ROT] hana02

    primary masters:hana01

    done.

CRM monitor:

    Stack: corosync
    Current DC: hana01 (version 1.1.16-3.2-77ea74d) - partition with quorum
    Last updated: Thu Jun  1 19:06:05 2017
    Last change: Thu Jun  1 19:06:00 2017 by root via crm_attribute on hana01

    2 nodes configured
    6 resources configured

    Online: [ hana01 hana02 ]

    Full list of resources:

    stonith-sbd     (stonith:external/sbd): Started hana01
    rsc_ip_XXX_HDB00        (ocf::heartbeat:IPaddr2):       Started hana01
     Master/Slave Set: msl_SAPHana_XXX_HDB00 [rsc_SAPHana_XXX_HDB00]
         Masters: [ hana01 ]
         Slaves: [ hana02 ]
     Clone Set: cln_SAPHanaTopology_XXX_HDB00 [rsc_SAPHanaTopology_XXX_HDB00]
         Started: [ hana01 hana02 ]

Landscape (`hana01`):

    hana01:xxxadm> HDBSettings.sh landscapeHostConfiguration.py
    |  Host  |  Host  |  Host  | Failover | Remove |  Storage  |   Failover   |   Failover   |  NameServer |  NameServer | IndexServer | IndexServer |     Host     |     Host     |
    |        | Active | Status |  Status  | Status | Partition | Config Group | Actual Group | Config Role | Actual Role | Config Role | Actual Role | Config Roles | Actual Roles |
    |--------|--------|--------|----------|--------|-----------|--------------|--------------|-------------|-------------|-------------|-------------|--------------|--------------|
    | hana01 | yes    | ok     |          |        |         1 | default      | default      | master 1    | master      | worker      | master      | worker       | worker       |

Landscape (`hana02`):

    hana02:xxxadm> HDBSettings.sh landscapeHostConfiguration.py
    | Host   | Host   | Host   | Failover | Remove | Storage   | Failover     | Failover     | NameServer  | NameServer  | IndexServer | IndexServer | Host         | Host         |
    |        | Active | Status | Status   | Status | Partition | Config Group | Actual Group | Config Role | Actual Role | Config Role | Actual Role | Config Roles | Actual Roles |
    | ------ | ------ | ------ | -------- | ------ | --------- | ------------ | ------------ | ----------- | ----------- | ----------- | ----------- | ------------ | ------------ |
    | hana02 | yes    | ok     |          |        |         1 | default      | default      | master 1    | master      | worker      | master      | worker       | worker       |




## Steps

### 1. Put nodes `hana01` and `hana02` to maintenance mode.

Alternatively, put only the affected `SAPHana`, `SAPHanaTopology` and the `Virtual IP` resource agents to maintenance mode (allows for HANA MCOS scenario).
    
Execute:
  ``crm resource maintenance msl_SAPHana_XXX_HDB00``
  ``crm resource maintenance cln_SAPHanaTopology_XXX_HDB00``
  ``crm resource maintenance rsc_ip_XXX_HDB00``

### 2. Break system replication between nodes `hana01` and `hana02`.

Given that the maintenance takes place on `hana02`, `hana01` is still fully operational, receives the SQL connections and has the Virtual IP assigned to it.
    
Execute:

``hana02:xxxadm> HDB stop``
``hana02:xxxadm> hdbnsutil -sr_unregister``

A warning is shown: 
``CAUTION: You must start the database in order to complete the unregistration!``

``hana02:xxxadm> HDB start``

Now the SR looks like the following:
On `hana01`:

    hana01:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~

    mode: primary
    site id: 1
    site name: WDF

    Host Mappings:
    ~~~~~~~~~~~~~~

    hana01 -> [WDF] hana01


    done.

On `hana02`:

    hana02:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~

    mode: none

    done.

Landscape on host `hana01`:

    hana01:xxxadm> HDBSettings.sh landscapeHostConfiguration.py                                                          
    | Host   | Host   | Host   | Failover | Remove | Storage   | Failover     | Failover     | NameServer  | NameServer  |IndexServer | IndexServer | Host         | Host         |
    |        | Active | Status | Status   | Status | Partition | Config Group | Actual Group | Config Role | Actual Role |Config Role | Actual Role | Config Roles | Actual Roles |
    | ------ | ------ | ------ | -------- | ------ | --------- | ------------ | ------------ | ----------- | ----------- |----------- | ----------- | ------------ | ------------ |
    | hana01 | yes    | ok     |          |        |         1 | default      | default      | master 1    | master      |worker      | master      | worker       | worker       |
        
    overall host status: ok

Landscape on host `hana02`:

    hana02:xxxadm> HDBSettings.sh landscapeHostConfiguration.py
    | Host   | Host   | Host   | Failover | Remove | Storage   | Failover     | Failover     | NameServer  | NameServer  | IndexServer | IndexServer | Host         | Host         |
    |        | Active | Status | Status   | Status | Partition | Config Group | Actual Group | Config Role | Actual Role | Config Role | Actual Role | Config Roles | Actual Roles |
    | ------ | ------ | ------ | -------- | ------ | --------- | ------------ | ------------ | ----------- | ----------- | ----------- | ----------- | ------------ | ------------ |
    | hana02 | yes    | ok     |          |        |         1 | default      | default      | master 1    | master      | worker      | master      | worker       | worker       |

    overall host status: ok


### 3. Mount a user-prepared update medium served via NFS.

Dependant on the update procedure to be used, this can be a full installation medium downloaded from SMP, or a prepared delta update downloaded with HANA Studio. In the former case, the media is to be copied locally, as the hdblcm is known to being unable to install/update certain HANA components from an NFS share.

Execute:
``mkdir /tmp/hana-update``
``mount f102.suse.de:/home/ilya/sap_inst_media/UN_51051857 /tmp/hana-update/``

### 4. Allow the user to manually update HANA on node `hana02`.

In this case, running ``hdblcm --action=update`` from the mounted installation medium.

<font color="red">NB:</font> unmount `/tmp/hana-update`

### 5. Register `hana02` as secondary to `hana01`.

First we need to stop HANA on `hana02`: 
``HDB stop``

Only then we can register `hana02` as secondary to `hana01`:
``hdbnsutil -sr_register --name=ROT1 --replicationMode=sync --remoteHost=hana01 --remoteInstance=00``

Then, in order to start SR, we start HANA on `hana02`:
``HDB start``

### 8. Wait until primary syncs to the secondary (polling on the `M_SERVICE_REPLICATION` SQL view).

SQL View:

<small>

|  HOST  |  PORT  | VOLUME_ID | SITE_ID | SITE_NAME | SECONDARY_HOST | SECONDARY_PORT | SECONDARY_SITE_ID | SECONDARY_SITE_NAME | SECONDARY_ACTIVE_STATUS |     SECONDARY_CONNECT_TIME    | SECONDARY_RECONNECT_COUNT | SECONDARY_FAILOVER_COUNT | SECONDARY_FULLY_RECOVERABLE | REPLICATION_MODE | REPLICATION_STATUS | REPLICATION_STATUS_DETAILS | FULL_SYNC | LAST_LOG_POSITION |     LAST_LOG_POSITION_TIME    | LAST_SAVEPOINT_VERSION | LAST_SAVEPOINT_LOG_POSITION |   LAST_SAVEPOINT_START_TIME   | SHIPPED_LOG_POSITION |   SHIPPED_LOG_POSITION_TIME   | SHIPPED_LOG_BUFFERS_COUNT | SHIPPED_LOG_BUFFERS_SIZE | SHIPPED_LOG_BUFFERS_DURATION | SHIPPED_SAVEPOINT_VERSION | SHIPPED_SAVEPOINT_LOG_POSITION |  SHIPPED_SAVEPOINT_START_TIME | SHIPPED_FULL_REPLICA_COUNT | SHIPPED_FULL_REPLICA_SIZE | SHIPPED_FULL_REPLICA_DURATION | SHIPPED_LAST_FULL_REPLICA_SIZE | SHIPPED_LAST_FULL_REPLICA_START_TIME | SHIPPED_LAST_FULL_REPLICA_END_TIME | SHIPPED_DELTA_REPLICA_COUNT | SHIPPED_DELTA_REPLICA_SIZE | SHIPPED_DELTA_REPLICA_DURATION | SHIPPED_LAST_DELTA_REPLICA_SIZE | SHIPPED_LAST_DELTA_REPLICA_START_TIME | SHIPPED_LAST_DELTA_REPLICA_END_TIME | ASYNC_BUFFER_FULL_COUNT | BACKLOG_SIZE | MAX_BACKLOG_SIZE | BACKLOG_TIME | MAX_BACKLOG_TIME |
|--------|--------|-----------|---------|-----------|----------------|----------------|-------------------|---------------------|-------------------------|-------------------------------|---------------------------|--------------------------|-----------------------------|------------------|--------------------|----------------------------|-----------|-------------------|-------------------------------|------------------------|-----------------------------|-------------------------------|----------------------|-------------------------------|---------------------------|--------------------------|------------------------------|---------------------------|--------------------------------|-------------------------------|----------------------------|---------------------------|-------------------------------|--------------------------------|--------------------------------------|------------------------------------|-----------------------------|----------------------------|--------------------------------|---------------------------------|---------------------------------------|-------------------------------------|-------------------------|--------------|------------------|--------------|------------------|
| hana01 | 30,001 |         1 |       1 | WDF       | hana02         | 30,001         |                 2 | ROT1                | YES                     | Jun 2, 2017 4:13:12.812449 PM |                         4 |                        0 | TRUE                        | SYNC             | ACTIVE             |                            | DISABLED  | 408,640           | Jun 2, 2017 4:13:31.506861 PM |                     81 | 407,938                     | Jun 2, 2017 4:13:15.003099 PM | 408,640              | Jun 2, 2017 4:13:31.506861 PM | 144                       | 593,920                  | 311,351                      |                        79 | 407,618                        | Jun 2, 2017 4:13:12.81881 PM  |                          2 | 137,220,096               | 3,470,339                     | 68,624,384                     | Jun 2, 2017 4:13:12.81881 PM         | Jun 2, 2017 4:13:14.659724 PM      |                           8 | 103,931,904                | 1,185,772                      | 17,190,912                      | Jun 2, 2017 1:33:56.574895 PM         | Jun 2, 2017 1:33:56.745541 PM       |                       0 |            0 |                0 |            0 |                0 |
| hana01 | 30,007 |         2 |       1 | WDF       | hana02         | 30,007         |                 2 | ROT1                | YES                     | Jun 2, 2017 4:13:15.967104 PM |                         6 |                        0 | TRUE                        | SYNC             | ACTIVE             |                            | DISABLED  | 455,296           | Jun 2, 2017 4:12:47.107686 PM |                     78 | 455,234                     | Jun 2, 2017 4:13:16.573412 PM | 455,296              | Jun 2, 2017 4:12:47.107686 PM | 941                       | 3,854,336                | 2,649,748                    |                        76 | 455,170                        | Jun 2, 2017 4:13:15.971121 PM |                          2 | 137,003,008               | 1,502,534                     | 68,435,968                     | Jun 2, 2017 4:13:15.971121 PM        | Jun 2, 2017 4:13:16.532266 PM      |                           8 | 36,634,624                 | 522,719                        | 17,055,744                      | Jun 2, 2017 1:29:55.948731 PM         | Jun 2, 2017 1:29:56.158067 PM       |                       0 |            0 |                0 |            0 |                0 |
| hana01 | 30,003 |         3 |       1 | WDF       | hana02         | 30,003         |                 2 | ROT1                | YES                     | Jun 2, 2017 4:13:17.020702 PM |                         6 |                        0 | TRUE                        | SYNC             | ACTIVE             |                            | DISABLED  | 33,139,392        | Jun 2, 2017 4:13:28.937906 PM |                     79 | 33,139,330                  | Jun 2, 2017 4:13:31.508019 PM | 33,139,392           | Jun 2, 2017 4:13:28.937906 PM | 7,913                     | 37,109,760               | 26,217,688                   |                        77 | 33,139,138                     | Jun 2, 2017 4:13:17.095572 PM |                          2 | 3,236,642,816             | 25,242,641                    | 1,621,647,360                  | Jun 2, 2017 4:13:17.095572 PM        | Jun 2, 2017 4:13:31.368605 PM      |                           8 | 250,851,328                | 2,744,859                      | 29,995,008                      | Jun 2, 2017 1:29:54.031111 PM         | Jun 2, 2017 1:29:54.347181 PM       |                       0 |            0 |                0 |            0 |                0 |

</small>

SR status on `hana01`:

    hana01:xxxadm> hdbnsutil -sr_state

    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~

    mode: primary
    site id: 1
    site name: WDF

    Host Mappings:
    ~~~~~~~~~~~~~~

    hana01 -> [WDF] hana01
    hana01 -> [ROT1] hana02


    done.


SR status on `hana02`:

    hana02:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~
    online: true

    mode: sync
    site id: 2
    site name: ROT1
    active primary site: 1


    Host Mappings:
    ~~~~~~~~~~~~~~

    hana02 -> [WDF] hana01
    hana02 -> [ROT1] hana02

    primary masters:hana01

    done.

### 9. Perform `hdbnsutil -sr_takeover` action on host `hana02`, effectively making `hana02` the primary.

    hana02:xxxadm> hdbnsutil -sr_takeover
    checking local nameserver ...
    done.

SR status on `hana01`:

    hana01:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~

    mode: primary
    site id: 1
    site name: WDF

    Host Mappings:
    ~~~~~~~~~~~~~~

    hana01 -> [WDF] hana01
    hana01 -> [ROT1] hana02


    done.

SR status on `hana02`:

    hana02:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~
    online: true

    mode: primary
    site id: 2
    site name: ROT1

    Host Mappings:
    ~~~~~~~~~~~~~~

    hana02 -> [WDF] hana01
    hana02 -> [ROT1] hana02


    done.


### 10. Forcefully migrate the Virtual IP resource to `hana02`.
<font color="red">TODO:</font> It is yet unclear how `sr_takeover` is performed. Does it sync the data? Should we migrate the Virtual IP first and only then perform takeover?

Execute on `hana01`:

    hana01:~ # /usr/sbin/crm_resource --force-stop --resource rsc_ip_XXX_HDB00
    Operation stop for rsc_ip_XXX_HDB00 (ocf:heartbeat:IPaddr2) returned 0
     >  stderr: INFO: IP status = ok, IP_CIP=


Execute on `hana02`:

    hana02:~ # /usr/sbin/crm_resource --force-start --resource rsc_ip_XXX_HDB00
    Operation start for rsc_ip_XXX_HDB00 (ocf:heartbeat:IPaddr2) returned 0
    >  stderr: INFO: Adding inet address 192.168.101.105/24 with broadcast address 192.168.101.255 to device eth2
    >  stderr: INFO: Bringing device eth2 up
    >  stderr: INFO: /usr/lib64/heartbeat/send_arp -i 200 -r 5 -p /run/resource-agents/send_arp-192.168.101.105 eth2 192.168.101.105 auto not_used not_used

### 11. Clear replication setup on `hana01`.

    hana01:xxxadm> HDB stop
    hdbdaemon will wait maximal 300 seconds for NewDB services finishing.
    Stopping instance using: /usr/sap/XXX/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function Stop 400

    02.06.2017 16:53:18
    Stop
    OK
    Waiting for stopped instance using: /usr/sap/XXX/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function WaitforStopped 600 2


    02.06.2017 16:53:40
    WaitforStopped
    OK
    hdbdaemon is stopped.

    hana01:xxxadm> hdbnsutil -sr_cleanup --force
    cleaning up ...

    ###################################################################################################################################
    ### WARNING: cleaning up will break system replication; secondary sites need to be takeovered by issuing hdbnsutil -sr_takeover ###
    ###################################################################################################################################

    checking for inactive nameserver ...
    nameserver hana01:30001 not responding.
    opening persistence ...
    run as transaction master
    clearing topology ...
    clearing local ini files ...
    done.

### 12. Mount the update medium on `hana01`.

Execute:
``mkdir /tmp/hana-update``
``mount f102.suse.de:/home/ilya/sap_inst_media/UN_51051857 /tmp/hana-update/``

### 13. Allow user to update HANA on node `hana01`.

In this case, running ``hdblcm --action=update`` from the mounted installation medium.

<font color="red">NB:</font> unmount `/tmp/hana-update`

### 14. Register `hana01` as secondary to `hana02`.

Since update process leaves HANA in started mode (can we prevent it?), we need to stop it first.

    hana01:xxxadm> HDB stop
    hdbdaemon will wait maximal 300 seconds for NewDB services finishing.
    Stopping instance using: /usr/sap/XXX/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function Stop 400

    02.06.2017 17:01:35
    Stop
    OK
    Waiting for stopped instance using: /usr/sap/XXX/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function WaitforStopped 600 2


    02.06.2017 17:01:59
    WaitforStopped
    OK
    hdbdaemon is stopped.
    hana01:xxxadm> hdbnsutil -sr_register --name=WDF1 --replicationMode=sync --remoteHost=hana02 --remoteInstance=00
    adding site ...
    --operationMode not set; using default from global.ini/[system_replication]/operation_mode: delta_datashipping
    checking for inactive nameserver ...
    nameserver hana01:30001 not responding.
    collecting information ...
    updating local ini files ...
    done.

M_SERVICE_REPLICATION view (HANA on `hana01` is still stopped):

HANA is not yet up: Connection timeout.

<small>

|  HOST  |  PORT  | VOLUME_ID | SITE_ID | SITE_NAME | SECONDARY_HOST | SECONDARY_PORT | SECONDARY_SITE_ID | SECONDARY_SITE_NAME | SECONDARY_ACTIVE_STATUS | SECONDARY_CONNECT_TIME | SECONDARY_RECONNECT_COUNT | SECONDARY_FAILOVER_COUNT | SECONDARY_FULLY_RECOVERABLE | REPLICATION_MODE | REPLICATION_STATUS | REPLICATION_STATUS_DETAILS | FULL_SYNC | LAST_LOG_POSITION | LAST_LOG_POSITION_TIME | LAST_SAVEPOINT_VERSION | LAST_SAVEPOINT_LOG_POSITION | LAST_SAVEPOINT_START_TIME | SHIPPED_LOG_POSITION | SHIPPED_LOG_POSITION_TIME | SHIPPED_LOG_BUFFERS_COUNT | SHIPPED_LOG_BUFFERS_SIZE | SHIPPED_LOG_BUFFERS_DURATION | REPLAYED_LOG_POSITION | REPLAYED_LOG_POSITION_TIME | SHIPPED_SAVEPOINT_VERSION | SHIPPED_SAVEPOINT_LOG_POSITION | SHIPPED_SAVEPOINT_START_TIME | SHIPPED_FULL_REPLICA_COUNT | SHIPPED_FULL_REPLICA_SIZE | SHIPPED_FULL_REPLICA_DURATION | SHIPPED_LAST_FULL_REPLICA_SIZE | SHIPPED_LAST_FULL_REPLICA_START_TIME | SHIPPED_LAST_FULL_REPLICA_END_TIME | SHIPPED_DELTA_REPLICA_COUNT | SHIPPED_DELTA_REPLICA_SIZE | SHIPPED_DELTA_REPLICA_DURATION | SHIPPED_LAST_DELTA_REPLICA_SIZE | SHIPPED_LAST_DELTA_REPLICA_START_TIME | SHIPPED_LAST_DELTA_REPLICA_END_TIME | ASYNC_BUFFER_FULL_COUNT | BACKLOG_SIZE | MAX_BACKLOG_SIZE | BACKLOG_TIME | MAX_BACKLOG_TIME |
|--------|--------|-----------|---------|-----------|----------------|----------------|-------------------|---------------------|-------------------------|------------------------|---------------------------|--------------------------|-----------------------------|------------------|--------------------|----------------------------|-----------|-------------------|------------------------|------------------------|-----------------------------|---------------------------|----------------------|---------------------------|---------------------------|--------------------------|------------------------------|-----------------------|----------------------------|---------------------------|--------------------------------|------------------------------|----------------------------|---------------------------|-------------------------------|--------------------------------|--------------------------------------|------------------------------------|-----------------------------|----------------------------|--------------------------------|---------------------------------|---------------------------------------|-------------------------------------|-------------------------|--------------|------------------|--------------|------------------|
| hana02 | 30,001 |         1 |       2 | ROT1      | hana01         | 30,001         |                 1 | WDF1                | CONNECTION TIMEO        | ?                      |                         0 |                        0 | FALSE                       | UNKNOWN          | UNKNOWN            |                            | DISABLED  |                 0 | ?                      |                      0 |                           0 | ?                         |                    0 | ?                         |                         0 |                        0 |                            0 |                     0 | ?                          |                         0 |                              0 | ?                            |                          0 |                         0 |                             0 |                              0 | ?                                    | ?                                  |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |
| hana02 | 30,007 |         2 |       2 | ROT1      | hana01         | 30,007         |                 1 | WDF1                | CONNECTION TIMEO        | ?                      |                         0 |                        0 | FALSE                       | UNKNOWN          | UNKNOWN            |                            | DISABLED  |                 0 | ?                      |                      0 |                           0 | ?                         |                    0 | ?                         |                         0 |                        0 |                            0 |                     0 | ?                          |                         0 |                              0 | ?                            |                          0 |                         0 |                             0 |                              0 | ?                                    | ?                                  |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |
| hana02 | 30,003 |         3 |       2 | ROT1      | hana01         | 30,003         |                 1 | WDF1                | CONNECTION TIMEO        | ?                      |                         0 |                        0 | FALSE                       | UNKNOWN          | UNKNOWN            |                            | DISABLED  |                 0 | ?                      |                      0 |                           0 | ?                         |                    0 | ?                         |                         0 |                        0 |                            0 |                     0 | ?                          |                         0 |                              0 | ?                            |                          0 |                         0 |                             0 |                              0 | ?                                    | ?                                  |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |

</small>

### 15. Wait until primary syncs to the secondary 

Simply poll on the `M_SERVICE_REPLICATION` SQL view.

During data sync phase:

<small>

|  HOST  |  PORT  | VOLUME_ID | SITE_ID | SITE_NAME | SECONDARY_HOST | SECONDARY_PORT | SECONDARY_SITE_ID | SECONDARY_SITE_NAME | SECONDARY_ACTIVE_STATUS |     SECONDARY_CONNECT_TIME    | SECONDARY_RECONNECT_COUNT | SECONDARY_FAILOVER_COUNT | SECONDARY_FULLY_RECOVERABLE | REPLICATION_MODE | REPLICATION_STATUS |    REPLICATION_STATUS_DETAILS    | FULL_SYNC | LAST_LOG_POSITION |     LAST_LOG_POSITION_TIME    | LAST_SAVEPOINT_VERSION | LAST_SAVEPOINT_LOG_POSITION |   LAST_SAVEPOINT_START_TIME   | SHIPPED_LOG_POSITION |   SHIPPED_LOG_POSITION_TIME   | SHIPPED_LOG_BUFFERS_COUNT | SHIPPED_LOG_BUFFERS_SIZE | SHIPPED_LOG_BUFFERS_DURATION | REPLAYED_LOG_POSITION | REPLAYED_LOG_POSITION_TIME | SHIPPED_SAVEPOINT_VERSION | SHIPPED_SAVEPOINT_LOG_POSITION |  SHIPPED_SAVEPOINT_START_TIME | SHIPPED_FULL_REPLICA_COUNT | SHIPPED_FULL_REPLICA_SIZE | SHIPPED_FULL_REPLICA_DURATION | SHIPPED_LAST_FULL_REPLICA_SIZE | SHIPPED_LAST_FULL_REPLICA_START_TIME | SHIPPED_LAST_FULL_REPLICA_END_TIME | SHIPPED_DELTA_REPLICA_COUNT | SHIPPED_DELTA_REPLICA_SIZE | SHIPPED_DELTA_REPLICA_DURATION | SHIPPED_LAST_DELTA_REPLICA_SIZE | SHIPPED_LAST_DELTA_REPLICA_START_TIME | SHIPPED_LAST_DELTA_REPLICA_END_TIME | ASYNC_BUFFER_FULL_COUNT | BACKLOG_SIZE | MAX_BACKLOG_SIZE | BACKLOG_TIME | MAX_BACKLOG_TIME |
|--------|--------|-----------|---------|-----------|----------------|----------------|-------------------|---------------------|-------------------------|-------------------------------|---------------------------|--------------------------|-----------------------------|------------------|--------------------|----------------------------------|-----------|-------------------|-------------------------------|------------------------|-----------------------------|-------------------------------|----------------------|-------------------------------|---------------------------|--------------------------|------------------------------|-----------------------|----------------------------|---------------------------|--------------------------------|-------------------------------|----------------------------|---------------------------|-------------------------------|--------------------------------|--------------------------------------|------------------------------------|-----------------------------|----------------------------|--------------------------------|---------------------------------|---------------------------------------|-------------------------------------|-------------------------|--------------|------------------|--------------|------------------|
| hana02 | 30,001 |         1 |       2 | ROT1      | hana01         | 30,001         |                 1 | WDF1                | YES                     | Jun 2, 2017 5:04:07.297388 PM |                         0 |                        0 | TRUE                        | SYNC             | ACTIVE             |                                  | DISABLED  | 414,464           | Jun 2, 2017 5:04:11.975852 PM |                     91 | 413,826                     | Jun 2, 2017 5:04:10.165481 PM | 414,464              | Jun 2, 2017 5:04:11.975852 PM |                        17 | 69,632                   | 29,434                       |                     0 | ?                          |                        89 | 413,506                        | Jun 2, 2017 5:04:07.303051 PM |                          1 | 83,886,080                | 2,713,397                     | 83,886,080                     | Jun 2, 2017 5:04:07.303051 PM        | Jun 2, 2017 5:04:10.016448 PM      |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |
| hana02 | 30,007 |         2 |       2 | ROT1      | hana01         | 30,007         |                 1 | WDF1                | YES                     | Jun 2, 2017 5:04:10.77775 PM  |                         0 |                        0 | TRUE                        | SYNC             | ACTIVE             |                                  | DISABLED  | 545,280           | Jun 2, 2017 5:04:10.790948 PM |                     88 | 545,218                     | Jun 2, 2017 5:04:11.540706 PM | 545,280              | Jun 2, 2017 5:04:10.790948 PM |                         4 | 16,384                   | 8,487                        |                     0 | ?                          |                        86 | 545,154                        | Jun 2, 2017 5:04:10.78767 PM  |                          1 | 83,886,080                | 692,828                       | 83,886,080                     | Jun 2, 2017 5:04:10.78767 PM         | Jun 2, 2017 5:04:11.480498 PM      |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |
| hana02 | 30,003 |         3 |       2 | ROT1      | hana01         | 30,003         |                 1 | WDF1                | YES                     | Jun 2, 2017 5:04:11.741705 PM |                         0 |                        0 | FALSE                       | SYNC             | INITIALIZING       | Full Replica: 36 % (576/1568 MB) | DISABLED  | 35,423,808        | Jun 2, 2017 5:04:13.139818 PM |                     89 | 35,423,682                  | Jun 2, 2017 5:04:11.758078 PM | 35,423,808           | Jun 2, 2017 5:04:13.139818 PM |                         3 | 12,288                   | 31,074                       |                     0 | ?                          |                         0 | 0                              | ?                             |                          0 | 0                         | 0                             | 0                              | ?                                    | ?                                  |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |

</small>

And finally fully synced:

<small>

|  HOST  |  PORT  | VOLUME_ID | SITE_ID | SITE_NAME | SECONDARY_HOST | SECONDARY_PORT | SECONDARY_SITE_ID | SECONDARY_SITE_NAME | SECONDARY_ACTIVE_STATUS |     SECONDARY_CONNECT_TIME    | SECONDARY_RECONNECT_COUNT | SECONDARY_FAILOVER_COUNT | SECONDARY_FULLY_RECOVERABLE | REPLICATION_MODE | REPLICATION_STATUS | REPLICATION_STATUS_DETAILS | FULL_SYNC | LAST_LOG_POSITION |     LAST_LOG_POSITION_TIME    | LAST_SAVEPOINT_VERSION | LAST_SAVEPOINT_LOG_POSITION |   LAST_SAVEPOINT_START_TIME   | SHIPPED_LOG_POSITION |   SHIPPED_LOG_POSITION_TIME   | SHIPPED_LOG_BUFFERS_COUNT | SHIPPED_LOG_BUFFERS_SIZE | SHIPPED_LOG_BUFFERS_DURATION | REPLAYED_LOG_POSITION | REPLAYED_LOG_POSITION_TIME | SHIPPED_SAVEPOINT_VERSION | SHIPPED_SAVEPOINT_LOG_POSITION |  SHIPPED_SAVEPOINT_START_TIME | SHIPPED_FULL_REPLICA_COUNT | SHIPPED_FULL_REPLICA_SIZE | SHIPPED_FULL_REPLICA_DURATION | SHIPPED_LAST_FULL_REPLICA_SIZE | SHIPPED_LAST_FULL_REPLICA_START_TIME | SHIPPED_LAST_FULL_REPLICA_END_TIME | SHIPPED_DELTA_REPLICA_COUNT | SHIPPED_DELTA_REPLICA_SIZE | SHIPPED_DELTA_REPLICA_DURATION | SHIPPED_LAST_DELTA_REPLICA_SIZE | SHIPPED_LAST_DELTA_REPLICA_START_TIME | SHIPPED_LAST_DELTA_REPLICA_END_TIME | ASYNC_BUFFER_FULL_COUNT | BACKLOG_SIZE | MAX_BACKLOG_SIZE | BACKLOG_TIME | MAX_BACKLOG_TIME |
|--------|--------|-----------|---------|-----------|----------------|----------------|-------------------|---------------------|-------------------------|-------------------------------|---------------------------|--------------------------|-----------------------------|------------------|--------------------|----------------------------|-----------|-------------------|-------------------------------|------------------------|-----------------------------|-------------------------------|----------------------|-------------------------------|---------------------------|--------------------------|------------------------------|-----------------------|----------------------------|---------------------------|--------------------------------|-------------------------------|----------------------------|---------------------------|-------------------------------|--------------------------------|--------------------------------------|------------------------------------|-----------------------------|----------------------------|--------------------------------|---------------------------------|---------------------------------------|-------------------------------------|-------------------------|--------------|------------------|--------------|------------------|
| hana02 | 30,001 |         1 |       2 | ROT1      | hana01         | 30,001         |                 1 | WDF1                | YES                     | Jun 2, 2017 5:04:07.297388 PM |                         0 |                        0 | TRUE                        | SYNC             | ACTIVE             |                            | DISABLED  | 414,528           | Jun 2, 2017 5:04:24.781145 PM |                     91 | 413,826                     | Jun 2, 2017 5:04:10.165481 PM | 414,528              | Jun 2, 2017 5:04:24.781145 PM |                        18 | 73,728                   | 29,984                       |                     0 | ?                          |                        89 | 413,506                        | Jun 2, 2017 5:04:07.303051 PM |                          1 | 83,886,080                | 2,713,397                     | 83,886,080                     | Jun 2, 2017 5:04:07.303051 PM        | Jun 2, 2017 5:04:10.016448 PM      |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |
| hana02 | 30,007 |         2 |       2 | ROT1      | hana01         | 30,007         |                 1 | WDF1                | YES                     | Jun 2, 2017 5:04:10.77775 PM  |                         0 |                        0 | TRUE                        | SYNC             | ACTIVE             |                            | DISABLED  | 545,600           | Jun 2, 2017 5:04:35.236106 PM |                     88 | 545,218                     | Jun 2, 2017 5:04:11.540706 PM | 545,600              | Jun 2, 2017 5:04:35.236106 PM |                         9 | 36,864                   | 23,656                       |                     0 | ?                          |                        86 | 545,154                        | Jun 2, 2017 5:04:10.78767 PM  |                          1 | 83,886,080                | 692,828                       | 83,886,080                     | Jun 2, 2017 5:04:10.78767 PM         | Jun 2, 2017 5:04:11.480498 PM      |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |
| hana02 | 30,003 |         3 |       2 | ROT1      | hana01         | 30,003         |                 1 | WDF1                | YES                     | Jun 2, 2017 5:04:11.741705 PM |                         0 |                        0 | TRUE                        | SYNC             | ACTIVE             |                            | DISABLED  | 35,428,736        | Jun 2, 2017 5:04:35.267349 PM |                     90 | 35,423,810                  | Jun 2, 2017 5:04:24.786158 PM | 35,428,736           | Jun 2, 2017 5:04:35.267349 PM |                        79 | 327,680                  | 291,963                      |                     0 | ?                          |                        88 | 35,423,682                     | Jun 2, 2017 5:04:11.758052 PM |                          1 | 1,644,167,168             | 12,845,455                    | 1,644,167,168                  | Jun 2, 2017 5:04:11.758052 PM        | Jun 2, 2017 5:04:24.603507 PM      |                           0 |                          0 |                              0 |                               0 | ?                                     | ?                                   |                       0 |            0 |                0 |            0 |                0 |

</small>

### 16. Optionally, restore cluster to its initial state.
First we force a migration of the Virtual IP address to `hana01`:

    hana02:~ # /usr/sbin/crm_resource --force-stop --resource rsc_ip_XXX_HDB00
    Operation stop for rsc_ip_XXX_HDB00 (ocf:heartbeat:IPaddr2) returned 0
     >  stderr: INFO: IP status = ok, IP_CIP=


    hana01:~ # /usr/sbin/crm_resource --force-start --resource rsc_ip_XXX_HDB00
    Operation start for rsc_ip_XXX_HDB00 (ocf:heartbeat:IPaddr2) returned 0
     >  stderr: INFO: Adding inet address 192.168.101.105/24 with broadcast address 192.168.101.255 to device eth2
     >  stderr: INFO: Bringing device eth2 up
     >  stderr: INFO: /usr/lib64/heartbeat/send_arp -i 200 -r 5 -p /run/resource-agents/send_arp-192.168.101.105 eth2 192.168.101.105 auto not_used not_used

Then we revert the synchronization direction:

    hana01:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~
    online: true

    mode: primary
    site id: 1
    site name: WDF1

    Host Mappings:
    ~~~~~~~~~~~~~~

    hana01 -> [WDF1] hana01
    hana01 -> [ROT1] hana02


    done.

On `hana02`:

    hana02:xxxadm> HDB stop
    hdbdaemon will wait maximal 300 seconds for NewDB services finishing.
    Stopping instance using: /usr/sap/XXX/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function Stop 400

    02.06.2017 17:42:44
    Stop
    OK
    Waiting for stopped instance using: /usr/sap/XXX/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function WaitforStopped 600 2


    02.06.2017 17:43:04
    WaitforStopped
    OK
    hdbdaemon is stopped.

    hana02:xxxadm> hdbnsutil -sr_register --name=ROT1 --replicationMode=sync --remoteHost=hana01 --remoteInstance=00
    adding site ...
    --operationMode not set; using default from global.ini/[system_replication]/operation_mode: delta_datashipping
    checking for inactive nameserver ...
    nameserver hana02:30001 not responding.
    collecting information ...
    updating local ini files ...
    done.

    hana02:xxxadm> HDB start


    StartService
    Impromptu CCC initialization by 'rscpCInit'.
      See SAP note 1266393.
    OK
    OK
    Starting instance using: /usr/sap/XXX/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function StartWait 2700 2


    02.06.2017 17:44:50
    Start
    OK

    02.06.2017 17:45:12
    StartWait
    OK

### 17. Clean up resources.

    hana01:~ # crm_resource --cleanup --resource msl_SAPHana_XXX_HDB00
    Cleaned up rsc_SAPHana_XXX_HDB00:0 on hana01
    Cleaned up rsc_SAPHana_XXX_HDB00:0 on hana02
    Waiting for 2 replies from the CRMd.. OK
    hana01:~ # crm_resource --cleanup --resource cln_SAPHanaTopology_XXX_HDB00
    Cleaned up rsc_SAPHanaTopology_XXX_HDB00:0 on hana01
    Cleaned up rsc_SAPHanaTopology_XXX_HDB00:0 on hana02
    Waiting for 2 replies from the CRMd.. OK
    hana01:~ # crm_resource --cleanup --resource rsc_ip_XXX_HDB00
    Cleaned up rsc_ip_XXX_HDB00 on hana01
    Cleaned up rsc_ip_XXX_HDB00 on hana02
    Waiting for 2 replies from the CRMd.. OK

### 18. Put resources out of maintenance mode.

    hana01:~ # crm resource maintenance msl_SAPHana_XXX_HDB00 off
    Set 'msl_SAPHana_XXX_HDB00' option: id=msl_SAPHana_XXX_HDB00-meta_attributes-maintenance name=maintenance=false
    hana01:~ # crm resource maintenance cln_SAPHanaTopology_XXX_HDB00 off
    Set 'cln_SAPHanaTopology_XXX_HDB00' option: id=cln_SAPHanaTopology_XXX_HDB00-meta_attributes-maintenance name=maintenance=false
    hana01:~ # crm resource maintenance rsc_ip_XXX_HDB00 off
    Set 'rsc_ip_XXX_HDB00' option: id=rsc_ip_XXX_HDB00-meta_attributes-maintenance name=maintenance=false


## Resulting configuration

SR status on `hana01`:

    hana01:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~
    online: true

    mode: primary
    site id: 1
    site name: WDF1

    Host Mappings:
    ~~~~~~~~~~~~~~

    hana01 -> [WDF1] hana01
    hana01 -> [ROT1] hana02


    done.

SR status on `hana02`:

    hana02:xxxadm> hdbnsutil -sr_state
    checking for active or inactive nameserver ...

    System Replication State
    ~~~~~~~~~~~~~~~~~~~~~~~~
    online: true

    mode: sync
    site id: 2
    site name: ROT1
    active primary site: 1


    Host Mappings:
    ~~~~~~~~~~~~~~

    hana02 -> [WDF1] hana01
    hana02 -> [ROT1] hana02

    primary masters:hana01

    done.

CRM monitor:

    Stack: corosync
    Current DC: hana01 (version 1.1.16-3.2-77ea74d) - partition with quorum
    Last updated: Fri Jun  2 17:52:50 2017
    Last change: Fri Jun  2 17:51:46 2017 by root via crm_attribute on hana01

    2 nodes configured
    6 resources configured

    Online: [ hana01 hana02 ]

    Full list of resources:

    stonith-sbd     (stonith:external/sbd): Started hana01
    rsc_ip_XXX_HDB00        (ocf::heartbeat:IPaddr2):       Started hana01
     Master/Slave Set: msl_SAPHana_XXX_HDB00 [rsc_SAPHana_XXX_HDB00]
         Masters: [ hana01 ]
         Slaves: [ hana02 ]
     Clone Set: cln_SAPHanaTopology_XXX_HDB00 [rsc_SAPHanaTopology_XXX_HDB00]
         Started: [ hana01 hana02 ]

HDB version on `hana01`:

    hana01:xxxadm> HDB version
    HDB version info:
      version:             1.00.122.06.1485334242
      branch:              fa/hana1sp12
      git hash:            d8064682123f04814f4ffe01dc21a928a1b703a4
      git merge time:      2017-01-25 09:50:42
      weekstone:           0000.00.0
      compile date:        2017-01-25 10:00:24
      compile host:        ld7272
      compile type:        rel

HDB version on `hana02`:

    hana02:xxxadm> HDB version
    HDB version info:
      version:             1.00.122.06.1485334242
      branch:              fa/hana1sp12
      git hash:            d8064682123f04814f4ffe01dc21a928a1b703a4
      git merge time:      2017-01-25 09:50:42
      weekstone:           0000.00.0
      compile date:        2017-01-25 10:00:24
      compile host:        ld7272
      compile type:        rel

