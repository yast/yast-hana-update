# Manual testing of the module

1. Install SAP HANA 2.0
from `f102.suse.de:/home/ilya/sap_inst_media/51051635`.
2. Create cluster using `sap_ha` module.
3. Run `hana_updater`, select SAP HANA 2.0 SPS01 update medium `f102.suse.de:/home/ilya/sap_inst_media/51052030`.
4. Update both instances.

```
mount NFS: true
path: f102.suse.de:/home/ilya/sap_inst_media/51052030
copy: true
where: /hana/upd

HDB LCM: https://localhost:1129/lmsl/HDBLCM/PRD/index.html
```

