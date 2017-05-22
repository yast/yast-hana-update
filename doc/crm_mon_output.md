# crm_mon output

```xml
<crm_mon>
    <summary>
        <cluster_options maintenance-mode="false"/>
    </summary>
    <nodes>
        <node name="hana01" id="1084777749" online="true" standby="false" standby_onfail="false" maintenance="false" pending="false" unclean="false" shutdown="false" expected_up="true" is_dc="true" resources_running="3" type="member" />
        <node name="hana02" id="1084777750" online="true" standby="false" standby_onfail="false" maintenance="false" pending="false" unclean="false" shutdown="false" expected_up="true" is_dc="false" resources_running="3" type="member" />
    </nodes>
</crm_mon>
```

# Cluster state check
1. crm_mon/summary/cluster_options[@maintenance-mode] == "false"