# Wrong cluster restore step

At step 7.
If we execute `su -lc 'hdbnsutil -sr_register --remoteHost=hana02 --remoteInstance=00 --replicationMode=sync --operationMode=delta_datashipping --name=NUREMBERG' 'prdadm'`, HANA doesn't allow us to do so:

> adding site ...
> checking for inactive nameserver ...
> error: system must be shut down before it can be registered as secondary site; 
> failed. trace file nameserver_hana01.00000.000.trc may contain more error details.

<hr>

This is due to the fact, that both instances think that they are primaries with no secondaries

**Correct step sequence to restore:**

1. `sr_disable` at former primary
```
hana01:~/yast-hana-update # ./debug.sh disable
> su -lc 'hdbnsutil -sr_disable' 'prdadm'
checking local nameserver:
checking for inactive nameserver ...
nameserver is running, proceeding ...
done.
Return code: 0
```

2. shut down in order to enable system replication
```
hana01:~/yast-hana-update # ./debug.sh stop
> su -lc 'HDB stop' 'prdadm'
hdbdaemon will wait maximal 300 seconds for NewDB services finishing.
Stopping instance using: /usr/sap/PRD/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function Stop 400

20.09.2017 14:14:39
Stop
OK
Waiting for stopped instance using: /usr/sap/PRD/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function WaitforStopped 600 2


20.09.2017 14:15:13
WaitforStopped
OK
hdbdaemon is stopped.
Return code: 0
```

3. register former primary as secondary:
```
hana01:~/yast-hana-update # ./debug.sh disable
> su -lc 'hdbnsutil -sr_disable' 'prdadm'
checking local nameserver:
checking for inactive nameserver ...
nameserver is running, proceeding ...
done.
Return code: 0
```

4. start it
```

```

5. query status  on current primary, until DBs are in sync
```
hana02:~/yast-hana-update # ./debug.sh status
> su -lc 'HDBSettings.sh systemReplicationStatus.py' 'prdadm'
| Database | Host   | Port  | Service Name | Volume ID | Site ID | Site Name | Secondary | Secondary | Secondary | Secondary | Secondary     | Replication | Replication  | Replication                       | 
|          |        |       |              |           |         |           | Host      | Port      | Site ID   | Site Name | Active Status | Mode        | Status       | Status Details                    | 
| -------- | ------ | ----- | ------------ | --------- | ------- | --------- | --------- | --------- | --------- | --------- | ------------- | ----------- | ------------ | --------------------------------- | 
| PRD      | hana02 | 30007 | xsengine     |         2 |       2 | PRAGUE    | hana01    |     30007 |         1 | NUREMBERG | YES           | SYNC        | ACTIVE       |                                   | 
| SYSTEMDB | hana02 | 30001 | nameserver   |         1 |       2 | PRAGUE    | hana01    |     30001 |         1 | NUREMBERG | YES           | SYNC        | INITIALIZING | Full Replica: 92 % (1376/1488 MB) | 
| PRD      | hana02 | 30003 | indexserver  |         3 |       2 | PRAGUE    | hana01    |     30003 |         1 | NUREMBERG | YES           | SYNC        | INITIALIZING | Full Replica: 7 % (224/3152 MB)   |

status system replication site "1": INITIALIZING
overall system replication status: INITIALIZING

Local System Replication State
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

mode: PRIMARY
site id: 2
site name: PRAGUE
Return code: 13


hana02:~/yast-hana-update # ./debug.sh status
> su -lc 'HDBSettings.sh systemReplicationStatus.py' 'prdadm'
| Database | Host   | Port  | Service Name | Volume ID | Site ID | Site Name | Secondary | Secondary | Secondary | Secondary | Secondary     | Replication | Replication  | Replication                       | 
|          |        |       |              |           |         |           | Host      | Port      | Site ID   | Site Name | Active Status | Mode        | Status       | Status Details                    | 
| -------- | ------ | ----- | ------------ | --------- | ------- | --------- | --------- | --------- | --------- | --------- | ------------- | ----------- | ------------ | --------------------------------- | 
| PRD      | hana02 | 30007 | xsengine     |         2 |       2 | PRAGUE    | hana01    |     30007 |         1 | NUREMBERG | YES           | SYNC        | ACTIVE       |                                   | 
| SYSTEMDB | hana02 | 30001 | nameserver   |         1 |       2 | PRAGUE    | hana01    |     30001 |         1 | NUREMBERG | YES           | SYNC        | ACTIVE       |                                   | 
| PRD      | hana02 | 30003 | indexserver  |         3 |       2 | PRAGUE    | hana01    |     30003 |         1 | NUREMBERG | YES           | SYNC        | INITIALIZING | Full Replica: 89 % (2816/3152 MB) |

status system replication site "1": INITIALIZING
overall system replication status: INITIALIZING

Local System Replication State
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

mode: PRIMARY
site id: 2
site name: PRAGUE
Return code: 13


hana02:~/yast-hana-update # ./debug.sh status
> su -lc 'HDBSettings.sh systemReplicationStatus.py' 'prdadm'
| Database | Host   | Port  | Service Name | Volume ID | Site ID | Site Name | Secondary | Secondary | Secondary | Secondary | Secondary     | Replication | Replication | Replication    | 
|          |        |       |              |           |         |           | Host      | Port      | Site ID   | Site Name | Active Status | Mode        | Status      | Status Details | 
| -------- | ------ | ----- | ------------ | --------- | ------- | --------- | --------- | --------- | --------- | --------- | ------------- | ----------- | ----------- | -------------- | 
| PRD      | hana02 | 30007 | xsengine     |         2 |       2 | PRAGUE    | hana01    |     30007 |         1 | NUREMBERG | YES           | SYNC        | ACTIVE      |                | 
| SYSTEMDB | hana02 | 30001 | nameserver   |         1 |       2 | PRAGUE    | hana01    |     30001 |         1 | NUREMBERG | YES           | SYNC        | ACTIVE      |                | 
| PRD      | hana02 | 30003 | indexserver  |         3 |       2 | PRAGUE    | hana01    |     30003 |         1 | NUREMBERG | YES           | SYNC        | ACTIVE      |                |

status system replication site "1": ACTIVE
overall system replication status: ACTIVE

Local System Replication State
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

mode: PRIMARY
site id: 2
site name: PRAGUE
Return code: 15
```

6. If cluster reverse is not needed, turn off maintenance mode, and we're done.
    hana02 will be primary
    vIP is already running here

========== TODO:
Should we migrate the IP before taking over?
Rejected DB writes are better than lost DB writes...

7. Else, take over to hana01:
```
hana01:~/yast-hana-update # ./debug.sh takeover
> su -lc 'hdbnsutil -sr_takeover' 'prdadm'
checking local nameserver ...
done.
>> Return code: 0
```

8. Migrate IP
```
hana01:~/yast-hana-update # ./debug.sh takeover
> su -lc 'hdbnsutil -sr_takeover' 'prdadm'
checking local nameserver ...
done.
>> Return code: 0
```

9. Register hana02 as secondary
```
hana02:~/yast-hana-update # ./debug.sh register
> su -lc 'hdbnsutil -sr_register --remoteHost=hana01 --remoteInstance=00 --replicationMode=sync --operationMode=delta_datashipping --name=PRAGUE' 'prdadm'
adding site ...
checking for inactive nameserver ...
error: system must be shut down before it can be registered as secondary site; 
failed. trace file nameserver_hana02.00000.000.trc may contain more error details.
>> Return code: 128


hana02:~/yast-hana-update # ./debug.sh disable
> su -lc 'hdbnsutil -sr_disable' 'prdadm'
checking local nameserver:
checking for inactive nameserver ...
nameserver is running, proceeding ...
done.
>> Return code: 0

hana02:~/yast-hana-update # ./debug.sh stop
> su -lc 'HDB stop' 'prdadm'
hdbdaemon will wait maximal 300 seconds for NewDB services finishing.
Stopping instance using: /usr/sap/PRD/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function Stop 400

20.09.2017 17:24:14
Stop
OK
Waiting for stopped instance using: /usr/sap/PRD/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function WaitforStopped 600 2


20.09.2017 17:24:46
WaitforStopped
OK
hdbdaemon is stopped.
>> Return code: 0

hana01:~/yast-hana-update # ./debug.sh state
> su -lc 'hdbnsutil -sr_state' 'prdadm'
checking for active or inactive nameserver ...

System Replication State
~~~~~~~~~~~~~~~~~~~~~~~~
online: true

mode: primary
operation mode: primary
site id: 1
site name: NUREMBERG

is source system: true
is secondary/consumer system: false
has secondaries/consumers attached: true
is a takeover active: false

Host Mappings:
~~~~~~~~~~~~~~

hana01 -> [NUREMBERG] hana01
hana01 -> [PRAGUE] hana02


done.
>> Return code: 0

hana02:~/yast-hana-update # ./debug.sh start
> su -lc 'HDB start' 'prdadm'


StartService
Impromptu CCC initialization by 'rscpCInit'.
  See SAP note 1266393.
OK
OK
Starting instance using: /usr/sap/PRD/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr 00 -function StartWait 2700 2


20.09.2017 17:25:17
Start
OK

20.09.2017 17:25:43
StartWait
OK
>> Return code: 0


hana01:~/yast-hana-update # ./debug.sh status
> su -lc 'HDBSettings.sh systemReplicationStatus.py' 'prdadm'
| Database | Host   | Port  | Service Name | Volume ID | Site ID | Site Name | Secondary | Secondary | Secondary | Secondary | Secondary     | Replication | Replication  | Replication                      | 
|          |        |       |              |           |         |           | Host      | Port      | Site ID   | Site Name | Active Status | Mode        | Status       | Status Details                   | 
| -------- | ------ | ----- | ------------ | --------- | ------- | --------- | --------- | --------- | --------- | --------- | ------------- | ----------- | ------------ | -------------------------------- | 
| PRD      | hana01 | 30007 | xsengine     |         2 |       1 | NUREMBERG | hana02    |     30007 |         2 | PRAGUE    | STARTING      | UNKNOWN     | UNKNOWN      |                                  | 
| SYSTEMDB | hana01 | 30001 | nameserver   |         1 |       1 | NUREMBERG | hana02    |     30001 |         2 | PRAGUE    | YES           | SYNC        | INITIALIZING | Full Replica: 62 % (928/1488 MB) | 
| PRD      | hana01 | 30003 | indexserver  |         3 |       1 | NUREMBERG | hana02    |     30003 |         2 | PRAGUE    | STARTING      | UNKNOWN     | UNKNOWN      |                                  |

status system replication site "2": UNKNOWN
overall system replication status: UNKNOWN

Local System Replication State
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

mode: PRIMARY
site id: 1
site name: NUREMBERG
>> Return code: 12


hana01:~/yast-hana-update # ./debug.sh status
> su -lc 'HDBSettings.sh systemReplicationStatus.py' 'prdadm'
| Database | Host   | Port  | Service Name | Volume ID | Site ID | Site Name | Secondary | Secondary | Secondary | Secondary | Secondary     | Replication | Replication | Replication    | 
|          |        |       |              |           |         |           | Host      | Port      | Site ID   | Site Name | Active Status | Mode        | Status      | Status Details | 
| -------- | ------ | ----- | ------------ | --------- | ------- | --------- | --------- | --------- | --------- | --------- | ------------- | ----------- | ----------- | -------------- | 
| PRD      | hana01 | 30007 | xsengine     |         2 |       1 | NUREMBERG | hana02    |     30007 |         2 | PRAGUE    | YES           | SYNC        | ACTIVE      |                | 
| SYSTEMDB | hana01 | 30001 | nameserver   |         1 |       1 | NUREMBERG | hana02    |     30001 |         2 | PRAGUE    | YES           | SYNC        | ACTIVE      |                | 
| PRD      | hana01 | 30003 | indexserver  |         3 |       1 | NUREMBERG | hana02    |     30003 |         2 | PRAGUE    | YES           | SYNC        | ACTIVE      |                |

status system replication site "2": ACTIVE
overall system replication status: ACTIVE

Local System Replication State
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

mode: PRIMARY
site id: 1
site name: NUREMBERG
>> Return code: 15

```

9. Clean up resources and maintenance off:
```
hana02:~/yast-hana-update # q cup
> crm resource cleanup msl_SAPHana_PRD_HDB00
Cleaned up rsc_SAPHana_PRD_HDB00:0 on hana01
Cleaned up rsc_SAPHana_PRD_HDB00:0 on hana02
Waiting for 2 replies from the CRMd.. OK
>> Return code: 0
> crm resource cleanup cln_SAPHanaTopology_PRD_HDB00
Cleaned up rsc_SAPHanaTopology_PRD_HDB00:0 on hana01
Cleaned up rsc_SAPHanaTopology_PRD_HDB00:0 on hana02
Waiting for 2 replies from the CRMd.. OK
>> Return code: 0
> crm resource cleanup rsc_ip_PRD_HDB00
Cleaned up rsc_ip_PRD_HDB00 on hana01
Cleaned up rsc_ip_PRD_HDB00 on hana02
Waiting for 2 replies from the CRMd.. OK
>> Return code: 0


hana01:~/yast-hana-update # q moff
> crm resource maintenance msl_SAPHana_PRD_HDB00 off
Set 'msl_SAPHana_PRD_HDB00' option: id=msl_SAPHana_PRD_HDB00-meta_attributes-maintenance name=maintenance=false
>> Return code: 0
> crm resource maintenance cln_SAPHanaTopology_PRD_HDB00 off
Set 'cln_SAPHanaTopology_PRD_HDB00' option: id=cln_SAPHanaTopology_PRD_HDB00-meta_attributes-maintenance name=maintenance=false
>> Return code: 0
> crm resource maintenance rsc_ip_PRD_HDB00 off
Set 'rsc_ip_PRD_HDB00' option: id=rsc_ip_PRD_HDB00-meta_attributes-maintenance name=maintenance=false
>> Return code: 0
```
