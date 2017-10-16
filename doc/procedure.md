# Three-step update procedure

## All steps

1. System Selection
2. Media Selection
3. Update Local Node // Rename? Cluster configuration
4. Update HANA
5. Update Plan (remote node)


## Step 3. Local node re-configuration

This step prepares local node (secondary HANA instance) for update.

1. Set msl, cln and vip resources to maintenance mode.
2. Stop HANA locally.
3. Unregister secondary (local node).
4. Start HANA locally.
5. Mound update medium [opt]

### Cluster state after step 3

1. Cluster resources are in maintenance mode.
2. Local HANA is running and has no SR enabled
3. Media is mounted/updated
4. vIP is running on the remote node
5. Remote HANA is running
6. Remote HANA is in mode=primary

## Step 5. Remote node re-configuration

This step brings back the SR as it used to be set up and syncs data (steps 1-3), takes
over to the local node (step 4) and prepares the remote node (former primary HANA
instance) for update (steps 5-6).

1. Stop HANA on local node.
2. Register local site as secondary to the primary.
3. Start HANA on local node, and wait until instances are in sync.
4. Take over from remote to local.
5. Force-migrate the IP address to local node.
6. Disable system replication on remote.

### Cluster state after step 5

1. Cluster resources are in maintenance mode
2. Local HANA is running
3. Local HANA is in mode PRIMARY
4. vIP is running on local node
5. HANA is running on remote node
