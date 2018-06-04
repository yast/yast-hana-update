for hana01 (sap13)

<disk type="block" device="disk">
    <driver name="qemu" type="raw"/>
    <source dev="/dev/disk/by-id/raid-sap13-data130"/>
    <target dev="vdd" bus="virtio"/>
    <address type="pci" domain="0x0000" bus="0x00" slot="0x10" function="0x0"/>
</disk>

for hana02 (sap14)

<disk type="block" device="disk">
    <driver name="qemu" type="raw"/>
    <source dev="/dev/disk/by-id/raid-sap14-data140"/>
    <target dev="vdd" bus="virtio"/>
    <address type="pci" domain="0x0000" bus="0x00" slot="0x10" function="0x0"/>
</disk>

---

Mounts

`/dev/vdc   /hana   xfs     rw,realtime,attr2,inode64,noquota   0 0`