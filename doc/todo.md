1. Parse output of crm_mon first, because it's the only way of getting resource IDs by their resource type, i.e. SAPHana, SAPHanaTopology, etc.

Then we get something like:

```xml
<clone id="msl_SAPHana_XXX_HDB00" multi_state="true" unique="false" managed="true" failed="false" failure_ignored="false" >
        <resource id="rsc_SAPHana_XXX_HDB00" resource_agent="ocf::suse:SAPHana" role="Master" active="true" orphaned="false" blocked="false" managed="true" failed="false" failure_ignored="false" nodes_running_on="1" >
            <node name="hana01" id="1084777749" cached="false"/>
        </resource>
        <resource id="rsc_SAPHana_XXX_HDB00" resource_agent="ocf::suse:SAPHana" role="Slave" active="true" orphaned="false" blocked="false" managed="true" failed="false" failure_ignored="false" nodes_running_on="1" >
            <node name="hana02" id="1084777750" cached="false"/>
        </resource>
</clone>
<clone id="cln_SAPHanaTopology_XXX_HDB00" multi_state="false" unique="false" managed="true" failed="false" failure_ignored="false" >
    <resource id="rsc_SAPHanaTopology_XXX_HDB00" resource_agent="ocf::suse:SAPHanaTopology" role="Started" active="true" orphaned="false" blocked="false" managed="true" failed="false" failure_ignored="false" nodes_running_on="1" >
        <node name="hana01" id="1084777749" cached="false"/>
    </resource>
    <resource id="rsc_SAPHanaTopology_XXX_HDB00" resource_agent="ocf::suse:SAPHanaTopology" role="Started" active="true" orphaned="false" blocked="false" managed="true" failed="false" failure_ignored="false" nodes_running_on="1" >
        <node name="hana02" id="1084777750" cached="false"/>
    </resource>
</clone>
```

2. Now we need to match those by SID. This information is available throug `cibadmin.xml`:


```xml
<master id="msl_SAPHana_XXX_HDB00">
<meta_attributes id="msl_SAPHana_XXX_HDB00-meta_attributes">
  <nvpair name="clone-max" value="2" id="msl_SAPHana_XXX_HDB00-meta_attributes-clone-max"/>
  <nvpair name="clone-node-max" value="1" id="msl_SAPHana_XXX_HDB00-meta_attributes-clone-node-max"/>
  <nvpair name="interleave" value="true" id="msl_SAPHana_XXX_HDB00-meta_attributes-interleave"/>
</meta_attributes>
<primitive id="rsc_SAPHana_XXX_HDB00" class="ocf" provider="suse" type="SAPHana">
  <instance_attributes id="rsc_SAPHana_XXX_HDB00-instance_attributes">
    <nvpair name="SID" value="XXX" id="rsc_SAPHana_XXX_HDB00-instance_attributes-SID"/>
    <nvpair name="InstanceNumber" value="00" id="rsc_SAPHana_XXX_HDB00-instance_attributes-InstanceNumber"/>
    <nvpair name="PREFER_SITE_TAKEOVER" value="true" id="rsc_SAPHana_XXX_HDB00-instance_attributes-PREFER_SITE_TAKEOVER"/>
    <nvpair name="AUTOMATED_REGISTER" value="false" id="rsc_SAPHana_XXX_HDB00-instance_attributes-AUTOMATED_REGISTER"/>
    <nvpair name="DUPLICATE_PRIMARY_TIMEOUT" value="7200" id="rsc_SAPHana_XXX_HDB00-instance_attributes-DUPLICATE_PRIMARY_TIMEOUT"/>
  </instance_attributes>
  <operations>
    <op name="start" interval="0" timeout="3600" id="rsc_SAPHana_XXX_HDB00-start-0"/>
    <op name="stop" interval="0" timeout="3600" id="rsc_SAPHana_XXX_HDB00-stop-0"/>
    <op name="promote" interval="0" timeout="3600" id="rsc_SAPHana_XXX_HDB00-promote-0"/>
    <op name="monitor" interval="60" role="Master" timeout="700" id="rsc_SAPHana_XXX_HDB00-monitor-60"/>
    <op name="monitor" interval="61" role="Slave" timeout="700" id="rsc_SAPHana_XXX_HDB00-monitor-61"/>
  </operations>
</primitive>
</master>
<clone id="cln_SAPHanaTopology_XXX_HDB00">
<meta_attributes id="cln_SAPHanaTopology_XXX_HDB00-meta_attributes">
  <nvpair name="is-managed" value="true" id="cln_SAPHanaTopology_XXX_HDB00-meta_attributes-is-managed"/>
  <nvpair name="clone-node-max" value="1" id="cln_SAPHanaTopology_XXX_HDB00-meta_attributes-clone-node-max"/>
  <nvpair name="interleave" value="true" id="cln_SAPHanaTopology_XXX_HDB00-meta_attributes-interleave"/>
</meta_attributes>
<primitive id="rsc_SAPHanaTopology_XXX_HDB00" class="ocf" provider="suse" type="SAPHanaTopology">
  <instance_attributes id="rsc_SAPHanaTopology_XXX_HDB00-instance_attributes">
    <nvpair name="SID" value="XXX" id="rsc_SAPHanaTopology_XXX_HDB00-instance_attributes-SID"/>
    <nvpair name="InstanceNumber" value="00" id="rsc_SAPHanaTopology_XXX_HDB00-instance_attributes-InstanceNumber"/>
  </instance_attributes>
  <operations>
    <op name="monitor" interval="10" timeout="600" id="rsc_SAPHanaTopology_XXX_HDB00-monitor-10"/>
    <op name="start" interval="0" timeout="600" id="rsc_SAPHanaTopology_XXX_HDB00-start-0"/>
    <op name="stop" interval="0" timeout="300" id="rsc_SAPHanaTopology_XXX_HDB00-stop-0"/>
  </operations>
</primitive>
</clone>
```