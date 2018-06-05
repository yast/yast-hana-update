# Manual Tests

- HANA versions:
    + Test HANA 1.0 SPS12 SDC to HANA 2.0 SPS01 MDC upgrade (make sure the checkbox is checked in the corresponding screen);
    + Test HANA 2.0 SPS01 to HANA 2.0 SPS03 upgrade;
- NFS share and update medium:
    + Do not mount the NFS share, care about the update medium yourself;
    + Mount the NFS share, without copying the installation medium (*Note:* AFL upgrade, if AFL is installed, usually fails from the NFS share);
    + Mount the NFS share, copy the update medium to a local path (check consistency on both nodes, the local path should show up in the help sections in "update node XXX" screens);
- Sync direction restore:
    + (in the one of the last screens, select to) not restore the cluster state, then the primary and the secondary will exchange their roles;
    + Restore the cluster state, then after one more takeover action the former primary will become the current primary.
- Corner cases:
    + Run in a non-clustered environment
    + Run on an empty cluster
    + Run on a cluster with 2+ HANA resources
- Yast-specific: test both Qt and ncurses modes.
After the full cycle of execution, the cluster has to come to a normal state and *show no warnings*.


# How to test

1. Install HANA cluster in **Performance-Optimized scenario**.
2. Have the target version (update) media ready.
3. Create the [`SRTAKEOVER` user](#user) in the HANA secure store. Unless the user is created, the module won't allow you to proceed.
4. Start the module on the *secondary node*. If run it on the primary HANA node, the module will issue an error and quit.
5. The module scans the cluster configuration and presents a list of HANAs in the cluster. Select the necessary system and click *Next*.
6. If you're doing the HANA 1.0 to 2.0 upgrade, check the corresponding checkbox. Otherwise the SSFS keys won't be copied, and the two instances won't be able to talk to each other until you do it manually. This will break the wizard's workflow.
7. You can select that the module mounts the NFS share for you, and, optionally, it will copy its contents for you to a local path.
8. Click *Next*.
9. The update plan for the secondary instance is proposed. As soon as you click *Next*, the listed actions will be executed in the cluster.
10. Now the module waits until you update the secondary HANA instance. The *Help* section tells you how to do it. Click *Next* when done.
11. The update plan for the primary instance is proposed. As soon as you click *Next*, the listed actions, [including the takeover](#takeover), will be executed in the cluster.
12.  Now the module waits until you update the former HANA instance. The *Help* section tells you how to do it. Click *Next* when done. The SAP recommendation here is to use the `--hdbupd_server_nostart` parameter.
13. The last update plan is genrated and displayed to the user. Here we can choose to revert the synchronization direction, but it's not the default option.
14. Click *Next*. The cluster will come back out of the maintenance mode. During the sync stage, it's useful to look at the `./debug.sh status`. If something went wrong, e.g., secondary cannot sync properly, look at HANA trace files located at `/hana/shared/$(SID)/HDB${INO}/${hostname}/trace`.
15. Done.

# Cluster status after takeover <a name="takeover"></a>

Now that the takeover has been executed, the `hdbnsutil -sr_state` will show you that *both* HANA instances are primary, but in reality the former secondary is now the primary:
```
hana01:~/yast-hana-update # ./debug.sh state
> su -lc 'hdbnsutil -sr_state' prdadm
checking for active or inactive nameserver ...
nameserver hana01:30001 not responding.

System Replication State
`~~~~~~~~~~~~~~~~~~~~~~~~
online: false

mode: primary
site id: 1
site name: NUREMBERG

done.
>> Return code: 0
```
```
hana02:~/yast-hana-update # ./debug.sh status
> su -lc 'HDBSettings.sh systemReplicationStatus.py' prdadm
there are no secondary sites attached

Local System Replication State
`~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

mode: PRIMARY
site id: 2
site name: PRAGUE
>> Return code: 10
```
`crm_mon` shows that the virtual IP is running on the former primary node, but in reality it is running on the former secondary, which is now primary. Use `debug.sh fip` to find the IP resource:
```
hana02:~/yast-hana-update # ./debug.sh fip
> crm_resource --resource rsc_ip_PRD_HDB00 --force-check &>/dev/null
>> Return code: 0
> ssh hana01 'crm_resource --resource rsc_ip_PRD_HDB00 --force-check &>/dev/null'
>> Return code: 7
Resouce rsc_ip_PRD_HDB00 is running locally on node hana02
```
The accessibility of HANA can be checked by `debug.sh dummy`, that performs a SELECT on HANA:
```
hana02:~/yast-hana-update # ./debug.sh dummy
> su -lc "hdbsql  -j -d PRD -u SYSTEM -n 192.168.101.100:30015 -p Qwerty1234 \"SELECT * FROM DUMMY\"" prdadm
DUMMY
"X"
1 row selected (overall time 37.384 msec; server time 145 usec)

>> Return code: 0
```

# `SRTAKEOVER` user <a name="user"></a>
The "How To Perform System Replication for SAP HANA" guide describes how to create this user.
> Set user store entry for automatic repository import at takeover time on primary and secondary by executing the following command, where `<myUser>` requires the necessary privileges to import the repository content of the new version of the software during the takeover:
> `hdbuserstore SET SRTAKEOVER <public hostname>:<sqlport> <myUser> <UsersPasswd>`

The debug script has an option to do that automatically: `debug.sh srtakeover`, which also grants necessary privileges. `debug.sh srtakeover-check` checks for the userstore record and also checks the necessary permissions on DB level.
Make sure you use the right SQL port. Since this user account will be used *after* the upgrade, you'll probably need port `3xx15` for the first tenant.

On privileges: SAP writes:
> How to create a user `<myUser>` with the privileges required for importing the repository content is shown in the following example:

```
CREATE USER MY_REPO_IMPORT_USER PASSWORD MyRepoUserPW123;
GRANT EXECUTE ON SYS.REPOSITORY_REST TO MY_REPO_IMPORT_USER;
GRANT REPO.READ ON ".REPO_PACKAGE_ROOT" TO MY_REPO_IMPORT_USER;
GRANT REPO. IMPORT TO MY_REPO_IMPORT_USER;
GRANT SELECT ON _SYS_REPO.DELIVERY_UNITS TO MY_REPO_IMPORT_USER;
GRANT REPO.ACTIVATE_IMPORTED_OBJECTS ON ".REPO_PACKAGE_ROOT" TO MY_REPO_IMPORT_USER;
```

> You create this user on the primary from where it is replicated to the secondary automatically.

Note that only the DB user is replicated automatically, while the hdbuserstore user has to be created on every node.