---
author: "Andreas M"
title: "Arista Automated Provisioning using Ansible"
date: 2024-06-10T07:51:41+02:00 
description: "Deploying Arista vEOS from zero to full spine-leaf"
draft: false 
toc: true
#featureimage: ""
thumbnail: "/images/1280px-Arista-networks-logo.svg.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Networking
  - Provisioning
  - Automation
tags:
  - networking
  - provisioning
  - automation
Summary: In this post I will deploy Arista vEOS from zero to a full Spine-Leaf topology using Arista ZeroTouch Provisining and Ansible
comment: false # Disable comment if false.
---



# Arista Networks

From Arista's [homepage](https://www.arista.com/en/company/company-overview): 

> Arista Networks is an industry leader in data-driven, client to cloud networking for large data center/AI, campus and routing environments. Arista’s award-winning platforms deliver availability, agility, automation, analytics and security through an advanced network operating stack

Arista has some really great products, and what I would like to have a deeper look at is the automation part, which also may involve the agility part.

I have been working with network for many years, starting out with basic network configurations like VLAN, iSCSI setups and routing to support my vSphere implementations as a consultant many many years back. Then I started working with VMware NSX back in 2014/15 first as a consultant doing presale, design and implementation before joining VMware as a NSX specialist. Working with NSX, both as consultant and later as a VMware NSX solutions engineer, very much involved the physical network NSX was supposed to run "on top" of as the actual NSX design. One of NSX benefits was how easy it was to automate. 

What I have never been working with is automating the physical network. Automation is not only for easier deployment, handling dynamics in the datacenter more efficient, but also reducing/eliminate configuration issues. In this post I will go through how I make use of Arista vEOS and Ansible to deploy a full spine-leaf topology from zero to hero.

## vEOS

vEOS is a virtual appliance making it possible to run EOS as a virtual machine in vSphere, KVM, Proxmox, VMware Workstation, Fusion, and VirtualBox just to name a few. For more information head over [here](https://arista.my.site.com/AristaCommunity/s/article/veos-running-eos-in-a-vm). 

With this it is absolutely possible to deploy/test Arista EOS with all kinds of functionality in the comfort of my lab. So without further ado, lets jump in to it.  

### vEOS on Proxmox

The vEOS appliance consists of two files, the *aboot-veos-x.iso* and the *veos-lab-4-x.disk*. The *aboot-veos-x.iso* is mounted as a CD/DVD ISO and the disk file is the harddisk of your VM. I am running Proxmox in my lab that supports both VMDK vm disk files and qcow2 I will be using qcow2 as vEOS also includes this file. So what I did to create a working vEOS VM in Proxmox was this:

- Upload the files aboot-veos.iso to a datastore on my Proxmox host I can store ISO files. 

![aboot-iso](images/image-20240610143633008.png)

- Upload the qcow2 image/disk file to a temp folder on my Proxmox host. (/tmp)

```bash
root@proxmox-02:/tmp# ls
vEOS64-lab-4.32.1F.qcow2
```

- Create a new VM like this:

![vm-eos](images/image-20240610144322725.png)

Add a Serial Port, a USB device and mount the *aboot-iso* on the CD/DVD drive, and select no hardisk in the wizard (delete the proposed harddisk). Operating system type is Linux 6.x. I chose to use x86-64-v2-AES CPU emulation. 

- Add the vEOS disk by utilizing the qm import command like this, where 7011 is the ID of my VM, raid-10-node02 is the disk where I want the qcow2 image to be imported/placed. 

```bash
root@proxmox-02:/tmp# qm importdisk 7011 vEOS64-lab-4.32.1F.qcow2 raid-10-node02 -format raw
importing disk 'vEOS64-lab-4.32.1F.qcow2' to VM 7011 ...
transferred 0.0 B of 4.0 GiB (0.00%)
transferred 50.9 MiB of 4.0 GiB (1.24%)
...
transferred 4.0 GiB of 4.0 GiB (100.00%)
Successfully imported disk as 'unused0:raid-10-node02:vm-7011-disk-0'
```

When this is done it will turn up as an unused disk in my VM. 

![unused-disk](images/image-20240610144925682.png)

To add the unused disk I selected it, clicked edit and choose SATA and bus 0. This was the only way for the vEOS to successfully boot. This is not what is mentioned in the official documentation [here](https://arista.my.site.com/AristaCommunity/s/article/veos-running-eos-in-a-vm) *The Aboot-veos iso must be set as a CD-ROM image on the IDE bus, and the EOS vmdk must be a hard drive image on the same IDE bus. The simulated hardware cannot contain a SATA controller or vEOS will fail to fully boot.* 

![sata](images/image-20240610145327095.png)

![add](images/image-20240610145356565.png)

![sata-disk-added](images/image-20240610145428519.png)

Now the disk has been added. One final note, I have added the network interfaces I need in my lab as seen above. The net0 will be used for dedicated oob management. 

Thats it, I can now power on my vEOS. 

![booting](images/image-20240610151817343.png)

When its done booting, can take a couple of seconds, it will present you with the following screen:

![login](images/image-20240610151711714.png)

I can decide to log in and configure it manually by logging in with admin, disable Zero Touch Provisioning. But thats not what this post is about, it is about automating the whole process as much as possible. So this takes me to the next chapter. Zero Touch Provisioning. 

I can now power it off, clone this instance to the amount of vEOS appliances I need. I have created 5 instances to be used In the following parts of this post.

## ZTP - Zero Touch Provisioning

Now that I have created all my needed vEOS VMs I need some way to set the basic config like Management Interface IP and username password so I can hand them over to Ansible to automate the whole configuration.

EOS starts by default in ZTP mode, meaning it will do a DHCP request and acquire an IP address if there is a DHCP server that reply, this also means I can configure my DHCP server with a option to run a script from a TFTP server to do these initial configurations. 

For ZTP to work I must have a DHCP server with some specific settings, then a TFTP server. I decided to create a dedicated DHCP server for this purpose, and I also run the TFTPD instance on the same server as where I run the DHCPD server. The Linux distribution I am using is Ubuntu Server. 

Following the official documentation [here](https://arista.my.site.com/AristaCommunity/s/article/ztp-set-up-guide) I have configured my DHCP server with the following setting:

```bash
# ####GLOBAL Server config###
default-lease-time 7200;
max-lease-time 7200;
authoritative;
log-facility local7;
ddns-update-style none;
one-lease-per-client true;
deny duplicates;
option option-252 code 252 = text;
option domain-name "int.guzware.net";
option domain-name-servers 10.100.1.7,10.100.1.6;
option netbios-name-servers 10.100.1.7,10.100.1.6;
option ntp-servers 10.100.1.7;

# ###### Arista MGMT####
subnet 172.18.100.0 netmask 255.255.255.0 {
    pool {
    range 172.18.100.101 172.18.100.150;
    option domain-name "int.guzware.net";
    option domain-name-servers 10.100.1.7,10.100.1.6;
    option broadcast-address 10.100.1.255;
    option ntp-servers 10.100.1.7;
    option routers 172.18.100.2;
    get-lease-hostnames true;
    option subnet-mask 255.255.255.0;
  }
}


host s_lan_0 {
        hardware ethernet bc:24:11:7b:5d:e6;
        fixed-address 172.18.100.101;
        option bootfile-name "tftp://172.18.100.10/ztp-spine1-script";
     }

host s_lan_1 {
        hardware ethernet bc:24:11:04:f8:f8;
        fixed-address 172.18.100.102;
        option bootfile-name "tftp://172.18.100.10/ztp-spine2-script";
     }

host s_lan_2 {
        hardware ethernet bc:24:11:ee:53:83;
        fixed-address 172.18.100.103;
        option bootfile-name "tftp://172.18.100.10/ztp-leaf1-script";
     }

host s_lan_3 {
        hardware ethernet bc:24:11:b3:2f:74;
        fixed-address 172.18.100.104;
        option bootfile-name "tftp://172.18.100.10/ztp-leaf2-script";
     }

host s_lan_4 {
        hardware ethernet bc:24:11:f8:da:7f;
        fixed-address 172.18.100.105;
        option bootfile-name "tftp://172.18.100.10/ztp-borderleaf1-script";
     }
```

The 5 host entries corresponds with my 5 vEOS appliances mac addresses respectively and the *option bootfile-name* referes to a unique file for every vEOS appliance. 

The TFTP server has this configuration:

```bash
# /etc/default/tftpd-hpa

TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/home/andreasm/arista/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure"
```

Then in the tftp_directory I have the following files:

```bash
andreasm@arista-dhcp:~/arista/tftpboot$ ll
total 48
drwxrwxr-x 2      777 nogroup  4096 Jun 10 08:59 ./
drwxrwxr-x 3 andreasm andreasm 4096 Jun 10 08:15 ../
-rw-r--r-- 1 root     root      838 Jun 10 08:55 borderleaf-1-startup-config
-rw-r--r-- 1 root     root      832 Jun 10 08:52 leaf-1-startup-config
-rw-r--r-- 1 root     root      832 Jun 10 08:53 leaf-2-startup-config
-rw-r--r-- 1 root     root      832 Jun 10 08:45 spine-1-startup-config
-rw-r--r-- 1 root     root      832 Jun 10 08:51 spine-2-startup-config
-rw-r--r-- 1 root     root      103 Jun 10 08:55 ztp-borderleaf1-script
-rw-r--r-- 1 root     root       97 Jun 10 08:53 ztp-leaf1-script
-rw-r--r-- 1 root     root       97 Jun 10 08:54 ztp-leaf2-script
-rw-r--r-- 1 root     root       98 Jun 10 08:39 ztp-spine1-script
-rw-r--r-- 1 root     root       98 Jun 10 08:51 ztp-spine2-script
```

The content of the *ztp-leaf1-script* file:

```bash
andreasm@arista-dhcp:~/arista/tftpboot$ cat ztp-leaf1-script
#!/usr/bin/Cli -p2

enable

copy tftp://172.18.100.10/leaf-1-startup-config flash:startup-config
```

The content of the *leaf-1-startup-config* file (taken from the Arista AVD repository [here](https://avd.arista.com/4.8/examples/single-dc-l3ls/index.html#basic-eos-config)):

```bash
andreasm@arista-dhcp:~/arista/tftpboot$ cat leaf-1-startup-config
hostname leaf-1
!
! Configures username and password for the ansible user
username ansible privilege 15 role network-admin secret sha512 $hash/
!
! Defines the VRF for MGMT
vrf instance MGMT
!
! Defines the settings for the Management1 interface through which Ansible reaches the device
interface Management1
   description oob_management
   no shutdown
   vrf MGMT
   ! IP address - must be set uniquely per device
   ip address 172.18.100.103/24
!
! Static default route for VRF MGMT
ip route vrf MGMT 0.0.0.0/0 172.18.100.2
!
! Enables API access in VRF MGMT
management api http-commands
   protocol https
   no shutdown
   !
   vrf MGMT
      no shutdown
!
end
!
! Save configuration to flash
copy running-config startup-config
```

Now I just need to make sure both my DHCP service and TFTP service is running:

```bash
# DHCP Server
andreasm@arista-dhcp:~/arista/tftpboot$ systemctl status isc-dhcp-server
● isc-dhcp-server.service - ISC DHCP IPv4 server
     Loaded: loaded (/lib/systemd/system/isc-dhcp-server.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-06-10 09:02:08 CEST; 6h ago
       Docs: man:dhcpd(8)
   Main PID: 3725 (dhcpd)
      Tasks: 4 (limit: 4557)
     Memory: 4.9M
        CPU: 15ms
     CGroup: /system.slice/isc-dhcp-server.service
             └─3725 dhcpd -user dhcpd -group dhcpd -f -4 -pf /run/dhcp-server/dhcpd.pid -cf /etc/dhcp/dhcpd.co>

# TFTPD server
andreasm@arista-dhcp:~/arista/tftpboot$ systemctl status tftpd-hpa.service
● tftpd-hpa.service - LSB: HPA's tftp server
     Loaded: loaded (/etc/init.d/tftpd-hpa; generated)
     Active: active (running) since Mon 2024-06-10 08:17:55 CEST; 7h ago
       Docs: man:systemd-sysv-generator(8)
    Process: 2414 ExecStart=/etc/init.d/tftpd-hpa start (code=exited, status=0/SUCCESS)
      Tasks: 1 (limit: 4557)
     Memory: 408.0K
        CPU: 39ms
     CGroup: /system.slice/tftpd-hpa.service
             └─2422 /usr/sbin/in.tftpd --listen --user tftp --address :69 --secure /home/andreasm/arista/tftpb>


```

Thats it. If I have already powered on my vEOS appliance they will very soon get their new config and reboot with the desired config. If not, just reset or power them on and off again. Every time I deploy a new vEOS appliance I just have to update my DHCP server config to add the additional hosts mac addresses and corresponding config files. 

Now next chapter is about configuring the vEOS switches to form a spine/leaf topology automatically provisioned by using Ansible. To get started I used Arista's very well documented Arista Validated Design [here](https://avd.arista.com/4.8/index.html). More on this in the coming chapters

## Desired Topology

Before I did any automation with ZTP and Ansible I deployed my vEOS manually, configured them manually so I was sure I had a working configuration, and no issues in my lab. I just made sure I could deploy a spine-leaf topology, created some vlans and attached some VMs to them and checked connectivity. Below was my desired topology:

![spine-leaf](images/image-20240610155111246.png)

### My physical lab topology

## 

## Ansible





```bash
(arista_avd) andreasm@linuxmgmt01:~/arista/andreas-spine-leaf$ ansible-playbook build.yml

PLAY [Build Configurations and Documentation] *******************************************************************************************************************************************************************

TASK [arista.avd.eos_designs : Verify Requirements] *************************************************************************************************************************************************************
AVD version 4.8.0
Use -v for details.
[WARNING]: Collection arista.cvp does not support Ansible version 2.17.0
ok: [dc1-spine1 -> localhost]

TASK [arista.avd.eos_designs : Create required output directories if not present] *******************************************************************************************************************************
ok: [dc1-spine1 -> localhost] => (item=/home/andreasm/arista/andreas-spine-leaf/intended/structured_configs)
ok: [dc1-spine1 -> localhost] => (item=/home/andreasm/arista/andreas-spine-leaf/documentation/fabric)

TASK [arista.avd.eos_designs : Set eos_designs facts] ***********************************************************************************************************************************************************
ok: [dc1-spine1]

TASK [arista.avd.eos_designs : Generate device configuration in structured format] ******************************************************************************************************************************
An exception occurred during task execution. To see the full traceback, use -vvv. The error was: ansible_collections.arista.avd.plugins.plugin_utils.errors.errors.AristaAvdDuplicateDataError: Found duplicate objects with conflicting data while generating configuration for Ethernet Interfaces defined for underlay. {'name': 'Ethernet1', 'peer': 'dc1-leaf1', 'peer_interface': 'Ethernet1', 'description': 'P2P_LINK_TO_DC1-LEAF1_Ethernet1', 'ip_address': '192.168.0.0/31'} conflicts with {'name': 'Ethernet1', 'peer': 'dc1-borderleaf1', 'peer_interface': 'Ethernet1', 'description': 'P2P_LINK_TO_DC1-BORDERLEAF1_Ethernet1', 'ip_address': '192.168.0.8/31'}.
fatal: [dc1-spine1 -> localhost]: FAILED! => {"changed": false, "msg": "Found duplicate objects with conflicting data while generating configuration for Ethernet Interfaces defined for underlay. {'name': 'Ethernet1', 'peer': 'dc1-leaf1', 'peer_interface': 'Ethernet1', 'description': 'P2P_LINK_TO_DC1-LEAF1_Ethernet1', 'ip_address': '192.168.0.0/31'} conflicts with {'name': 'Ethernet1', 'peer': 'dc1-borderleaf1', 'peer_interface': 'Ethernet1', 'description': 'P2P_LINK_TO_DC1-BORDERLEAF1_Ethernet1', 'ip_address': '192.168.0.8/31'}."}
An exception occurred during task execution. To see the full traceback, use -vvv. The error was: ansible_collections.arista.avd.plugins.plugin_utils.errors.errors.AristaAvdDuplicateDataError: Found duplicate objects with conflicting data while generating configuration for Ethernet Interfaces defined for underlay. {'name': 'Ethernet2', 'peer': 'dc1-leaf1', 'peer_interface': 'Ethernet2', 'description': 'P2P_LINK_TO_DC1-LEAF1_Ethernet2', 'ip_address': '192.168.0.2/31'} conflicts with {'name': 'Ethernet2', 'peer': 'dc1-borderleaf1', 'peer_interface': 'Ethernet2', 'description': 'P2P_LINK_TO_DC1-BORDERLEAF1_Ethernet2', 'ip_address': '192.168.0.10/31'}.
fatal: [dc1-spine2 -> localhost]: FAILED! => {"changed": false, "msg": "Found duplicate objects with conflicting data while generating configuration for Ethernet Interfaces defined for underlay. {'name': 'Ethernet2', 'peer': 'dc1-leaf1', 'peer_interface': 'Ethernet2', 'description': 'P2P_LINK_TO_DC1-LEAF1_Ethernet2', 'ip_address': '192.168.0.2/31'} conflicts with {'name': 'Ethernet2', 'peer': 'dc1-borderleaf1', 'peer_interface': 'Ethernet2', 'description': 'P2P_LINK_TO_DC1-BORDERLEAF1_Ethernet2', 'ip_address': '192.168.0.10/31'}."}
changed: [dc1-leaf2 -> localhost]
changed: [dc1-borderleaf1 -> localhost]
changed: [dc1-leaf1 -> localhost]

TASK [arista.avd.eos_designs : Generate fabric documentation] ***************************************************************************************************************************************************
changed: [dc1-leaf1 -> localhost]

TASK [arista.avd.eos_designs : Generate fabric point-to-point links summary in csv format.] *********************************************************************************************************************
changed: [dc1-leaf1 -> localhost]

TASK [arista.avd.eos_designs : Generate fabric topology in csv format.] *****************************************************************************************************************************************
changed: [dc1-leaf1 -> localhost]

TASK [arista.avd.eos_designs : Remove avd_switch_facts] *********************************************************************************************************************************************************
ok: [dc1-leaf1]

TASK [arista.avd.eos_cli_config_gen : Verify Requirements] ******************************************************************************************************************************************************
skipping: [dc1-leaf1]

TASK [arista.avd.eos_cli_config_gen : Create required output directories if not present] ************************************************************************************************************************
ok: [dc1-leaf1 -> localhost] => (item=/home/andreasm/arista/andreas-spine-leaf/intended/structured_configs)
ok: [dc1-leaf1 -> localhost] => (item=/home/andreasm/arista/andreas-spine-leaf/documentation)
ok: [dc1-leaf1 -> localhost] => (item=/home/andreasm/arista/andreas-spine-leaf/intended/configs)
ok: [dc1-leaf1 -> localhost] => (item=/home/andreasm/arista/andreas-spine-leaf/documentation/devices)

TASK [arista.avd.eos_cli_config_gen : Include device intended structure configuration variables] ****************************************************************************************************************
skipping: [dc1-leaf1]
skipping: [dc1-leaf2]
skipping: [dc1-borderleaf1]

TASK [arista.avd.eos_cli_config_gen : Generate eos intended configuration] **************************************************************************************************************************************
changed: [dc1-borderleaf1 -> localhost]
changed: [dc1-leaf2 -> localhost]
changed: [dc1-leaf1 -> localhost]

TASK [arista.avd.eos_cli_config_gen : Generate device documentation] ********************************************************************************************************************************************
changed: [dc1-leaf2 -> localhost]
changed: [dc1-leaf1 -> localhost]
changed: [dc1-borderleaf1 -> localhost]

PLAY RECAP ******************************************************************************************************************************************************************************************************
dc1-borderleaf1            : ok=3    changed=3    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
dc1-leaf1                  : ok=8    changed=6    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
dc1-leaf2                  : ok=3    changed=3    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
dc1-spine1                 : ok=3    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
dc1-spine2                 : ok=0    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
```

