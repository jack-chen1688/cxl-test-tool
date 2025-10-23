# How DCD works in Qemu Emulation - One VM case

## Table of Contents

- [How DCD works in Qemu Emulation - One VM case](#how-dcd-works-in-qemu-emulation---one-vm-case)
  - [Table of Contents](#table-of-contents)
  - [Create region](#create-region)
    - [Check memdev size](#check-memdev-size)
    - [create a region based on the sizego](#create-a-region-based-on-the-sizego)
    - [Kernel Log](#kernel-log)
  - [Add Dynamic Capacity](#add-dynamic-capacity)
      - [Add an exent of 0-128MB](#add-an-exent-of-0-128mb)
    - [QMP command sent by the cxl-tool.py](#qmp-command-sent-by-the-cxl-toolpy)
    - [Qemu handles cxl-add-dynamic-capacity](#qemu-handles-cxl-add-dynamic-capacity)
    - [Kernel processes the DCD event](#kernel-processes-the-dcd-event)
- [How DCD works in Qemu Emulation - Two VMs case](#how-dcd-works-in-qemu-emulation---two-vms-case)

## Create region
### Check memdev size
```
$./cxl-tool.py -C "cxl list -i -m mem0"
[
  {
    "memdev":"mem0",
    "dynamic_ram_a_size":2147483648,
    "serial":3841,
    "host":"0000:10:00.0",
    "firmware_version":"BWFW VERSION 00"
  }
]
```
### create a region based on the sizego 
cxl create-region -m mem0 -d decoder0.0 -s 2147483648 -t dynamic_ram_a

### Kernel Log
``` 
[ 7929.099585] cxl_core:cxl_region_probe:3571: cxl_region region0: config state: 0
[ 7929.100130] cxl_core:cxl_bus_probe:2087: cxl_region region0: probe: -6
[ 7929.100564] cxl_core:devm_cxl_add_region:2535: cxl_acpi ACPI0017:00: decoder0.0: created region0
[ 7929.104160] cxl_core:cxl_port_attach_region:1169: cxl region0: mem0:endpoint3 decoder3.0 add: mem0:decoder3.0 @ 0 next: none nr_eps: 1 nr_targets: 1
[ 7929.104938] cxl_core:cxl_port_attach_region:1169: cxl region0: 0000:0e:00.0:port2 decoder2.0 add: mem0:decoder3.0 @ 0 next: mem0 nr_eps: 1 nr_targets: 1
[ 7929.105754] cxl_core:cxl_port_attach_region:1169: cxl region0: pci0000:0c:port1 decoder1.0 add: mem0:decoder3.0 @ 0 next: 0000:0e:00.0 nr_eps: 1 nr_targets: 1
[ 7929.106599] cxl_core:cxl_port_setup_targets:1489: cxl region0: pci0000:0c:port1 iw: 1 ig: 256
[ 7929.107126] cxl_core:cxl_port_setup_targets:1513: cxl region0: pci0000:0c:port1 target[0] = 0000:0c:01.0 for mem0:decoder3.0 @ 0
[ 7929.107859] cxl_core:cxl_port_setup_targets:1489: cxl region0: 0000:0e:00.0:port2 iw: 1 ig: 256
[ 7929.108424] cxl_core:cxl_port_setup_targets:1513: cxl region0: 0000:0e:00.0:port2 target[0] = 0000:0f:00.0 for mem0:decoder3.0 @ 0
[ 7929.109229] cxl_core:cxl_calc_interleave_pos:1880: cxl_mem mem0: decoder:decoder3.0 parent:0000:10:00.0 port:endpoint3 range:0x1290000000-0x130fffffff pos:0
[ 7929.110393] cxl_core:cxl_region_attach:2080: cxl decoder3.0: Test cxl_calc_interleave_pos(): success test_pos:0 cxled->pos:0
non interleaved decoder 1290000000 80000000 0
non interleaved decoder 1290000000 80000000 0
dumb commit
non interleaved decoder 1290000000 80000000 0
dumb commit
[ 7929.112959] cxl_core:cxl_bus_probe:2087: cxl_dax_region dax_region0: probe: 0
[ 7929.113394] cxl_core:devm_cxl_add_dax_region:3251: cxl_region region0: region0: register dax_region0
[ 7929.113948] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x4801    
```

We can see that Get Dynamic Capacity Extent List command (0x4801) is issued by the kernel when creating the region.

```
[ 7929.114460] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[ 7929.115017] cxl_core:__cxl_process_extent_list:1803: cxl_pci 0000:10:00.0: Got extent list 0--1 of 0 generation Num:0
[ 7929.115628] cxl_core:cxl_bus_probe:2087: cxl_region region0: probe: 0
```


## Add Dynamic Capacity

#### Add an exent of 0-128MB
```
$ ./cxl-tool.py --dcd-test mem0
region0 already created for mem0, exit
sn=3841
cxl-memdev1
sn=3841
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 0
Input extent to add, for example (unit: MB): 0-128[,128-256]
Extents: 0-128
cat /tmp/qmp-add.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886-dirty"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
```

### QMP command sent by the cxl-tool.py

In the above seqenuce, cxl-tool.py will create write the following command to the /tmp/qmp-add.json.
```
$ cat /tmp/qmp-add.json 
{
    "execute": "qmp_capabilities"
}{
    "execute": "cxl-add-dynamic-capacity",
    "arguments": {
        "path": "/machine/peripheral/cxl-memdev1",
        "host-id": 0,
        "selection-policy": "prescriptive",
        "region": 0,
        "extents": [
            {
                "offset": 0,
                "len": 134217728
            }
        ]
    }
```
Then it will exuecute "cat /tmp/qmp-add.json |ncat localhost $qmp_port"

### Qemu handles cxl-add-dynamic-capacity

Qemu will call qmp_cxl_add_dynamic_capacity function to process the command. Based on the policy of "prescriptive",  
qmp_cxl_process_dynamic_capacity_prescriptive will be called with DC_EVENT_ADD_CAPACITY. This function will   
do sanity check like block size alignment, range within the region, etc... If OK, the extent will be added for   
the mem device. An event will be generated and interrupt will be asserted to let host know.

### Kernel processes the DCD event
The correponding kernel log is below.
```
[ 9130.419501] cxl_core:cxl_mem_get_event_records:1412: cxl_pci 0000:10:00.0: Reading event logs: 10
```
10 is the hex value from the event status register, bit 4 (CXLDEV_EVENT_STATUS_DCD) is set.
cxl_mem_get_records_log(mds, CXL_EVENT_TYPE_DCD) will be called

```
[ 9130.420061] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x0100
[ 9130.420574] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[ 9130.421245] cxl_core:cxl_handle_dcd_event_records:1316: cxl_pci 0000:10:00.0: DCD event add : DPA:0x0 LEN:0x8000000
[ 9130.421854] cxl_core:cxl_validate_extent:975: cxl_pci 0000:10:00.0: DC extent DPA [range 0x0000000000000000-0x0000000007ffffff] (DCR:[range 0x0000000000000000-0x000000007fffffff])(00000000-0000-0000-0000-000000000000)
[ 9130.422985] cxl_core:__cxl_dpa_to_region:2869: cxl decoder3.0: dpa:0x0 mapped in region:region0
[ 9130.423516] cxl_core:cxl_add_extent:460: cxl decoder3.0: Checking ED ([mem 0x00000000-0x7fffffff flags 0x80000200]) for extent [range 0x0000000000000000-0x0000000007ffffff]
[ 9130.424762] cxl_core:cxl_add_extent:492: cxl decoder3.0: Add extent [range 0x0000000000000000-0x0000000007ffffff] (00000000-0000-0000-0000-000000000000)
[ 9130.426218] cxl_core:online_region_extent:176:  extent0.0: region extent HPA [range 0x0000000000000000-0x0000000007ffffff]
[ 9130.427400] cxl_core:cxlr_notify_extent:285: cxl_dax_region dax_region0: Trying notify: type 0 HPA [range 0x0000000000000000-0x0000000007ffffff]
[ 9130.428788] cxl_core:cxlr_notify_extent:305: cxl_dax_region dax_region0: Notify: type 0 HPA [range 0x0000000000000000-0x0000000007ffffff]
[ 9130.430128] dax:dax_region_add_resource:222: cxl_dax_region dax_region0: DAX region resource [mem 0x1290000000-0x130fffffff flags 0x206]
[ 9130.431429] dax:dax_region_add_resource:230: cxl_dax_region dax_region0: add resource [mem 0x1290000000-0x1297ffffff flags 0x80000200]
```
Kernel send a command of "Get Event Records" (0x0100) to retrieve the DCD event and processed it. 

```
[ 9130.432809] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x4802
[ 9130.433830] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[ 9130.434394] cxl_core:cxl_clear_event_record:1099: cxl_pci 0000:10:00.0: Event log '4': Clearing 1
[ 9130.434927] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x0101
[ 9130.435444] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[ 9130.435991] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x0100
[ 9130.436519] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
```

Kernel issues three commands below.
Add Dynamic Capacity Response - 0x4802
Clear Event Records           - 0x0101
Get Event Records             - 0x0100









# How DCD works in Qemu Emulation - Two VMs case