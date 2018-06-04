# Manual Tests

- HANA versions:
    + Test HANA 1.0 SPS12 SDC to HANA 1.0 SPS01 MDC upgrade (make sure the checkbox is checked in the corresponding screen);
    + Test HANA 2.0 SPS01 to HANA 2.0 SPS03 upgrade;
- NFS share and update medium:
    + Do not mount the NFS share, care about the update medium yourself;
    + Mount the NFS share, without copying the installation medium (*Note:* AFL upgrade usually fails from the NFS share);
    + Mount the NFS share, copy the update medium to a local path (check consistency on both nodes, the local path should show up in the help sections in "update node XXX" screens);
- Sync direction restore:
    + (in the one of the last screens, select to) not restore the cluster state, then the primary and the secondary will exchange their roles;
    + Restore the cluster state, then after one more takeover action the former primary will become the current primary.

After the full cycle of execution, the cluster has to come to the normal state and *show no warnings*.
