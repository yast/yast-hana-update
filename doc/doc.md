Note: during the update of HANA on the former primary, the vIP resource will be forcefully moved to the node 
of the secondary SAP HANA instance. However, due to the fact that all resources are unmanaged by the cluster,
`crm_mon` will show that the resource is running on the former primary.
To make sure that the resource is indeed running on the former secondary node, execute the following command:

`crm_resource --force-check --resource=<vIP resource ID>`

Exit code `7` means that the resource is not running, while exit code `0` means that the resource is running.
