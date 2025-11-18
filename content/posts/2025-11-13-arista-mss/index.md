---
author: "Andreas M"
title: "Arista MSS - Multi-Domain Segmentation"
date: 2025-11-13T08:17:20+01:00
description: "What is Arista MSS and how does it work"
draft: true
toc: true
#featureimage: ""
#thumbnail: "/images/thumbnail.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Networking
  - Security
  - MicroSegmentation
  - ZeroTrust
  - Datacenter
  - Campus
tags:
  - networking
  - security
  - microsegmentation
  - zerotrust

summary: Deploying Arista MSS in my lab and seeing it in action
comment: false # Disable comment if false.
---



# Arista MSS - Multi-Domain Segmentation Services



Before I dive into how I configured and tested Arista MSS in my lab, I feel its kind of necessary to do a short introduction of MSS. What is it?

On a very high level, Arista Multi-Domain Segmentation Services is a solution to help you achieve Zero-Trust by allowing you to create microsegmention policies in your network fabric. This is regardless whether it is in your Campus, Datacenter or Branch/Edge. 

From Arista's offical MSS [web-page](https://www.arista.com/en/products/multi-domain-segmentation):

> Arista MSS offers a switch-based microperimeter technology stack that preserves the best attributes of switch-based and host-based firewall micro-segmentation technologies and, at the same time, overcomes their main limitations while delivering a consistent, unified segmentation architecture end-to-end across multiple domains (from the campus/branch to the data center).



> The following key principles of the Arista MSS architecture make it stand out compared to all other solutions in the market: 
>
> 1. Consistent architecture across multiple network domains (campus, branch, data center) predicated on a single EOS binary, common across all switching platforms, a single Arista CloudVision™ policy orchestration platform, and an aggregated Network Data Lake (Arista EOS NetDL™) infrastructure for state management and monitoring. 
> 2. The only microperimeter (tag-based) segmentation solution in the industry that is both network and endpoint agnostic: it has no dependency on any network data plane or control plane protocols and at the same time it does not require any software agents on the endpoints. 
> 3. A unified framework for micro- as well as macro-segmentation policies enabling security rules to be built around microperimeter objects as well as traditional network objects (subnets, VRFs), with the ability to enforce policies in the network or redirect traffic to any traditional security gateways. 
> 4. Arista MSS offers a switch-based microperimeter technology stack that preserves the best attributes of switch-based and host-based firewall micro-segmentation technologies and, at the same time, overcomes their main limitations while delivering a consistent, unified segmentation architecture end-to-end across multiple domains (from the campus/branch to the data center).

![management](images/image-20251113154945141.png)



![arista-mss](images/image-20251113155024489.png)



In my previous role at a software vendor as a Solution Engineer for many years helping customers with microsegmentation, zero-trust and microsegmentation is nothing new but an important security solution in todays IT landscape. I find the Arista MSS solution very interesting. The biggest differenciator with MSS is where the enforcement is done and how easy it is to get started and manage. In contrast to other solutions out there MSS will allow you to cover all needs from Campus, Datacenter all the way to the Branch/Edge, not leaving any gaps. MSS enforcement point is your switches, not an agent, not a software layer but right there where the traffic is and on the devices that are responsible for switching and routing your precious data, regardless of what kind and in which part of the network it is. Then there is performance, when using MSS it is actually line-rate performance which means no performance penalty when enabling an important security solution in your fabric. 

So how does it work? Lets dig in and find out.

## What is needed to get started with MSS?

This blog will only cover three components needed to run MSS, a supported Arista Switch, the ZTX appliance and Arista CloudVision. I will not cover things such as license requirements. For more detailed list of requirements and features see the MSS Data Sheet [here](https://www.arista.com/assets/data/pdf/Datasheets/Multi-Domain-Segmentation-Services-for-Zero-Trust-Networking.pdf) (page 5 for hardware and license requirements). Things like Data Sources will not be covered as I dont have things like vSphere (vCenter with VDS) and Arista AGNI (yet) available in my lab.



### The ZTX appliance (monitor node)

> The primary purpose of a Multi-domain Segmentation Services (MSS) Monitor Node is to provide visibility into app-to-app traffic in the network, and to develop non-intrusive MSS policies that are aligned with applications requirements. It is a baseline capability for any micro or macro segmentation solution and is a practical way to build and deploy policies. Configuring policies in terms of groups of end-points or prefixes is essential to simplify policy management and secure Data Center and Campus environments. The ZTX monitor node provides visibility into existing traffic needed to build such policies.

![ztx-figure](images/image-20251114060532447.png)

Source: [arista.com](https://www.arista.com/assets/data/pdf/user-manual/um-books/MSS-Deployment-Guide.pdf)

The ZTX monitor comes in two flavours, a physical appliance (ZTX-7250S-16S) and a virtual appliance. I will use the virtual appliance, vZTX, in my lab. vZTX can run on ESXi or KVM. In my lab I am using Proxmox which is KVM. Choosing between the physical or virtual in a production environment comes down to scale and performance. 

*For more information on the ZTX deployment head over [here](https://www.arista.com/assets/data/pdf/ZTX-7250S-Deployment-Guide.pdf), it covers both the ZTX and vZTX and includes different supported toplogies.*



There are some initial configurations that needs to be in place for the ZTX to work as intended, the steps below will go through these steps. Here are the things that needs to be done:

- Create the virtual machine in Proxmox with correct configuration so the CloudEOS image will boot
- Moving the CloudEOS image into monitor mode
- Basic configurations like username/password for SSH access and management
- Out of Band Management interface
- Peer to Peer link betwen the vZTX appliance and TOR switches (in my case my only 720XP).
- Loopback interface
- Some static routes (dynamic routing is also possible see [this](https://www.arista.com/assets/data/pdf/ZTX-7250S-Deployment-Guide.pdf)) for the loopback addresses between vZTX and TOR switch
- DNS
- NTP & Timezone
- Onboarding the vZTX to CloudVision. Several of the step above can be configured and provisioned by CloudVision.

#### Creating the virtual machine in Proxmox

To get started with the vZTX appliance I have downloaded the **CloudEOS64-4.35.0F.qcow2** image and **Aboot-veos-serial-8.0.2.iso** from arista.com and uploaded the qcow2 image to my Proxmox /tmp folder and the iso image to my ISO Images storage.

![ISO Images](images/image-20251114074513277.png)

 

Then I created a virtual machine in Proxmox with the following configurations *(I dont use more than two of the nics. 1 for mgmt and 1 for dataplane)*.

![vZTX-vm](images/image-20251114074146277.png)

Notice the Serial Port, this must be added to the VM otherwise it will not boot. 

The harddisk was imported using the following command:

```bash
qm importdisk 7988 /tmp/CloudEOS64-4.35.0F.qcow2 raid-10-node02 -format raw
```

*raid-10-node02 is my storage*

{{< alert >}}

This is a lab, if using the vZTX in production there are some requirements that needs to be in place:

SR-IOV is a MUST in production (not supported otherwise), but in my lab I did not have any free NICs for this purpose so I had to use VIRTIO. Again, this is in my lab, and performance is not an absolute must. Unless I do something that limits my Internet speed, then I will have some explaining to do for my kids :smile:

{{< /alert >}}

#### Moving the CloudEOS to Monitor Mode

When the vZTX has been configured in Proxmox its time to power it up. It will boot up with a very simple config. Username defaults to admin, and there is no password or was the password admin? Dont remember.

Before I can use the CloudEOS image as my ZTX appliance the first thing that needs to be done is to move the CloudEOS into monitor mode after first boot. This is done by running the following commands:

```bash
# Verify the veos-config before
vZTX# bash cat /mnt/flash/veos-config
MODE=sfe
vZTX#
```

Now perform the configuration:

```bash
vZTX# configure
vZTX(config)# firewall distributed instance
vZTX(config-firewall-distributed-instance)# no disabled
vZTX(config-firewall-distributed-instance)# end
vZTX# write
vZTX# reload
```

When the switch boots back up login again and verify veos-config after the config above:

```bash
# Verify the veos-config after
vZTX# bash cat /mnt/flash/veos-config
MODE=sfe
platformRuby=True
maxDatapathCores=2
vZTX# 
```

Thats it.

#### Basic configurations - Management1-p2p link-loopback

Now I can proceed to do the other configurations like mgmt interface, hostname, DNS, NTP and p2p link to my 720XP switch. See below for my running-config:

```bash
andreas-ztx1#show running-config
! Command: show running-config
! device: andreas-ztx1 (CloudEOS, EOS-4.35.0F-cloud)
!
! boot system flash:/CloudEOS.swi
!
no aaa root
!
username admin privilege 15 role network-admin secret sha512 <hash-redacted>
!
management api http-commands
   no shutdown
   !
   vrf MGMT
      no shutdown
!
daemon TerminAttr
   exec /usr/bin/TerminAttr -smashexcludes=ale,flexCounter,hardware,kni,pulse,strata -cvaddr=URL -cvauth=token-secure,/tmp/cv-onboarding-token -taillogs -cvvrf=MGMT -cvsourceintf=Management1
   no shutdown
!
switchport default mode routed
!
no service interface inactive port-id allocation disabled
!
transceiver qsfp default-mode 4x10G
!
service routing protocols model multi-agent
!
kernel software forwarding ecmp
!
hostname andreas-ztx1
ip name-server vrf MGMT 10.100.1.7
ip name-server vrf default 10.100.1.7
!
spanning-tree mode mstp
!
system l1
   unsupported speed action error
   unsupported error-correction action error
!
clock timezone Europe/Oslo
!
vrf instance MGMT
!
interface Ethernet1
   no switchport
   ip address 172.18.111.2/24
!
interface Ethernet2
   no switchport
!
interface Loopback0
   ip address 10.255.1.11/32
!
interface Management1
   description management
   vrf MGMT
   ip address 172.18.100.201/24
!
firewall distributed instance
   no disabled
!
ip routing
no ip routing vrf MGMT
!
ip route 0.0.0.0/0 172.18.111.1
ip route vrf MGMT 0.0.0.0/0 172.18.100.2
!
arp aging timeout default 180
!
ntp local-interface vrf MGMT Management1
ntp server vrf MGMT 10.100.1.7 prefer
!
end
```

Before onboarding the vZTX to CloudVision I did all the above configurations except:

```bash
!
daemon TerminAttr
   exec /usr/bin/TerminAttr -smashexcludes=ale,flexCounter,hardware,kni,pulse,strata -cvaddr=URL -cvauth=token-secure,/tmp/cv-onboarding-token -taillogs -cvvrf=MGMT -cvsourceintf=Management1
   no shutdown
!
```

The TerminAttr config will be done as part of the CloudVision onboarding process. Just follow the guide in CloudVision.

The documentation is not stating that the Management interface MUST be in the default VRF, I created a dedicated MGMT vrf and placed it there. That is the only VRF I have configured. Then I configured interface Ethernet1 as the p2p link to my Arista 720XP switch, and a Loopback0 interface. This loopback interface will be used later when I configure MSS Monitor object in CloudVision later. Then a default route in the default VRF using my 720XP p2p link as gateway. I used a /24 subnet for these p2p links which is unnecessary. 

Now my vZTX is ready configured with its necessary configuration and I can onboard it to CloudVision. 

#### Onboarding the vZTX to CloudVision

Go to Device and Inventory in Cloudvision and click on *+ Onboard Device*.

![onboard](images/image-20251115122213583.png)

Then follow the steps outlined there:

![onboard_steps](images/image-20251115122343884.png)

This may also be done using your preferred ZTP/bootstrap approach. 

*Under the General Requirements it says: *Have the Streaming Agent extension installed (minimum version 1.19.5). Click [here](https://www.arista.com/en/support/software-download) to download the Streaming Agent extension. If you already have the right minimum terminattr version on your EOS this can be skipped*

My vZTX onboarded to CloudVision together with my 720XP:

![my-devices](images/image-20251113203605371.png)

 

### My Arista 720XP switch

On my Arista 720XP there is very little to do except to configure the necessary connectivity between the vZTX and the 720XP switch. For that I created a vlan interface using VLAN 1111:

```bash
interface Vlan1111
   description vZTX_tunnel_interface
   ip address 172.18.111.1/24
!
interface Loopback0
   description vZTX_tunnel
   ip address 10.255.1.10/32
!
ip route 10.255.1.11/32 172.18.111.2
```

A Loopback0 interface, a static route pointing to the vZTX Loopback0 interface. Thats it for the actual switch configuration needed on the 720XP. (Dynamic routing is also possible).

Next up is CloudVision preparations



#### Connection between vZTX and my 720XP

With the above configurations done on both the vZTX and my 720XP it looks like this:



![vZTX-720XP](images/image-20251114101333854.png)

```bash
#vZTX config:
interface Ethernet1
   no switchport
   ip address 172.18.111.2/24
!
interface Loopback0
   ip address 10.255.1.11/32
!
ip route 0.0.0.0/0 172.18.111.1

#Arista 720XP switch:
interface Vlan1111
   description vZTX_tunnel_interface
   ip address 172.18.111.1/24
!
interface Loopback0
   description vZTX_tunnel
   ip address 10.255.1.10/32
!
ip route 10.255.1.11/32 172.18.111.2

```



### CloudVision preparations

The necessary MSS specific configurations on both my vZTX appliance and Arista 720XP switch will be taken care of by the MSS Service Studio. I just need to follow some initial steps to get the devices onboarded to be "MSS ready" with the MSS Service Studio.

Everything MSS related is managed by Studios and Workspaces. When the initial config has been done with the MSS Studio, the rest can be done from the Network Security section in CloudVision:

![network-security](images/image-20251113203356406.png)

To make sure all the MSS related features in CloudVision is readily available in the UI they may have to be enabled. Head over to settings in CloudVision and Features and enable the following features:

- Network Security- MSS
- Network Security - Fine-Grained Policy Monitor Loading
- Workspace Island - optional

![cvp-features](images/image-20251113202728185.png)

![workspace-island](images/image-20251113202933052.png)

Workspace Island is very useful when there are many changes that needs to be made, building, rebuilding and quickly see changes in your workspace is always there in the bottom of the screen. Readily available when you need to see what impact your changes has done etc.

Screenshot of the Island...

![workspace-island](images/image-20251113205549192.png)

Then ofcourse the MSS related features in CloudVision (if not already enabled). 

![mss-features](images/image-20251113135132913.png)



I have already onboarded my 720XP switch into CloudVision and I have also onboarded my vZTX appliance into CloudVision with minimal (but necessary) configurations done (see previous chapter on preparing the vZTX). 

I have decided to put all MGMT relevant stuff in a separate MGMT vrf. 

![my-devices](images/image-20251113203605371.png)

Now I need to do the initial config to make my vZTX and 720XP MSS "ready". This involves the Studio called "MSS Service" under Provisioning. 

{{< alert >}}

*As I am sharing the CvaaS instance with my colleagues I like to clone the Studios to my "own" Studios. Then I can do all the changes in my own Studios with my own selected devices without disrupting any of their studios and devices.* 

*With the MSS Service Studio, this will not work.* 

{{< /alert >}}

Select the default "MSS Studio" and complete the two tasks needed there:

1. Add a Security Domain
2. Add a Monitor Object

![image-20251113214852204](images/image-20251113214852204.png)

#### Security Domain and Monitor Object

The first that needs to be added to the Studio is the device selection. Add your devices (in my case my one 720XP) here under Device Selection:

![add-device-to_studio](images/image-20251113215022288.png)





Then add a Security Domain: click *+Add Security Domain*

![security-domain](images/image-20251113215114258.png)

Then type in the name of the domain and click plus to create:

![create](images/image-20251113212002224.png)

We need to click the > to add the devices we want to be part of the Security Domain. The Security Domain is the collection of switches that you want to enable a set of shared rules and policies on. This can be a site, building, branch, edge or datacenter. We can have several security domains, assigned to different sets of switches.

![click-arrow->](images/image-20251113215240807.png)





Click on the Security Domain name: security-domain:andreas-lab-domain and select the device from the dropdown menu:

![add-dev-to-domain](images/image-20251113215418329.png)

Go back by clicking at MSS Service in the blue text.

Next step is to add a Monitor Object:

![monitor-objects](images/image-20251113212452018.png)

Click + Add Monitor Object. This is quite straightforward. It will use the loopback interfaces configured on both the vZTX appliance but also the TOR switches that is part of the Security Domain. So in my lab I will use this information:

- Name: andreas-vztx
- Exporter Interface: loopback0
- Active Timeout: Default 1800000
- Tunnel Destination IP: 10.255.1.11 (the loopback0 interface ip of my vZTX)
- Tunnel Source Interface: looback0 (the loopback interface configured on all the tor switches in the security domain. Must be same interface on all)
- Rate Limit: Default 100000

Then under Monitor Cluster Click "View" and add the Monitor Node: 

![monitor-node](images/image-20251113215558215.png)



Go back by clicking on MSS Service in the blue text.

![monitor_object](images/image-20251113213526732.png)

Now a very important task. When you are back in the MSS Studio. Go all the way upp and look for the blue lightning symbol.

![lightning](images/image-20251113215718176.png)

Click it! ( I assure you, its not dangerous)

It will start a wheel for a couple of seconds and a green notification will update you when it is ready.

![auto-populate](images/image-20251113215911672.png)





Do a *build* on the Workspace Island:

![build](images/image-20251113215957973.png)



Then do a *Review*:

![review](images/image-20251113220103434.png)

Submit the Workspace:

![submit-workspace](images/image-20251113220132657.png)



![submitting](images/image-20251113213718400.png)



![success](images/image-20251113213735013.png)



Now, one can head over to Network Security and start work some magic with MSS

![network-security](images/image-20251113220314462.png)

Its now the fun begins.



### My lab

For better context, below is how my lab environment looks like.

My lab consists of two Proxmox servers forming a cluster using a qdevice (RPi) to form a quorom. These servers are both connected to the same Arista 720XP switch. My perimeter firewall is a virtual PfSense running as a virtual machine on the Proxmox servers. 

The Arista 720XP holds all my VLANs, it does routing when routing is needed between VLANs, where gateway of last resort is my PfSense firewall. I dont do much filtering between my vlans through the PfSense except a wifi guest network. 

![lab](images/image-20251114084901247.png)

That means I have a bunch of virtual machines placed in different vlans serving different needs, they are free to communicate with each other, within the same VLAN but also VLAN to VLAN. 

This is something MSS can be tasked to do something about.

## Creating network security rules and policies

By heading over to the *Network Security* section in CloudVision I will be greeted by the MSS Dashboard. This will give me a quick glimpse of my MSS "estate". From the amount of registered Monitoring Nodes and MSS Devices (MSS "enabled" switches) to events and policies related to these devices:

![mss-dashboard](images/image-20251117152241363.png)



I can go into Policy Manager to find more relevant details about my MSS Devices and Monitor Nodes. 

Under Domains I find my Security Domain *andreas-lab-domain* with my device selected:

![sec-domain](images/image-20251113220638501.png)

And under Policy Manager, Policy Objects I find my Monitor Object with my vZTX appliance assigned as Monitor Node:

![monitor-node](images/image-20251113220830377.png)

But no rules and policies yet.

Before creating any policies and rules, let us quickly go over the different things in the Network Security view and explain what they are. 



### Policy Manager

In the Policy Manager there are several sections:

- Domains
- Policies
- Rules
- Groups
- Policy Objects

Under *Domains* I can view my Security Domains, see details of the Security Domains which devices are part of the domain and any Policy assignements.

![domains](images/image-20251117152930635.png)

Under *Policies* 

What is a policy?????





### Microsegmenting my app





CLI commands to see flows, rules etc in ZTX and 720XP. 



 Iperf

```bash
sudo ethtool -K ens18 tso off gso off gro off
```

Being capped by CPU as offload is turned off. Multiqueue = amount of vCPU.

PVLAN - Port Isolation in the bridge - alternative to PVLAN.. Needs some tweaking like local-proxy-arp on the interface on the switch... 

vZTX - 

 



## Deploying MSS in my lab

### vZTX appliance

Arista MSS supports two kinds of ZTX appliances

CloudEOS - convert to monitor

When enrolled in CloudVision, make sure there are no reconciliation not applied on the device. 

### TOR switch preparation

There is a simple configuration that needs to be done on the switches that will be part of MSS. As I only have one switch in my lab, a 720XP, I just need to prepare this simple configuration on it. A P2P link to my vZTX device, and a loopback interface. These loopback interfaces must be identical across all the switches in the same security zone.



Redirect policy, flowdata, payload?





My lab topology:

Two hosts, one Arista 720XP and one vZTX.

Before I could get started with MSS I needed to prepare a couple of things. 

Either a local instance of CloudVision deployed and running,  and enabled 

## Outro

Recommend material:

Arists MSS on [YouTube](https://www.youtube.com/watch?v=WyR3oqnCu4w)



### Sources

- [Arista Multi-Domain Segmentaton - homepage](https://www.arista.com/en/products/multi-domain-segmentation/)
- [Arista Multi-Domain Segmentation - literature](https://www.arista.com/en/products/multi-domain-segmentation/literature)

