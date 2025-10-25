# 1. Experiment DCD using QEMU

## 1.1. Test Environment

- **OS**: Ubuntu 24.04
- **Software**: https://github.com/moking/cxl-test-tool
- **Base Commit**: d55e292 (2025-07-15)

## 1.2. Acronym Definition

| Acronym | Definition |
|---------|------------|
| FM | Fabric Manager |
| DCD | Dynamic Capacity Device |

## 1.3. Useful Commands

### 1.3.1. VM Access

```
# Log into the VM
./cxl-tool.py --login

# Log into the FM VM
./cxl-tool.py --login-fm
```


## 1.4. QEMU Environment Setup

### 1.4.1. Set up .vars.config

Created `.vars.config` using `run_vars.example.fm-dcd` as base:

```bash
run_opts_file=/tmp/run_opts
dbg_opt="cxl_acpi.dyndbg=+fplm cxl_pci.dyndbg=+fplm cxl_core.dyndbg=+fplm cxl_mem.dyndbg=+fplm cxl_pmem.dyndbg=+fplm cxl_port.dyndbg=+fplm cxl_region.dyndbg=+fplm cxl_test.dyndbg=+fplm cxl_mock.dyndbg=+fplm cxl_mock_mem.dyndbg=+fplm dax.dyndbg=+fplm dax_cxl.dyndbg=+fplm device_dax.dyndbg=+fplm"
edac_debug="edac_debug_level=4"
KERNEL_CMD="root=/dev/sda rw console=ttyS0,115200 ignore_loglevel nokaslr ${dbg_opt} ${edac_debug}"
SHARED_CFG="-qmp tcp:localhost:4444,server,wait=off"
ssh_port=2024
net_config="-netdev user,id=network0,hostfwd=tcp::${ssh_port}-:22 -device e1000,netdev=network0" 
#user name for the VM, by default it is "root"
vm_usr="root"
accel_mode="kvm"
cxl_test_tool_dir="~/cxl/cxl-test-tool/"
cxl_test_log_dir="/tmp/cxl-logs/"
cxl_host_dir="/tmp/host/"

#DCD 
QEMU_ROOT=~/cxl/jic/qemu/
QEMU_IMG=~/cxl/images/qemu-image.img
FM_KERNEL_ROOT=~/cxl/linux-v6.6-rc6
FM_QEMU_IMG=~/cxl/images/qemu-image-fm.img

qemu_branch='dcd-compression'
qemu_url="git+ssh://git@github.com/moking/qemu-jic-clone.git"
KERNEL_ROOT=/home/fan/cxl/linux-dcd
kernel_url="https://github.com/weiny2/linux-kernel.git"
kernel_branch="dcd-v6-2025-04-13"
ndctl_url="https://github.com/weiny2/ndctl.git"
ndctl_branch="dcd-region3-2025-04-13"
libcxlmi_branch="fixes"
libcxlmi_url="https://github.com/moking/libcxlmi.git"
```

### 1.4.2. Build QEMU

```
./cxl-tool.py --setup-qemu
```

This will build the QEMU executable inside `QEMU_ROOT`:
```
~/cxl/jic/qemu/build/qemu-system-x86_64
```

### 1.4.3. Create QEMU Image

```
./cxl-tool.py --create-image
```

This creates an image at `~/cxl/images/qemu-image.img`, which corresponds to `$QEMU_IMG` in `.vars.config`.

### 1.4.4. Setup Kernel

Run the command below and select option **2** when prompted:

```
./cxl-tool.py --setup-kernel
```

**Example output:**
```
git clone -b "dcd-v6-2025-04-13" --single-branch "https://github.com/weiny2/linux-kernel.git" /home/jack/cxl/linux-dcd
Cloning into '/home/jack/cxl/linux-dcd'...
remote: Enumerating objects: 10786612, done.
remote: Counting objects: 100% (703157/703157), done.
remote: Compressing objects: 100% (15699/15699), done.
Receiving objects: 100% (10786612/10786612), 2.51 GiB | 29.40 MiB/s, done.
remote: Total 10786612 (delta 694243), reused 688728 (delta 687458), pack-reused 10083455 (from 3)
Resolving deltas: 100% (9132578/9132578), done.
Updating files: 100% (88821/88821), done.
.config not found, configure mannually (1) or copy the example config (2): 2
cp /home/jack/work/cxl-test-tool//kconfig.example /home/jack/cxl/linux-dcd/.config
```

> **Note**: For new config options, press Enter to select the default.

This command will build the kernel in `~/cxl/linux-dcd`.



## 1.5. Test DCD on One VM

### 1.5.1. Create a Topology

Based on `.cxl-topology.xml.bak`, create the file `.cxl-topology.xml` as follows:

```
<cxl>
    <host_bridge>
        <rp>dcd</rp>
        <rp>
            <switch>
                <!--pmem/vmem/mixed/mixed-dcd/dcd-->
                <dsp id="1">dcd</dsp> 
            </switch>
        </rp>
    </host_bridge>
    <!--1 fmw for one HB, in order -->
    <fmw size="4G" ig="8K"> </fmw>
</cxl>
```

### 1.5.2. Run QEMU with the Created Topology

```
./cxl-tool.py --create-topo --run
```

**Example output:**
```
Info: back memory/lsa file exist under /tmp/host0 from previous run, delete them Y/N(default Y): Y
Starting VM...
QEMU instance is up, access it: ssh root@localhost -p 2024
```

### 1.5.3. Configure DNS Server

> **Issue**: By default, `/etc/resolv.conf` inside the QEMU image uses `8.8.8.8` as DNS server, which does not work.

**Solution**: Change it to `10.0.2.3`:

```
ssh root@localhost -p 2024 "sed -i 's/8.8.8.8/10.0.2.3/g' /etc/resolv.conf"
```

With this change, you can install packages inside the VM using `apt`.

### 1.5.4. Install ndctl

#### 1.5.4.1. Install Prerequisite Package

ndctl cannot be compiled by default due to missing `systemd-dev`:

```
./cxl-tool.py -C "apt install -y systemd-dev"
```

#### 1.5.4.2. Install ndctl

```
./cxl-tool.py --install-ndctl
```



## 1.6. Run DCD Test

### 1.6.1. Fix for Latest Commit Issue

> **Note**: Latest commit `d55e292` has a small issue where the default mode is `ram_a`:
> ```
> parser.add_argument('-M','--mode', help='DC decoder mode (ram_a)',
>                     required=False, default="ram_a")
> ```
> This will cause `./cxl-tool.py --dcd-test mem0` to fail.

There are two ways to solve it. 

#### 1.6.1.1. Option 1: Modify the `dc_region_idx` function in `utils/dcd.py`

```
def dc_region_idx():
    mode = os.getenv("dc_mode", "")
    if not mode:
        return 0;
    m = mode.split("_")
    if not m or len(m) < 3:
        return 0
    try:
        return int(m[2])
    except ValueError:
        # If the suffix is not a number (like 'a'), map it to a number
        # 'a' -> 0, 'b' -> 1, etc.
        # 'a' -> 0, 'b' -> 1, etc.
        if m[2].isalpha() and len(m[2]) == 1:
            return ord(m[2].lower()) - ord('a')
        return 0
```

With this change, `./cxl-tool.py --dcd-test mem0` works without problem.

#### 1.6.1.2. Option 2: Run with explicit mode parameter

```
./cxl-tool.py --dcd-test mem0 -M ram_0
```



### 1.6.2. Create a DC Region, Add an Extent, and Create a DAX Device

After modifying `dc_region_idx`, run the following command:

```
./cxl-tool.py --dcd-test mem0
```

**Example output:**

```
Load cxl drivers first
ssh root@localhost -p 2024 "modprobe -a cxl_acpi cxl_core cxl_pci cxl_port cxl_mem"

Module                  Size  Used by
dax_pmem               12288  0
device_dax             20480  0
nd_pmem                24576  0
nd_btt                 28672  1 nd_pmem
dax                    57344  3 dax_pmem,device_dax,nd_pmem
cxl_mem                12288  0
cxl_pmem               24576  0
libnvdimm             208896  4 cxl_pmem,dax_pmem,nd_btt,nd_pmem
cxl_pci                28672  0
cxl_acpi               24576  0
cxl_port               16384  0
cxl_core              356352  7 cxl_pmem,cxl_port,cxl_mem,cxl_pci,cxl_acpi
```

**Continued output:**

```
ssh root@localhost -p 2024 "cxl enable-memdev mem0"
cxl memdev: cmd_enable_memdev: enabled 1 mem
{
  "region":"region0",
  "resource":79725330432,
  "size":2147483648,
  "interleave_ways":1,
  "interleave_granularity":256,
  "decode_state":"commit",
  "mappings":[
    {
      "position":0,
      "memdev":"mem0",
      "decoder":"decoder2.0"
    }
  ]
}
cxl region: cmd_create_region: created 1 region
sn=3840
cxl-memdev0
sn=3840
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 0
Input extent to add, for example (unit: MB): 0-128[,128-256]
Extents: 0-128
cat /tmp/qmp-add.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 2
cat /tmp/qmp-show.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
{"return": {}}
Print accepted extent info:
0: [0x0 - 0x8000000]
In total, 1 extents printed!
Print pending-to-add extent info:
In total, 0 extents printed!
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 9
Do you want to continue to create dax device for DC(Y/N):Y
daxctl create-device -r region0
[
  {
    "chardev":"dax0.1",
    "size":134217728,
    "target_node":1,
    "align":2097152,
    "mode":"devdax"
  }
]
created 1 device
daxctl list -r region0 -D
[
  {
    "chardev":"dax0.1",
    "size":134217728,
    "target_node":1,
    "align":2097152,
    "mode":"devdax"
  }
]
ssh root@localhost -p 2024 "daxctl reconfigure-device dax0.1 -m system-ram"
reconfigured 1 device
[
  {
    "chardev":"dax0.1",
    "size":134217728,
    "target_node":1,
    "align":2097152,
    "mode":"system-ram",
    "online_memblocks":1,
    "total_memblocks":1,
    "movable":true
  }
]
RANGE                                  SIZE  STATE REMOVABLE BLOCK
0x0000000000000000-0x000000007fffffff    2G online       yes  0-15
0x0000000100000000-0x000000027fffffff    6G online       yes 32-79
0x0000001290000000-0x0000001297ffffff  128M online       yes   594

Memory block size:                128M
Total online memory:              8.1G
Total offline memory:               0B
```



### 1.6.3. Destroy the DAX Device, Release Extent, Add a Different Extent

> **Important**: You need to reconfigure the DAX device to `devdax` mode and destroy the device. Otherwise, recreating a DAX device will fail with an error.

#### 1.6.3.1. Step 1: Destroy the DAX Device

```
./cxl-tool.py --login
```

**Inside the VM:**

```
# List DAX devices
daxctl list
[
  {
    "chardev":"dax0.1",
    "size":134217728,
    "target_node":1,
    "align":2097152,
    "mode":"system-ram",
    "online_memblocks":1,
    "total_memblocks":1,
    "movable":true
  }
]

# Offline memory
daxctl offline-memory dax0.1 
offlined memory for 1 device

# Reconfigure to devdax mode
daxctl reconfigure-device dax0.1 -m devdax
[
  {
    "chardev":"dax0.1",
    "size":134217728,
    "target_node":1,
    "align":2097152,
    "mode":"devdax"
  }
]
reconfigured 1 device

# Disable device
daxctl disable-device dax0.1          
disabled 1 device

# Destroy device
daxctl destroy-device dax0.1 
destroyed 1 device
```

#### 1.6.3.2. Step 2: Release Extent, Add New Extent, and Create DAX Device

```
./cxl-tool.py --dcd-test mem0
```

**Example interaction:**

```
region0 already created for mem0, exit
sn=3840
cxl-memdev0
sn=3840
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 1
Input extent to release, for example (unit: MB): 0-128[,128-256]
Extents: 0-128
cat /tmp/qmp-rm.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 2
cat /tmp/qmp-show.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
{"return": {}}
Print accepted extent info:
In total, 0 extents printed!
Print pending-to-add extent info:
In total, 0 extents printed!
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 0
Input extent to add, for example (unit: MB): 0-128[,128-256]
Extents: 0-128
cat /tmp/qmp-add.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 2
cat /tmp/qmp-show.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
{"return": {}}
Print accepted extent info:
0: [0x0 - 0x8000000]
In total, 1 extents printed!
Print pending-to-add extent info:
In total, 0 extents printed!
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 9
Do you want to continue to create dax device for DC(Y/N):Y
daxctl create-device -r region0
created 1 device
[
  {
    "chardev":"dax0.1",
    "size":134217728,
    "target_node":1,
    "align":2097152,
    "mode":"devdax"
  }
]
daxctl list -r region0 -D
[
  {
    "chardev":"dax0.1",
    "size":134217728,
    "target_node":1,
    "align":2097152,
    "mode":"devdax"
  }
]
ssh root@localhost -p 2024 "daxctl reconfigure-device dax0.1 -m system-ram"
reconfigured 1 device
[
  {
    "chardev":"dax0.1",
    "size":134217728,
    "target_node":1,
    "align":2097152,
    "mode":"system-ram",
    "online_memblocks":1,
    "total_memblocks":1,
    "movable":true
  }
]
RANGE                                  SIZE  STATE REMOVABLE BLOCK
0x0000000000000000-0x000000007fffffff    2G online       yes  0-15
0x0000000100000000-0x000000027fffffff    6G online       yes 32-79
0x0000001290000000-0x0000001297ffffff  128M online       yes   594

Memory block size:                128M
Total online memory:              8.1G
Total offline memory:               0B

```

## 1.7. Test DCD using Fabric Manager (FM) VM

### 1.7.1. Set up Kernel for FM

#### 1.7.1.1. Fix Code Error in utils/mctp.py

Below is the fix.
```
--- a/utils/mctp.py
+++ b/utils/mctp.py
@@ -167,7 +167,7 @@ def setup_kernel(kernel_dir):
         kpatch=test_dir+"/test-workflows/mctp/mctp-patches-kernel.patch"
         cmd="cd %s; git am --reject %s"%(dire, kpatch)
         tools.sh_cmd(cmd, echo=True)
-        tools.build_kernel(dire, install = False)
+        tools.build_kernel(dire)
     else:
         print("mctp patches already applied, continue...")
```
#### 1.7.1.2. Run Kernel Setup for FM

```
./cxl-tool.py --setup-kernel-fm
```

When prompted, make the appropriate selections.

**Example kernel configuration prompts:**

```
Applying: i2c-aspeed: comment out an unused local variable to avoid compile debug
Packages: bc
All packages are already installed, skip installing!
Do you want to run make menuconfig first before building (Y/N): N   # <-- User responds with N
cd /home/jack/cxl/linux-v6.6-rc6; make -j20
  SYNC    include/config/auto.conf.cmd
*
* Restart config...
*
* CXL (Compute Express Link) Devices Support
*
CXL (Compute Express Link) Devices Support (CXL_BUS) [M/n/y/?] m
  PCI manageability (CXL_PCI) [M/n/?] m
    Raw Command Interface for Memory Devices (CXL_MEM_RAW_COMMANDS) [Y/n/?] y
  CXL ACPI: Platform Support (CXL_ACPI) [M/n/?] m
  CXL: Persistent Memory Support (CXL_PMEM) [M/n/?] m
  CXL: Memory Expansion (CXL_MEM) [M/n/?] m
  CXL: Region Support (CXL_REGION) [Y/n/?] y
    CXL: Region Cache Management Bypass (TEST) (CXL_REGION_INVALIDATION_TEST) [Y/n/?] y
  CXL Performance Monitoring Unit (CXL_PMU) [M/n/?] m
  CXL PMEM: Persistent Memory Support (CXL_PMEM) [M/n/?] m
  CXL switch mailbox access (CXL_SWITCH) [N/m/?] (NEW) m   # <-- User responds with m
```

> **Tip**: The `test-workflows/fm-test.sh` script provides examples of how to test FM.

### 1.7.2. Run VM with FM_TARGET Topology

```
./cxl-tool.py --run -T FM_TARGET
```

**Example output:**

```
Info: back memory/lsa file exist under /tmp/host0 from previous run, delete them Y/N(default Y): Y
Starting VM...
QEMU instance is up, access it: ssh root@localhost -p 2024
```

### 1.7.3. Create a Region on FM_TARGET VM

```
./cxl-tool.py --create-dcR mem0
```

**Example output:**

```
Load cxl drivers
ssh root@localhost -p 2024 "modprobe -a cxl_acpi cxl_core cxl_pci cxl_port cxl_mem"

Module                  Size  Used by
dax_pmem               12288  0
device_dax             20480  0
nd_pmem                24576  0
nd_btt                 28672  1 nd_pmem
dax                    57344  3 dax_pmem,device_dax,nd_pmem
cxl_mem                12288  0
cxl_pmem               24576  0
libnvdimm             208896  4 cxl_pmem,dax_pmem,nd_btt,nd_pmem
cxl_pci                28672  0
cxl_acpi               24576  0
cxl_port               16384  0
cxl_core              356352  6 cxl_pmem,cxl_port,cxl_mem,cxl_pci,cxl_acpi
ssh root@localhost -p 2024 "cxl enable-memdev mem0"
cxl memdev: cmd_enable_memdev: enabled 1 mem
{
  "region":"region0",
  "resource":79725330432,
  "size":4294967296,
  "interleave_ways":1,
  "interleave_granularity":256,
  "decode_state":"commit",
  "mappings":[
    {
      "position":0,
      "memdev":"mem0",
      "decoder":"decoder3.0"
    }
  ]
}
cxl region: cmd_create_region: created 1 region
```

### 1.7.4. Run VM with FM_CLIENT Topology

#### 1.7.4.1. Create FM Image

Use `qemu-image.img` as base for `qemu-image-fm.img`:

```
cp ~/cxl/images/qemu-image.img ~/cxl/images/qemu-image-fm.img
```

#### 1.7.4.2. Run FM Client VM

```
./cxl-tool.py --attach-fm -T FM_CLIENT
```

**Example output:**

```
Info: back memory/lsa file exist under /tmp/host1 from previous run, delete them Y/N(default Y): Y
Starting VM...
QEMU instance is up, access it: ssh root@localhost -p 2025
```

### 1.7.5. Install libcxlmi-fm

```
./cxl-tool.py --install-libcxlmi-fm
```

**Example output (partial):**

```
jack@jack-MS-7D30:~/work/cxl-test-tool1$ ./cxl-tool.py --install-libcxlmi-fm
The authenticity of host '[localhost]:2025 ([127.0.0.1]:2025)' can't be established.
ED25519 key fingerprint is SHA256:koyrM2rZsmN01ikE6s2axDdUJYxRZGTEBEFqaseVofY.
This host key is known by the following other names/addresses:
    ~/.ssh/known_hosts:1: [hashed name]
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
ssh root@localhost -p 2025 "rm -rf /tmp/libcxlmi"

Reading package lists...
Building dependency tree...
Reading state information...
The following additional packages will be installed:
  sgml-base xml-core
Suggested packages:
  sgml-base-doc debhelper
The following NEW packages will be installed:
  libdbus-1-dev sgml-base xml-core
0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded.
Need to get 246 kB of archives.
After this operation, 1156 kB of additional disk space will be used.
Get:1 http://deb.debian.org/debian stable/main amd64 sgml-base all 1.31+nmu1 [10.9 kB]
Get:2 http://deb.debian.org/debian stable/main amd64 xml-core all 0.19 [20.1 kB]
Get:3 http://deb.debian.org/debian stable/main amd64 libdbus-1-dev amd64 1.16.2-2 [215 kB]
perl: warning: Setting locale failed.
perl: warning: Please check that your locale settings:
        LANGUAGE = (unset),
        LC_ALL = (unset),
        LC_CTYPE = (unset),
        LC_NUMERIC = (unset),
        LC_COLLATE = (unset),
        LC_TIME = (unset),
        LC_MESSAGES = (unset),
        LC_MONETARY = (unset),
        LC_ADDRESS = (unset),
        LC_IDENTIFICATION = (unset),
        LC_MEASUREMENT = (unset),
        LC_PAPER = (unset),
        LC_TELEPHONE = (unset),
        LC_NAME = (unset),
        LANG = "en_US.UTF-8"
    are supported and installed on your system.
perl: warning: Falling back to the standard locale ("C").
locale: Cannot set LC_CTYPE to default locale: No such file or directory
locale: Cannot set LC_MESSAGES to default locale: No such file or directory
locale: Cannot set LC_ALL to default locale: No such file or directory
debconf: unable to initialize frontend: Dialog
debconf: (TERM is not set, so the dialog frontend is not usable.)
debconf: falling back to frontend: Readline
debconf: unable to initialize frontend: Readline
debconf: (This frontend requires a controlling tty.)
debconf: falling back to frontend: Teletype
debconf: unable to initialize frontend: Teletype
debconf: (This frontend requires a controlling tty.)
debconf: falling back to frontend: Noninteractive
Fetched 246 kB in 0s (1002 kB/s)
Selecting previously unselected package sgml-base.
(Reading database ... 
(Reading database ... 5%
(Reading database ... 10%
(Reading database ... 15%
(Reading database ... 20%
(Reading database ... 25%
(Reading database ... 30%
(Reading database ... 35%
(Reading database ... 40%
(Reading database ... 45%
(Reading database ... 50%
(Reading database ... 55%
(Reading database ... 60%
(Reading database ... 65%
(Reading database ... 70%
(Reading database ... 75%
(Reading database ... 80%
(Reading database ... 85%
(Reading database ... 90%
(Reading database ... 95%
(Reading database ... 100%
(Reading database ... 36959 files and directories currently installed.)
Preparing to unpack .../sgml-base_1.31+nmu1_all.deb ...
Unpacking sgml-base (1.31+nmu1) ...
Selecting previously unselected package xml-core.
Preparing to unpack .../archives/xml-core_0.19_all.deb ...
Unpacking xml-core (0.19) ...
Selecting previously unselected package libdbus-1-dev:amd64.
Preparing to unpack .../libdbus-1-dev_1.16.2-2_amd64.deb ...
Unpacking libdbus-1-dev:amd64 (1.16.2-2) ...
Setting up sgml-base (1.31+nmu1) ...
Setting up xml-core (0.19) ...
Processing triggers for sgml-base (1.31+nmu1) ...
Setting up libdbus-1-dev:amd64 (1.16.2-2) ...
ssh root@localhost -p 2025 "git clone -b fixes --single-branch https://github.com/moking/libcxlmi.git /tmp/libcxlmi"
Cloning into '/tmp/libcxlmi'...
ssh root@localhost -p 2025 "cd /tmp/libcxlmi; meson setup -Dlibdbus=enabled build; meson compile -C build;"
The Meson build system
Version: 1.7.0
Source dir: /tmp/libcxlmi
Build dir: /tmp/libcxlmi/build
Build type: native build
Project name: libcxlmi
Project version: 0.0.1
C compiler for the host machine: cc (gcc 14.2.0 "cc (Debian 14.2.0-19) 14.2.0")
C linker for the host machine: cc ld.bfd 2.44
Host machine cpu family: x86_64
Host machine cpu: x86_64
C++ compiler for the host machine: c++ (gcc 14.2.0 "c++ (Debian 14.2.0-19) 14.2.0")
C++ linker for the host machine: c++ ld.bfd 2.44
Found pkg-config: YES (/usr/bin/pkg-config) 1.8.1
Run-time dependency dbus-1 found: YES 1.16.2
Checking if "typeof" compiles: YES 
Checking if "byteswap.h" compiles: YES 
Checking if "bswap64" links: YES 
Checking if "linux/mctp.h" compiles: YES 
Checking if "linux/cxl_mem.h" compiles: YES 
Checking if "ioctl has glibc-style prototype" compiles: YES 
Checking if "gcc has dynamic object size" compiles: YES 
Configuring config.h using configuration
Build targets in project: 6

libcxlmi 0.0.1

  Paths
    prefixdir     : /usr/local
    bindir        : /usr/local/bin
    includedir    : /usr/local/include
    libdir        : /usr/local/lib/x86_64-linux-gnu
    build location: /tmp/libcxlmi/build

  Dependencies
    libdbus       : true

  User defined options
    libdbus       : enabled

Found ninja-1.12.1 at /usr/bin/ninja
ninja: Entering directory `/tmp/libcxlmi/build'
[1/17] Compiling C object ccan/libccan.a.p/ccan_str_debug.c.o
[2/17] Compiling C object ccan/libccan.a.p/ccan_str_str.c.o
[3/17] Compiling C object src/libcxlmi.so.p/cxlmi_log.c.o
[4/17] Compiling C object ccan/libccan.a.p/ccan_list_list.c.o
[5/17] Linking static target ccan/libccan.a
[6/17] Compiling C object tests/api-simple-tests.p/api-simple-tests.c.o
[7/17] Compiling C object examples/cxl-dcd.p/cxl-dcd.c.o
[8/17] Compiling C object examples/cxl-ioctl.p/cxl-ioctl.c.o
[9/17] Compiling C object examples/cxl-mctp.p/cxl-mctp.c.o
../examples/cxl-mctp.c:710:12: warning: 'test_fmapi_set_dc_region_config' defined but not used [-Wunused-function]
  710 | static int test_fmapi_set_dc_region_config(struct cxlmi_endpoint *ep)
      |            ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[10/17] Compiling C object src/libcxlmi.so.p/cxlmi_cxlmi.c.o
[11/17] Compiling C object src/libcxlmi.so.p/cxlmi_commands.c.o
[12/17] Linking target src/libcxlmi.so
[13/17] Generating symbol file src/libcxlmi.so.p/libcxlmi.so.symbols
[14/17] Linking target examples/cxl-dcd
[15/17] Linking target examples/cxl-ioctl
[16/17] Linking target tests/api-simple-tests
[17/17] Linking target examples/cxl-mctp
INFO: autodetecting backend as ninja
INFO: calculating backend command to run: /usr/bin/ninja -C /tmp/libcxlmi/build
INFO: Install libcxlmi succeeded, run /tmp/libcxlmi/build/examples/cxl-mctp on VM to test
```

### 1.7.6. Set up MCTP-FM

```
./cxl-tool.py --setup-mctp-fm
```

**Example output:**

```
/home/jack/work/cxl-test-tool//test-workflows/mctp.sh
Reading package lists...
Building dependency tree...
Reading state information...
The following additional packages will be installed:
  python3-iniconfig python3-packaging python3-pluggy
The following NEW packages will be installed:
  python3-iniconfig python3-packaging python3-pluggy python3-pytest
0 upgraded, 4 newly installed, 0 to remove and 0 not upgraded.
Need to get 340 kB of archives.
After this operation, 1674 kB of additional disk space will be used.
Get:1 http://deb.debian.org/debian stable/main amd64 python3-iniconfig all 1.1.1-2 [6396 B]
Get:2 http://deb.debian.org/debian stable/main amd64 python3-packaging all 25.0-1 [56.6 kB]
Get:3 http://deb.debian.org/debian stable/main amd64 python3-pluggy all 1.5.0-1 [26.9 kB]
Get:4 http://deb.debian.org/debian stable/main amd64 python3-pytest all 8.3.5-2 [250 kB]
perl: warning: Setting locale failed.
perl: warning: Please check that your locale settings:
        LANGUAGE = (unset),
        LC_ALL = (unset),
        LC_CTYPE = (unset),
        LC_NUMERIC = (unset),
        LC_COLLATE = (unset),
        LC_TIME = (unset),
        LC_MESSAGES = (unset),
        LC_MONETARY = (unset),
        LC_ADDRESS = (unset),
        LC_IDENTIFICATION = (unset),
        LC_MEASUREMENT = (unset),
        LC_PAPER = (unset),
        LC_TELEPHONE = (unset),
        LC_NAME = (unset),
        LANG = "en_US.UTF-8"
    are supported and installed on your system.
perl: warning: Falling back to the standard locale ("C").
locale: Cannot set LC_CTYPE to default locale: No such file or directory
locale: Cannot set LC_MESSAGES to default locale: No such file or directory
locale: Cannot set LC_ALL to default locale: No such file or directory
debconf: unable to initialize frontend: Dialog
debconf: (TERM is not set, so the dialog frontend is not usable.)
debconf: falling back to frontend: Readline
debconf: unable to initialize frontend: Readline
debconf: (This frontend requires a controlling tty.)
debconf: falling back to frontend: Teletype
debconf: unable to initialize frontend: Teletype
debconf: (This frontend requires a controlling tty.)
debconf: falling back to frontend: Noninteractive
Fetched 340 kB in 0s (2008 kB/s)
Selecting previously unselected package python3-iniconfig.
(Reading database ... 
(Reading database ... 5%
(Reading database ... 10%
(Reading database ... 15%
(Reading database ... 20%
(Reading database ... 25%
(Reading database ... 30%
(Reading database ... 35%
(Reading database ... 40%
(Reading database ... 45%
(Reading database ... 50%
(Reading database ... 55%
(Reading database ... 60%
(Reading database ... 65%
(Reading database ... 70%
(Reading database ... 75%
(Reading database ... 80%
(Reading database ... 85%
(Reading database ... 90%
(Reading database ... 95%
(Reading database ... 100%
(Reading database ... 37066 files and directories currently installed.)
Preparing to unpack .../python3-iniconfig_1.1.1-2_all.deb ...
Unpacking python3-iniconfig (1.1.1-2) ...
Selecting previously unselected package python3-packaging.
Preparing to unpack .../python3-packaging_25.0-1_all.deb ...
Unpacking python3-packaging (25.0-1) ...
Selecting previously unselected package python3-pluggy.
Preparing to unpack .../python3-pluggy_1.5.0-1_all.deb ...
Unpacking python3-pluggy (1.5.0-1) ...
Selecting previously unselected package python3-pytest.
Preparing to unpack .../python3-pytest_8.3.5-2_all.deb ...
Unpacking python3-pytest (8.3.5-2) ...
Setting up python3-iniconfig (1.1.1-2) ...
Setting up python3-packaging (25.0-1) ...
Setting up python3-pluggy (1.5.0-1) ...
Setting up python3-pytest (8.3.5-2) ...
install mctp program
ssh root@localhost -p 2025 "git clone https://github.com/CodeConstruct/mctp.git ~/mctp"
Cloning into '/root/mctp'...
ssh root@localhost -p 2025 "cd ~/mctp; git reset --hard 69ed224ff9b5206ca7f3a5e047a9da61377d2ca7"
HEAD is now at 69ed224 README: Add AssignEndpointStatic to dbus introspection output
ssh root@localhost -p 2025 "cd ~/mctp; meson setup obj; ninja -C obj; meson install -C obj"
The Meson build system
Version: 1.7.0
Source dir: /root/mctp
Build dir: /root/mctp/obj
Build type: native build
Project name: mctp
Project version: v1.1
C compiler for the host machine: cc (gcc 14.2.0 "cc (Debian 14.2.0-19) 14.2.0")
C linker for the host machine: cc ld.bfd 2.44
Host machine cpu family: x86_64
Host machine cpu: x86_64
Found pkg-config: YES (/usr/bin/pkg-config) 1.8.1
Run-time dependency libsystemd found: YES 257
Has header "linux/mctp.h" : YES 
Configuring config.h using configuration
Program pytest found: YES (/usr/bin/pytest)
Program sh found: YES (/usr/bin/sh)
Program dbus-run-session found: YES (/usr/bin/dbus-run-session)
Configuring pytest.ini using configuration
Build targets in project: 5

Found ninja-1.12.1 at /usr/bin/ninja
ninja: Entering directory `obj'
[1/21] Compiling C object mctp.p/src_mctp-ops.c.o
[2/21] Compiling C object mctp.p/src_mctp-util.c.o
[3/21] Compiling C object mctp-echo.p/src_mctp-util.c.o
[4/21] Compiling C object mctp-echo.p/src_mctp-echo.c.o
[5/21] Compiling C object mctp-req.p/src_mctp-req.c.o
[6/21] Compiling C object mctp-req.p/src_mctp-util.c.o
[7/21] Compiling C object mctpd.p/src_mctp-util.c.o
[8/21] Compiling C object mctpd.p/src_mctp-ops.c.o
[9/21] Compiling C object test-mctpd.p/tests_mctp-ops-test.c.o
[10/21] Compiling C object test-mctpd.p/src_mctp-util.c.o
[11/21] Linking target mctp-req
[12/21] Compiling C object mctp.p/src_mctp-netlink.c.o
[13/21] Compiling C object mctp.p/src_mctp.c.o
[14/21] Linking target mctp-echo
[15/21] Compiling C object mctpd.p/src_mctp-netlink.c.o
[16/21] Linking target mctp
[17/21] Compiling C object test-mctpd.p/src_mctp-netlink.c.o
[18/21] Compiling C object mctpd.p/src_mctpd.c.o
[19/21] Compiling C object test-mctpd.p/src_mctpd.c.o
[20/21] Linking target mctpd
[21/21] Linking target test-mctpd
ninja: Entering directory `/root/mctp/obj'
ninja: no work to do.
Installing mctp to /usr/local/bin
Installing mctpd to /usr/local/sbin
ssh root@localhost -p 2025 "cd ~/mctp; cp conf/mctpd-dbus.conf /etc/dbus-1/system.d/"

ssh root@localhost -p 2025 "cd ~/mctp; cat conf/mctpd.service | sed 's/sbin/local\/sbin/' > /etc/systemd/system/mctpd.service"

scp -r -P 2025 /home/jack/work/cxl-test-tool//test-workflows/mctp.sh root@localhost:/tmp/mctp-setup.sh 2>&1 1>/dev/null

ssh root@localhost -p 2025 "bash /tmp/mctp-setup.sh"
yisb 8 11 "/xyz/openbmc_project/mctp/11/8" true
yisb 9 11 "/xyz/openbmc_project/mctp/11/9" true
NAME                              TYPE      SIGNATURE RESULT/VALUE FLAGS
.EID                              property  y         8            const
.NetworkId                        property  u         11           const
.SupportedMessageTypes            property  ay        2 7 8        const
NAME                              TYPE      SIGNATURE RESULT/VALUE FLAGS
.EID                              property  y         9            const
.NetworkId                        property  u         11           const
.SupportedMessageTypes            property  ay        2 7 8        const
```

### 1.7.7. Login to FM Client and Run DCD Test via FM

```
./cxl-tool.py --login-fm
```

**Example output:**

```
jack@jack-MS-7D30:~/work/cxl-test-tool$ ./cxl-tool.py --login-fm
login with root@localhost: 2025
Linux jack-MS-7D30 6.6.0-rc6+ #2 SMP PREEMPT_DYNAMIC Fri Oct 10 17:31:11 PDT 2025 x86_64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
Last login: Wed Oct 15 18:19:05 2025 from 10.0.2.2
-bash: warning: setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8): No such file or directory
-bash: warning: setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8): No such file or directory
-bash: warning: setlocale: LC_COLLATE: cannot change locale (en_US.UTF-8): No such file or directory
-bash: warning: setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8): No such file or directory
-bash: warning: setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8): No such file or directory
-bash: warning: setlocale: LC_COLLATE: cannot change locale (en_US.UTF-8): No such file or directory
root@jack-MS-7D30:~# cd /tmp/libcxlmi/
root@jack-MS-7D30:/tmp/libcxlmi# ./build/examples/cxl-dcd
scanning dbus...
found 2 endpoint(s)
Max device capacity: 4096MB
Assign initial capacity to host: 512MB
Check capacity assigned: 
        Offer 0: [0MB-512MB]
Total capcity offered: 512MB, number of offering: 1

Assign initial capacity succeed
Compressing the data ...
Get 256MB capacity from compression
Offering 256MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
Total capcity offered: 768MB, number of offering: 2

Compressing the data ...
Get 128MB capacity from compression
Offering 128MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
Total capcity offered: 896MB, number of offering: 3

Compressing the data ...
Get 640MB capacity from compression
Offering 640MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
Total capcity offered: 1536MB, number of offering: 4

Compressing the data ...
Get 128MB capacity from compression
Offering 128MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
Total capcity offered: 1664MB, number of offering: 5

Compressing the data ...
Get 128MB capacity from compression
Offering 128MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
Total capcity offered: 1792MB, number of offering: 6

Compressing the data ...
Get 384MB capacity from compression
Offering 384MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
        Offer 6: [1792MB-2176MB]
Total capcity offered: 2176MB, number of offering: 7

Compressing the data ...
Get 128MB capacity from compression
Offering 128MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
        Offer 6: [1792MB-2176MB]
        Offer 7: [2176MB-2304MB]
Total capcity offered: 2304MB, number of offering: 8

Compressing the data ...
Get 512MB capacity from compression
Offering 512MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
        Offer 6: [1792MB-2176MB]
        Offer 7: [2176MB-2304MB]
        Offer 8: [2304MB-2816MB]
Total capcity offered: 2816MB, number of offering: 9

Compressing the data ...
Get 128MB capacity from compression
Offering 128MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
        Offer 6: [1792MB-2176MB]
        Offer 7: [2176MB-2304MB]
        Offer 8: [2304MB-2816MB]
        Offer 9: [2816MB-2944MB]
Total capcity offered: 2944MB, number of offering: 10

Compressing the data ...
Get 640MB capacity from compression
Offering 640MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
        Offer 6: [1792MB-2176MB]
        Offer 7: [2176MB-2304MB]
        Offer 8: [2304MB-2816MB]
        Offer 9: [2816MB-2944MB]
        Offer 10: [2944MB-3584MB]
Total capcity offered: 3584MB, number of offering: 11

Compressing the data ...
Get 128MB capacity from compression
Offering 128MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
        Offer 6: [1792MB-2176MB]
        Offer 7: [2176MB-2304MB]
        Offer 8: [2304MB-2816MB]
        Offer 9: [2816MB-2944MB]
        Offer 10: [2944MB-3584MB]
        Offer 11: [3584MB-3712MB]
Total capcity offered: 3712MB, number of offering: 12

Compressing the data ...
Get 256MB capacity from compression
Offering 256MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
        Offer 6: [1792MB-2176MB]
        Offer 7: [2176MB-2304MB]
        Offer 8: [2304MB-2816MB]
        Offer 9: [2816MB-2944MB]
        Offer 10: [2944MB-3584MB]
        Offer 11: [3584MB-3712MB]
        Offer 12: [3712MB-3968MB]
Total capcity offered: 3968MB, number of offering: 13

Compressing the data ...
Get 128MB capacity from compression
Offering 128MB to the host..
        Offer 0: [0MB-512MB]
        Offer 1: [512MB-768MB]
        Offer 2: [768MB-896MB]
        Offer 3: [896MB-1536MB]
        Offer 4: [1536MB-1664MB]
        Offer 5: [1664MB-1792MB]
        Offer 6: [1792MB-2176MB]
        Offer 7: [2176MB-2304MB]
        Offer 8: [2304MB-2816MB]
        Offer 9: [2816MB-2944MB]
        Offer 10: [2944MB-3584MB]
        Offer 11: [3584MB-3712MB]
        Offer 12: [3712MB-3968MB]
        Offer 13: [3968MB-4096MB]
Total capcity offered: 4096MB, number of offering: 14
```

### 1.7.8. Check Extents Allocated on FM_TARGET VM

You can run `cxl list -N -u` on FM_TARGET to show the extents added via `cxl-dcd`:

```
./cxl-tool.py -C "cxl list -N -u"
```

**Example output:**

```
[
  {
    "memdevs":[
      {
        "memdev":"mem0",
        "dynamic_ram_a_size":"4.00 GiB (4.29 GB)",
        "serial":"0x63",
        "host":"0000:11:00.0",
        "firmware_version":"BWFW VERSION 00"
      }
    ]
  },
  {
    "regions":[
      {
        "region":"region0",
        "resource":"0x1290000000",
        "size":"4.00 GiB (4.29 GB)",
        "interleave_ways":1,
        "interleave_granularity":256,
        "decode_state":"commit",
        "extents":[
          {
            "offset":"0x48000000",
            "length":"256.00 MiB (268.44 MB)",
            "uuid":"00000000-0000-0000-0000-000000000000"
          },
          {
            "offset":"0xe8000000",
            "length":"128.00 MiB (134.22 MB)",
            "uuid":"00000000-0000-0000-0000-000000000000"
          },
          {
            "offset":"0x70000000",
            "length":"128.00 MiB (134.22 MB)",
            "uuid":"00000000-0000-0000-0000-000000000000"
          },
          {
            "offset":"0x90000000",
            "length":"384.00 MiB (402.65 MB)",
            "uuid":"00000000-0000-0000-0000-000000000000"
          },
          {
            "offset":"0xb8000000",
            "length":"256.00 MiB (268.44 MB)",
            "uuid":"00000000-0000-0000-0000-000000000000"
          },
          {
            "offset":"0",
            "length":"512.00 MiB (536.87 MB)",
            "uuid":"00000000-0000-0000-0000-000000000000"
          },
	      ...
        ]
      }
    ]
  }
]
```

# 2. How DCD works in QEMU Emulation - One VM case

## 2.1. Kernel and QEMU source
kernel_url="https://github.com/weiny2/linux-kernel.git"  
kernel_branch="dcd-v6-2025-04-13"  
qemu_url="git+ssh://git@github.com/moking/qemu-jic-clone.git"  
qemu_branch='dcd-compression'  

## 2.2. DCD configuration during CXL driver loading

During driver loading, cxl_pci_probe is called, which will call cxl_configure_dcd
if DCD is supported.
```
	if (cxl_dcd_supported(mds))
		cxl_configure_dcd(mds, &range_info);
```

cxl_configure_dcd calls cxl_dev_dc_identify, which will call cxl_get_dc_config.
```
static int cxl_get_dc_config(struct cxl_mailbox *mbox, u8 start_partition,
			     struct cxl_mbox_get_dc_config_out *dc_resp,
			     size_t dc_resp_size)
{
	struct cxl_mbox_get_dc_config_in get_dc = (struct cxl_mbox_get_dc_config_in) {
		.partition_count = CXL_MAX_DC_PARTITIONS,
		.start_partition_index = start_partition,
	};
	struct cxl_mbox_cmd mbox_cmd = (struct cxl_mbox_cmd) {
		.opcode = CXL_MBOX_OP_GET_DC_CONFIG,
		.payload_in = &get_dc,
		.size_in = sizeof(get_dc),
		.size_out = dc_resp_size,
		.payload_out = dc_resp,
		.min_out = 1,
	};
	int rc;

	rc = cxl_internal_send_cmd(mbox, &mbox_cmd);
	if (rc < 0)
		return rc;

	dev_dbg(mbox->host, "Read %d/%d DC partitions\n",
		dc_resp->partitions_returned, dc_resp->avail_partition_count);
	return dc_resp->partitions_returned;
}
```

The CXL_MBOX_OP_GET_DC_CONFIG (Get Dynamic Capacity Configuration, 0x4800) command will be 
sent to the device to get the DCD info.

### 2.2.1. QEMU log of the CCI command
```
CXL Command: set=0x48 cmd=0x00 (DCD_GET_DC_CONFIG) len_in=2
  Payload (hex):
    0000: 08 00
CXL Command Response: set=0x48 cmd=0x00 (DCD_GET_DC_CONFIG) ret=0x00 len_out=104
  Response Payload (hex):
    0000: 02 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0010: 08 00 00 00 00 00 00 00 00 00 00 80 00 00 00 00
    0020: 00 00 20 00 00 00 00 00 00 00 00 00 00 00 00 00
    0030: 00 00 00 80 00 00 00 00 08 00 00 00 00 00 00 00
    0040: 00 00 00 80 00 00 00 00 00 00 20 00 00 00 00 00
    0050: 01 00 00 00 00 00 00 00 00 02 00 00 00 02 00 00
    0060: 00 00 00 00 00 00 00 00
  ```

## 2.3. Create region
### 2.3.1. Check memdev size
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
### 2.3.2. Create a region based on the size
cxl create-region -m mem0 -d decoder0.0 -s 2147483648 -t dynamic_ram_a

### 2.3.3. Kernel Log
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

### 2.3.4. QEMU log of the CCI command
```
CXL Command: set=0x48 cmd=0x01 (DCD_GET_DYNAMIC_CAPACITY_EXTENT_LIST) len_in=8
  Payload (hex):
    0000: 32 00 00 00 00 00 00 00
CXL Command Response: set=0x48 cmd=0x01 (DCD_GET_DYNAMIC_CAPACITY_EXTENT_LIST) ret=0x00 len_out=16
  Response Payload (hex):
    0000: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

## 2.4. Add Dynamic Capacity

### 2.4.1. Add an extent of 0-128MB
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

### 2.4.2. QMP command sent by the cxl-tool.py

In the above sequence, cxl-tool.py will create and write the following command to the /tmp/qmp-add.json.
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
Then it will execute "cat /tmp/qmp-add.json |ncat localhost $qmp_port"

### 2.4.3. QEMU Handles the cxl-add-dynamic-capacity QMP command

QEMU will call the `qmp_cxl_add_dynamic_capacity` function to process the command. Based on the "prescriptive" policy, `qmp_cxl_process_dynamic_capacity_prescriptive` will be called with `DC_EVENT_ADD_CAPACITY`. This function performs sanity checks, such as block size alignment and ensuring the range is within the region. If everything is correct, the extent will be added to a pending extent list, and a DC event record of type `DC_EVENT_ADD_CAPACITY` will be generated along with the extent information. Then, an interrupt will be asserted to notify the host.

### 2.4.4. Kernel processes the DCD event

The kernel will get the interrupt and process the event in the following function. 

```
static irqreturn_t cxl_event_thread(int irq, void *id)
{
	struct cxl_dev_id *dev_id = id;
	struct cxl_dev_state *cxlds = dev_id->cxlds;
	struct cxl_memdev_state *mds = to_cxl_memdev_state(cxlds);
	u32 status;

	do {
		/*
		 * CXL 3.0 8.2.8.3.1: The lower 32 bits are the status;
		 * ignore the reserved upper 32 bits
		 */
		status = readl(cxlds->regs.status + CXLDEV_DEV_EVENT_STATUS_OFFSET);
		/* Ignore logs unknown to the driver */
		status &= CXLDEV_EVENT_STATUS_ALL;
		if (!status)
			break;
		cxl_mem_get_event_records(mds, status);
		cond_resched();
	} while (status);

	return IRQ_HANDLED;
}
```

The corresponding kernel log is below.
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
The kernel sends a command of "Get Event Records" (0x0100) to retrieve the DCD event and processed it. 

```
[ 9130.432809] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x4802
[ 9130.433830] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[ 9130.434394] cxl_core:cxl_clear_event_record:1099: cxl_pci 0000:10:00.0: Event log '4': Clearing 1
[ 9130.434927] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x0101
[ 9130.435444] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[ 9130.435991] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x0100
[ 9130.436519] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
```

The kernel calls `cxl_send_dc_response` which will issue the mailbox command of Add Dynamic Capacity Response.    
This function will send back the extent accepted.  

The kernel issues two more mailbox commands  
Clear Event Records           - 0x0101  
Get Event Records             - 0x0100  

### 2.4.5. QEMU adds the extent accepted to the device
At the QEMU side, `cmd_dcd_add_dyn_cap_rsp` will be called and add the accepted extent passed by the kernel to its extent list and update the extent count. The extent will also be removed from the pending extent list where it was appended in `qmp_cxl_add_dynamic_capacity`.

### 2.4.6. QEMU log of the CCI commands
```
CXL Command: set=0x01 cmd=0x00 (EVENTS_GET_RECORDS) len_in=1
  Payload (hex):
    0000: 04
CXL Command Response: set=0x01 cmd=0x00 (EVENTS_GET_RECORDS) ret=0x00 len_out=160
  Response Payload (hex):
    0000: 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0010: 00 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00
    0020: ca 95 af a7 f1 83 40 18 8c 2f 95 26 8e 10 1a 2a
    0030: 80 01 00 00 01 00 00 00 da a1 e6 61 78 8c 71 18
    0040: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0050: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0060: 00 00 00 08 00 00 00 00 00 00 00 00 00 00 00 00
    0070: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0080: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0090: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
CXL Command: set=0x48 cmd=0x02 (DCD_ADD_DYNAMIC_CAPACITY_RESPONSE) len_in=32
  Payload (hex):
    0000: 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0010: 00 00 00 08 00 00 00 00 00 00 00 00 00 00 00 00
CXL Command Response: set=0x48 cmd=0x02 (DCD_ADD_DYNAMIC_CAPACITY_RESPONSE) ret=0x00 len_out=0
CXL Command: set=0x01 cmd=0x01 (EVENTS_CLEAR_RECORDS) len_in=8
  Payload (hex):
    0000: 04 00 01 00 00 00 01 00
CXL Command Response: set=0x01 cmd=0x01 (EVENTS_CLEAR_RECORDS) ret=0x00 len_out=0
CXL Command: set=0x01 cmd=0x00 (EVENTS_GET_RECORDS) len_in=1
  Payload (hex):
    0000: 04
CXL Command Response: set=0x01 cmd=0x00 (EVENTS_GET_RECORDS) ret=0x00 len_out=32
  Response Payload (hex):
    0000: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0010: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

## 2.5. Show Extents

### 2.5.1. QMP commands issued by the cxl-tool.py
Below is the operation to print extent.
```
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 2
cat /tmp/qmp-show.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886-dirty"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
{"return": {}}
Print accepted extent info:
0: [0x0 - 0x8000000]
In total, 1 extents printed!
Print pending-to-add extent info:
In total, 0 extents printed!
```

The QMP commands issued by the cxl-tool.py are created in the create_display_extents_qmp_input function.
```
def create_display_extents_qmp_input(dev):
    op="cxl-display-accepted-dc-extents"
    op2="cxl-display-pending-to-add-dc-extents"

    body=[
    { "execute": "qmp_capabilities" }
    ,
    { "execute": "%s"%op,
     "arguments": {
         "path": "/machine/peripheral/%s"%dev,
         "output": "%s"%extent_file
         }
     },
    { "execute": "%s"%op2,
     "arguments": {
         "path": "/machine/peripheral/%s"%dev,
          "output": "/tmp/dc-extent.txt"
      }
    }
    ]
```

### 2.5.2. QEMU returns extents
QEMU calls `qmp_cxl_display_accepted_dc_extents` and `qmp_cxl_display_pending_to_add_dc_extents` and returns the extents that are accepted or pending to add. 


## 2.6. Release Extent

### 2.6.1. QMP commands issued by the cxl-tool.py
The operation of Release Extent is below.
```
Choose OP: 0: add, 1: release, 2: print extent, 9: exit
Choice: 1
Input extent to release, for example (unit: MB): 0-128[,128-256]
Extents: 0-128
cat /tmp/qmp-rm.json|ncat localhost 4445
{"QMP": {"version": {"qemu": {"micro": 90, "minor": 2, "major": 9}, "package": "v6.2.0-28065-g3537a06886-dirty"}, "capabilities": ["oob"]}}
{"return": {}}
{"return": {}}
```

The QMP command issued by cxl-tool.py is created in the function `create_release_extent_qmp_input`. 
The format of the command is below.

```
 { "execute": "cxl-release-dynamic-capacity",
	  "arguments": {
		  "path": "/machine/peripheral/cxl-memdev0",
          "host-id":0,
          "removal-policy":"prescriptive",
          "region": 0,
          "tag": "",
		  "extents": [
		  {
			  "offset": 0,
			  "len": 134217728
		  }
		  ]
	  }
	}
```
### 2.6.2. QEMU handles cxl-release-dynamic-capacity QMP command
QEMU calls `qmp_cxl_release_dynamic_capacity` to release the extent. Based on the "prescriptive" policy, `qmp_cxl_process_dynamic_capacity_prescriptive` will be called with `DC_EVENT_RELEASE_CAPACITY`. Some sanity checks will be done for the extent specified. If passed, a DC event record will be generated with type `DC_EVENT_RELEASE_CAPACITY`. The event record also has the extent to be released. And an interrupt will be asserted to notify the host.  

### 2.6.3. Kernel processes the DCD event

Below is the kernel log during the operation of release DC extent.
```
[17993.005454] cxl_core:cxl_mem_get_event_records:1412: cxl_pci 0000:10:00.0: Reading event logs: 10
```
10 is the hex value from the event status register, with bit 4 (CXLDEV_EVENT_STATUS_DCD) set. Then, `cxl_mem_get_records_log(mds, CXL_EVENT_TYPE_DCD)` will be called.

```
[17993.005959] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x0100
[17993.006414] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[17993.006951] cxl_core:cxl_handle_dcd_event_records:1316: cxl_pci 0000:10:00.0: DCD event release : DPA:0x0 LEN:0x8000000
[17993.007689] cxl_core:__cxl_dpa_to_region:2869: cxl decoder3.0: dpa:0x0 mapped in region:region0
[17993.008212] cxl_core:cxlr_rm_extent:331:  extent0.0: Remove region extent HPA [range 0x0000000000000000-0x0000000007ffffff]
[17993.008802] cxl_core:cxlr_notify_extent:285: cxl_dax_region dax_region0: Trying notify: type 1 HPA [range 0x0000000000000000-0x0000000007ffffff]
[17993.009482] cxl_core:cxlr_notify_extent:305: cxl_dax_region dax_region0: Notify: type 1 HPA [range 0x0000000000000000-0x0000000007ffffff]
[17993.010123] dax:__dax_release_resource:191: cxl_dax_region dax_region0: Extent release resource [mem 0x1290000000-0x1297ffffff flags 0x80000200]
[17993.010788] cxl_core:region_extent_unregister:117:  extent0.0: DAX region rm extent HPA [range 0x0000000000000000-0x0000000007ffffff]
[17993.011422] dax:__dax_release_resource:191: cxl_dax_region dax_region0: Extent release resource (null)
[17993.011916] cxl_core:cxled_release_extent:72: cxl decoder3.0: Remove extent [range 0x0000000000000000-0x0000000007ffffff] (00000000-0000-0000-0000-000000000000)
[17993.012678] cxl_core:memdev_release_extent:1203: cxl_pci 0000:10:00.0: Release response dpa [range 0xffff8881045e1fc8-0x0000000000000000]
```
The kernel sends a command of "Get Event Records" (0x0100) to retrieve the DCD event and processed it.

```
[17993.013377] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x4803
[17993.013843] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[17993.014326] cxl_core:cxl_clear_event_record:1099: cxl_pci 0000:10:00.0: Event log '4': Clearing 2
[17993.014799] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x0101
[17993.015277] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
[17993.015762] cxl_pci:__cxl_pci_mbox_send_cmd:263: cxl_pci 0000:10:00.0: Sending command: 0x0100
[17993.016229] cxl_pci:cxl_pci_mbox_wait_for_doorbell:74: cxl_pci 0000:10:00.0: Doorbell wait took 0ms
```

Kernel calls cxl_send_dc_response which will issue the mailbox command of CXL_MBOX_OP_RELEASE_DC (0x4803).
If the extent can be released, it will also be put in the payload of the command.

Two more commands are sent by the kernel.  
Clear Event Records           - 0x0101  
Get Event Records             - 0x0100  



### 2.6.4. QEMU mem device releases the extent
The QEMU side will call `cmd_dcd_release_dyn_cap` to process the mailbox command and get the extent to be released and remove it from its extent list.


### 2.6.5. Qemu log of the cci commands
```
CXL Command: set=0x01 cmd=0x00 (EVENTS_GET_RECORDS) len_in=1
  Payload (hex):
    0000: 04
CXL Command Response: set=0x01 cmd=0x00 (EVENTS_GET_RECORDS) ret=0x00 len_out=160
  Response Payload (hex):
    0000: 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0010: 00 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00
    0020: ca 95 af a7 f1 83 40 18 8c 2f 95 26 8e 10 1a 2a
    0030: 80 01 00 00 02 00 00 00 6c 44 95 89 9d 8c 71 18
    0040: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0050: 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0060: 00 00 00 08 00 00 00 00 00 00 00 00 00 00 00 00
    0070: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0080: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0090: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
CXL Command: set=0x48 cmd=0x03 (DCD_RELEASE_DYNAMIC_CAPACITY) len_in=32
  Payload (hex):
    0000: 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0010: 00 00 00 08 00 00 00 00 00 00 00 00 00 00 00 00
CXL Command Response: set=0x48 cmd=0x03 (DCD_RELEASE_DYNAMIC_CAPACITY) ret=0x00 len_out=0
CXL Command: set=0x01 cmd=0x01 (EVENTS_CLEAR_RECORDS) len_in=8
  Payload (hex):
    0000: 04 00 01 00 00 00 02 00
CXL Command Response: set=0x01 cmd=0x01 (EVENTS_CLEAR_RECORDS) ret=0x00 len_out=0
CXL Command: set=0x01 cmd=0x00 (EVENTS_GET_RECORDS) len_in=1
  Payload (hex):
    0000: 04
CXL Command Response: set=0x01 cmd=0x00 (EVENTS_GET_RECORDS) ret=0x00 len_out=32
  Response Payload (hex):
    0000: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    0010: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

# 3. How DCD works in QEMU Emulation - Two VMs case

TBD