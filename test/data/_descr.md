# Test cases

## Case 01





Full list of resources:

stonith-sbd     (stonith:external/sbd): Started hana01
rsc_ip_XXX_HDB00        (ocf::heartbeat:IPaddr2):       Started hana01
 Master/Slave Set: msl_SAPHana_XXX_HDB00 [rsc_SAPHana_XXX_HDB00]
     Masters: [ hana01 ]
     Slaves: [ hana02 ]
 Clone Set: cln_SAPHanaTopology_XXX_HDB00 [rsc_SAPHanaTopology_XXX_HDB00]
     Started: [ hana01 hana02 ]

Failed Actions:
* rsc_SAPHana_XXX_HDB00_monitor_60000 on hana02 'ok' (0): call=30, status=compl
ete, exitreason='none',
    last-rc-change='Tue May 30 12:11:12 2017', queued=0ms, exec=6684ms


