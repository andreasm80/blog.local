---

author: "Andreas M"
title: "Overlay on overlay - Arista in the underlay"
date: 2024-11-08T08:56:51+01:00 
description: "Going over some typical scenarios using overlay protocols in both the compute stack and network stack"
draft: false 
toc: true
#featureimage: ""
thumbnail: "/images/1280px-Arista-networks-logo.svg.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Networking
  - EOS
  - Arista
  - Overlay
  - Encapsulation
  - Topologies
tags:
  - Networking
  - EOS
  - Arista
  - Overlay
  - Encapsulation
  - Topologies

summary: Describing typical deployments where we end up with double encapsulation, how to monitor, troubleshoot
comment: false # Disable comment if false.
---



# Spine/Leaf with EVPN and VXLAN - underlay and overlay

In a typical datacenter today a common architecture is the Spine/Leaf design ([Clos](https://en.wikipedia.org/wiki/Clos_network)). This architecture comes with many benefits such as:

- Performance 
- Scalability 
- Redundancy
- High Availability
- Simplified Network Management
- Supports East-West



## Underlay

There are two ways to design a spine leaf fabric. We can do layer 2 designs and layer 3 designs. I will be focusing on the layer 3 design in this post as this is the most common design. Layer 3 scales and performs better, we dont need to consider STP (spanning tree) and we get Equal Cost Multi Path as a bonus. In a layer 3 design all switches in the fabric are connected using routed ports, which also means there is no layer 2 possibilities between the switches, unless we introduce some kind of layer on top that can carry this layer 2 over the layer 3 links. This layer is what this post will cover and is often referrred to as the overlay layer. Before going all in on overlay I need to also cover the underlay. The underlay in a spine leaf fabric is the physical ports configured as routed ports connecting the switches together. All switches in a layer 3 fabric is being connected to each other using routed ports. All leaves exchange routes/peers with the spines.

As everything is routed we need to add some routing information in the underlay to let all switches know where to go to reach certain destinations. This can in theory be any kind of routing protocols (even static routes) supported by the [IETF](https://www.ietf.org/) such as OSFP, ISIS and BGP.

In Arista the preferred and recommended routing protocol in both the underlay and overlay is BGP. Why? BGP is the most commonly used routing protocol, it is very robust, feature rich and customisable. It supports EVPN, and if you know you are going to use EVPN why consider a different routing protocol in the underlay. That just adds more complexity and management overhead. Using BGP in both the underlay and the overlay gives a much more consistent config and benefits like BGP does not need multicast. 

So if you read any Arista deployment recommendations, use Arista Validated Design, Arista's protocol of choice will always be BGP. It just makes everything so much easier. 

In a spine leaf fabric, all leaves peers with the spines. The leaves do not peer with the other leaves in the underlay, unless there is an mlag config between two [leaf pairs](https://www.arista.com/en/um-eos/eos-multi-chassis-link-aggregation). All leaves have their own BGP AS, the spines usually share the same BGP AS.  

A diagram of the fabric underlay:

![layer-3-ls](images/image-20241127103701406.png)

In the above diagram I have confgured my underlay with layer 3 routing, BGP exhanges route information between the leaves. So far in my configuration I can not have two servers connected to different leaves on the same layer 2 subnet. Only if they are connected to the same leaf I can have layer 2 adjacency. So when server 1, connected to leaf1a, wants to talk to server 2, connected on leaf2a, it has to be over layer 3 and both servers needs to be in their own subnet. Leaf1a and leaf2a advertises its subnets to both spine1 and spine2, server 1 and 2 has been configured to use their connected leaf switches  as gateway respectively. 

If I do a ping in the "underlay" how will it look like when I ping from leaf1a to leaf2a using loopback interface 0 on my leaf1a and leaf2a to just simulate layer 3 connectivity without any overlay protocol involved (*I dont have any servers connected to a routed interfaces in my lab on any of my leaves at the moment*).

Tcpdump on leaf1a on both its uplinks (the source of the icmp request):

```bash
[ansible@veos-dc1-leaf1a ~]$ tcpdump -i vmnicet1 -nnvvv -s 0 icmp -c2
tcpdump: listening on vmnicet1, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:41:41.626368 bc:24:11:4a:9a:d0 > bc:24:11:1d:5f:a1, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 63, id 33961, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.5 > 10.255.0.3: ICMP echo reply, id 53, seq 1, length 80
13:41:41.628659 bc:24:11:4a:9a:d0 > bc:24:11:1d:5f:a1, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 63, id 33962, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.5 > 10.255.0.3: ICMP echo reply, id 53, seq 2, length 80
2 packets captured
5 packets received by filter
0 packets dropped by kernel
[ansible@veos-dc1-leaf1a ~]$ tcpdump -i vmnicet2 -nnvvv -s 0 icmp -c2
tcpdump: listening on vmnicet2, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:41:51.177083 bc:24:11:1d:5f:a1 > bc:24:11:f5:c0:d2, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 64, id 21419, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.3 > 10.255.0.5: ICMP echo request, id 54, seq 1, length 80
13:41:51.179460 bc:24:11:1d:5f:a1 > bc:24:11:f5:c0:d2, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 64, id 21420, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.3 > 10.255.0.5: ICMP echo request, id 54, seq 2, length 80
2 packets captured
2 packets received by filter
0 packets dropped by kernel
```

Notice the change of direction on the MAC addresses.

Now if I do a tcpdump on both spine 1 and spine 2 - depending on which path my request takes:

Spine1 on downlinks to leaf1a and leaf2a :

```bash
[ansible@veos-dc1-spine1 ~]$ tcpdump -i vmnicet1 -nnvvv -s 0 icmp -c2
tcpdump: listening on vmnicet1, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:44:38.739492 bc:24:11:4a:9a:d0 > bc:24:11:1d:5f:a1, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 63, id 39153, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.5 > 10.255.0.3: ICMP echo reply, id 55, seq 1, length 80
13:44:38.741578 bc:24:11:4a:9a:d0 > bc:24:11:1d:5f:a1, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 63, id 39154, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.5 > 10.255.0.3: ICMP echo reply, id 55, seq 2, length 80
2 packets captured
5 packets received by filter
0 packets dropped by kernel

[ansible@veos-dc1-spine1 ~]$ tcpdump -i vmnicet3 -nnvvv -s 0 icmp -c2
tcpdump: listening on vmnicet3, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:44:57.720811 bc:24:11:31:35:db > bc:24:11:4a:9a:d0, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 64, id 41546, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.5 > 10.255.0.3: ICMP echo reply, id 57, seq 1, length 80
13:44:57.723117 bc:24:11:31:35:db > bc:24:11:4a:9a:d0, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 64, id 41547, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.5 > 10.255.0.3: ICMP echo reply, id 57, seq 2, length 80
2 packets captured
5 packets received by filter
0 packets dropped by kernel
[ansible@veos-dc1-spine1 ~]$
```

Spine2 on downlinks to leaf1a and leaf2a:

```bash
[ansible@veos-dc1-spine2 ~]$ tcpdump -i vmnicet1 icmp -nnvvv -s 0 -c 2
tcpdump: listening on vmnicet1, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:46:42.934823 bc:24:11:1d:5f:a1 > bc:24:11:f5:c0:d2, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 64, id 64040, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.3 > 10.255.0.5: ICMP echo request, id 58, seq 1, length 80
13:46:42.937184 bc:24:11:1d:5f:a1 > bc:24:11:f5:c0:d2, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 64, id 64041, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.3 > 10.255.0.5: ICMP echo request, id 58, seq 2, length 80
2 packets captured
5 packets received by filter
0 packets dropped by kernel
[ansible@veos-dc1-spine2 ~]$ tcpdump -i vmnicet3 icmp -nnvvv -s 0 -c 2
tcpdump: listening on vmnicet3, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:46:51.617532 bc:24:11:f5:c0:d2 > bc:24:11:31:35:db, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 63, id 497, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.3 > 10.255.0.5: ICMP echo request, id 59, seq 1, length 80
13:46:51.620311 bc:24:11:f5:c0:d2 > bc:24:11:31:35:db, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 63, id 498, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.3 > 10.255.0.5: ICMP echo request, id 59, seq 2, length 80
2 packets captured
5 packets received by filter
0 packets dropped by kernel
[ansible@veos-dc1-spine2 ~]$
```

And finally on leaf2a on both its uplinks:

```bash
[ansible@veos-dc1-leaf2a ~]$ tcpdump -i vmnicet1 -nnvvv -s 0 icmp -c2
tcpdump: listening on vmnicet1, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:50:01.166378 bc:24:11:31:35:db > bc:24:11:4a:9a:d0, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 64, id 21154, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.5 > 10.255.0.3: ICMP echo reply, id 60, seq 1, length 80
13:50:01.168794 bc:24:11:31:35:db > bc:24:11:4a:9a:d0, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 64, id 21155, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.5 > 10.255.0.3: ICMP echo reply, id 60, seq 2, length 80
2 packets captured
5 packets received by filter
0 packets dropped by kernel
[ansible@veos-dc1-leaf2a ~]$ tcpdump -i vmnicet2 -nnvvv -s 0 icmp -c2
tcpdump: listening on vmnicet2, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:50:07.251988 bc:24:11:f5:c0:d2 > bc:24:11:31:35:db, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 63, id 31490, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.3 > 10.255.0.5: ICMP echo request, id 61, seq 1, length 80
13:50:07.254459 bc:24:11:f5:c0:d2 > bc:24:11:31:35:db, ethertype IPv4 (0x0800), length 114: (tos 0x0, ttl 63, id 31491, offset 0, flags [none], proto ICMP (1), length 100)
    10.255.0.3 > 10.255.0.5: ICMP echo request, id 61, seq 2, length 80
2 packets captured
5 packets received by filter
0 packets dropped by kernel
[ansible@veos-dc1-leaf2a ~]$
```



If I take a tcpdump and open it in Wireshark, I can have a look at the protocols in the frame.

![image-20241130135824702](images/image-20241130135824702.png)

Something to have in the back of the mind to later in this post...

Depending on which path my traffic takes, via spine 1 or spine 2, (remember one of the bonuses with L3 is ECMP), I see the mac address of my leaf1a `bc:24:11:1d:5f:a1` as source and the destination spine2 mac address `bc:24:11:f5:c0:d2`. Then the source IP and destination IP of their respective loopback interfaces. Nothing special here. Why do I see the spine2's mac address as destination mac address? Remember that this is a pure layer 3 fabric which means leaf1a and leaf2a are not seeing each other directly, everything is routed over spine1 and spine2. So the destination mac will be either spine1 and spine2 as those are both intermediary. The packets IP header (source and destination IP address) on the other hand corresponds to the right source and destination ip address. Its only the layer 2 ethernet header thats is being updated along the hops: leaf1a  -> spine 1 or spine 2 -> leaf2a.

For reference I have my leaf1a, spine1, spine2 and leaf2a's mac and ip address below:

```bash
[ansible@veos-dc1-leaf1a ~]$ ip link show et1
29: et1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9194 qdisc pfifo_fast state UP mode DEFAULT group default qlen 1000
    link/ether bc:24:11:1d:5f:a1 brd ff:ff:ff:ff:ff:ff
[ansible@veos-dc1-leaf1a ~]$

veos-dc1-leaf1a#show interfaces loopback 0
Loopback0 is up, line protocol is up (connected)
  Hardware is Loopback
  Description: EVPN_Overlay_Peering
  Internet address is 10.255.0.3/32
  Broadcast address is 255.255.255.255
```

```bash
[ansible@veos-dc1-spine1 ~]$ ip link show et1
16: et1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9194 qdisc pfifo_fast state UP mode DEFAULT group default qlen 1000
    link/ether bc:24:11:4a:9a:d0 brd ff:ff:ff:ff:ff:ff
[ansible@veos-dc1-spine1 ~]$
```

```bash
[ansible@veos-dc1-spine2 ~]$ ip link show et1
22: et1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9194 qdisc pfifo_fast state UP mode DEFAULT group default qlen 1000
    link/ether bc:24:11:f5:c0:d2 brd ff:ff:ff:ff:ff:ff
[ansible@veos-dc1-spine2 ~]$
```



```bash
[ansible@veos-dc1-leaf2a ~]$ ip link show et1
26: et1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9194 qdisc pfifo_fast state UP mode DEFAULT group default qlen 1000
    link/ether bc:24:11:31:35:db brd ff:ff:ff:ff:ff:ff
[ansible@veos-dc1-leaf2a ~]$

veos-dc1-leaf2a#show interfaces loopback 0
Loopback0 is up, line protocol is up (connected)
  Hardware is Loopback
  Description: EVPN_Overlay_Peering
  Internet address is 10.255.0.5/32
  Broadcast address is 255.255.255.255
```



![icmp-request-reply](images/image-20241130133641620.png)

This is fine, I can go home and rest, no one needs to use layer 2. Or... Well it depends. 

Having solved a well performing layer 3 fabric, the routing in the underlay does not help me if I want layer 2 mobility between servers, virtual machines etc connected to different layer 3 leafs. This is where the overlay part comes in to the rescue. And to make it a bit more interesting, I will add several overlay layers into the mix.  

## Overlay in the "underlay"

In a Spine/Leaf architecture **the** most used overlay protocol is [VXLAN](https://datatracker.ietf.org/doc/html/rfc7348) as the transport plane and BGP EVPN as the control plane. Why use overlay in the physical network you say? Well its the best way of moving L2 over L3, and in a "distributed world" as the services in the datacenter today mostly is we need to make sure this can be done in a controlled and effective way in our network. Doing pure L2 will not scale, L3 is the way. EVPN for multi-tenancy.

Adding VXLAN as the overlay protocol in my spine leaf fabric I can stretch my layer 2 networks across all my layer 3 leaves without worries. This means I can now suddenly have multiple servers physical as virtual in the same layer 2 subnet. To make that happen as effectively and with as low admin overhead as possible VXLAN will be the transport plane (overlay protocol) and again BGP will be used as the control plane. This means we now need to configure BGP in the overlay, on top of our BGP in the underlay. BGP EVPN will be used to create isolation and multi tenancy on top of the underlay. To quickly summarize, VXLAN is the transport protocol responsible of carrying the layer 2 subnets over any layer 3 link in the fabric. BGP and EVPN will be the control plane that always knows where things are located and can effectively inform where the traffic should go. This is stil all in the physical network fabric. As we will see a bit later, we can also introduce network overlay protocols in other parts of the infrastructure. 

![vxlan-l2-over-l3](images/image-20241127110441121.png)

In the diagram above all my leaf switches has become VTEPs, VXLAN Tunnel Endpoints. Meaning they are responsible of taking my ethernet packet coming from server 1, encapsulate it, send it over the layer 3 links in my fabric, to the destination leaf where server 2 is located. The BGP configured in the overlay here is using an EVPN address family to advertise mac addresses. If one have a look at the ethernet packet coming from server 1 and destined to server 2 we will see some differerent mac addresses, depending on where you capture the traffic of course. Lets quickly illustrate that.

The two switches in the diagram above that will be the best place to look at all packages using tcpdump will be the spine 1 and spine 2 as they are connecting everything together and there is no direct communication between any leaf, they have to go through spine 1 and spine 2. 

If I do a ping from server 1 to server 2 going over my VXLAN tunnel, how will the ethernet packet look like when captured at spine1s ethernet interface 1 (the one connected to leaf1a)?

Looking at the tcpdump below from *spine 1* I can clearly see some additional information added to the packet. First I see two mac addresses where source `bc:24:11:1d:5f:a1` is my *leaf1a*  a the destination mac address, `bc:24:11:4a:9a:d0` is my *spine1* switch. The first two ip addresses `10.255.1.3` and `10.255.1.4` is *leaf1a* and *leaf1b* VXLAN loopback interfaces respectively with the corresponding mac addresses `bc:24:11:1d:5f:a1`and `bc:24:11:9b:8f:08`. Then I get to the actual payload itself, the ICMP, between my *server 1* and *server 2* where I can see the source and destination ip of the actual servers doing the ping. 

```yaml
15:44:33.125961 bc:24:11:1d:5f:a1 > bc:24:11:4a:9a:d0, ethertype IPv4 (0x0800), length 148: (tos 0x0, ttl 64, id 0, offset 0, flags [DF], proto UDP (17), length 134)
    10.255.1.3.53892 > 10.255.1.4.4789: VXLAN, flags [I] (0x08), vni 10
bc:24:11:1d:5f:a1 > bc:24:11:9b:8f:08, ethertype IPv4 (0x0800), length 98: (tos 0x0, ttl 63, id 6669, offset 0, flags [DF], proto ICMP (1), length 84)
    10.20.11.10 > 10.20.12.10: ICMP echo request, id 10, seq 108, length 64
```

![encap-decap](images/vxlan_flow_diagram_2.gif)

A quick explanation on what we are looking at. The ICMP request comes in from *server 1* to *leaf1a* and before it sends it to its destination leaf1b (vtep) it  encapsulates the packet by removing  some headers and adding some headers. As seen above it is adding an outer header including the source and destination VTEP mac addresses (leaf1a and leaf1b). Spine1 knows of the mac and IP address for both leaf1a and leaf1b. More info on VXLAN encapsulation further down.

Having a further look at a tcpdump in Wireshark captured at Spine1:

![vxlan](images/image-20241130141355245.png)

I now notice another protocl in the header, VXLAN. The "outer" source IP and destination IP addresses are now my leaf1a and leaf1b's VXLAN loopback interfaces. The inner source and destination IP addresses will still be my original frame, namely server 1 and server 2's ip addresses:

![inner-src-dst](images/image-20241130141817568.png)



### TCPdump on Arista switches (EOS)

Doing tcpdump on Arista switches is straight forward. Its just one of the benefits Arista has as it uses its EOS operating system which is a pure Linux operating system. I can do tcpdump directly from bash or remote. Here I will show a couple of methods of doing tcpumps in EOS. 

***Locally on the switch in bash***

I will log in to the switch and be in my cli context, enter privilege mode (enable) then enter bash:

```bash
veos-dc1-leaf1a>enable
veos-dc1-leaf1a#bash

Arista Networks EOS shell

[ansible@veos-dc1-leaf1a ~]$
```

From here I have full access to the Linux operating system and can more or less use the exact same tools as I am used to in a regular Linux operating system. 

To list all available interfaces, type *ip link* as usual. 

Now I want to do a tcpdump in the interface where my Client 1 is connected and just have a quick look of whats going on:

```bash
[ansible@veos-dc1-leaf1a ~]$ tcpdump -i vmnicet5 -s 0 -c 2
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on vmnicet5, link-type EN10MB (Ethernet), snapshot length 262144 bytes
15:14:18.343604 bc:24:11:44:85:95 (oui Unknown) > 00:1c:73:00:00:99 (oui Arista Networks), ethertype IPv4 (0x0800), length 98: 10.20.11.10 > 10.20.12.10: ICMP echo request, id 11, seq 1302, length 64
15:14:18.347329 bc:24:11:1d:5f:a1 (oui Unknown) > bc:24:11:44:85:95 (oui Unknown), ethertype IPv4 (0x0800), length 98: 10.20.12.10 > 10.20.11.10: ICMP echo reply, id 11, seq 1302, length 64
2 packets captured
3 packets received by filter
0 packets dropped by kernel
[ansible@veos-dc1-leaf1a ~]$
```

If I want to save a dump to a pcap file for Wireshark I can do the following:

```bash
[ansible@veos-dc1-leaf1a ~]$ tcpdump -i vmnicet5 -s 0 -c 2 -w wireshark.pcap
tcpdump: listening on vmnicet5, link-type EN10MB (Ethernet), snapshot length 262144 bytes
2 packets captured
39 packets received by filter
0 packets dropped by kernel
[ansible@veos-dc1-leaf1a ~]$ ll
total 4
-rw-r--r-- 1 ansible eosadmin 361 Nov 28 15:20 wireshark.pcap
[ansible@veos-dc1-leaf1a ~]$ pwd
/home/ansible
[ansible@veos-dc1-leaf1a ~]$
```

Now I need to copy this one out of my switch to open it in Wireshark on my laptop. To do that I can use SCP. I will initate the scp command from my laptop and initiate the scp session from my laptop to my Arista switch and grab the file.

I have configured my out of band interface in a MGMT vrf, so for me to be able to access the switch via that interface I need to put the bash session on the switch in the MGMT vrf context. So before going into bash I need to enter the VRF and then enter bash.

```bash
[ansible@veos-dc1-leaf1a ~]$ exit
logout
veos-dc1-leaf1a#cli vrf MGMT
veos-dc1-leaf1a(vrf:MGMT)#bash

Arista Networks EOS shell

[ansible@veos-dc1-leaf1a ~]$ pwd
/home/ansible
[ansible@veos-dc1-leaf1a ~]$ ls
wireshark.pcap
[ansible@veos-dc1-leaf1a ~]$
```

Now I have placed bash in the correct context and grab the file using SCP from my client:

<div style="border-left: 4px solid #2196F3; background-color: #E3F2FD; padding: 10px; margin: 10px 0; color: #0000FF;"> <strong>Info:</strong>
The user that logs into the switch needs to be allowed to log directly to Enable mode. This is done by adding the following:
AristaSwitch#aaa authorization exec default local 
** In configure mode ** 
 </div>



From my client where I have Wireshark installed I will execute scp to copy the pcap file from the switch (*I can also run scp from the switch and copy to any destination*):

```bash
➜  vxlan_dumps scp ansible@172.18.100.103:/home/ansible/wireshark.pcap .
(ansible@172.18.100.103) Password:
wireshark.pcap                                                                                           100%  361    46.1KB/s   00:00
➜  vxlan_dumps
```

Now I can open it in Wireshark

![wireshark](images/image-20241128153913617.png)

When done, I can go back to the Arista switch log out of bash and into default vrf again like this:

```bash
[ansible@veos-dc1-leaf1a ~]$ exit
logout
veos-dc1-leaf1a(vrf:MGMT)#cli vrf default
veos-dc1-leaf1a#
```



***TCPdump remotely on the switch***

The first approach introduced many steps to get hold of some tcpdumps. 

One can also trigger tcpdumps remotely and either show them in your own terminal session or dump to a pcap file. 
To trigger the tcpdump and show live in your session I will now from my own client execute the following command:

```bash
➜  vxlan_dumps ssh ansible@172.18.100.103 "bash tcpdump -s 0 -v -vv -w - -i vmnicet5 -c 4 icmp" | tshark -i -
(ansible@172.18.100.103) Password: Capturing on 'Standard input'

tcpdump: listening on vmnicet5, link-type EN10MB (Ethernet), snapshot length 262144 bytes
4 packets captured
4 packets received by filter
0 packets dropped by kernel
    1   0.000000  10.20.11.10 → 10.20.12.10  ICMP 98 Echo (ping) request  id=0x000b, seq=3558/58893, ttl=64
    2   0.003400  10.20.12.10 → 10.20.11.10  ICMP 98 Echo (ping) reply    id=0x000b, seq=3558/58893, ttl=62 (request in 1)
    3   1.001586  10.20.11.10 → 10.20.12.10  ICMP 98 Echo (ping) request  id=0x000b, seq=3559/59149, ttl=64
    4   1.005124  10.20.12.10 → 10.20.11.10  ICMP 98 Echo (ping) reply    id=0x000b, seq=3559/59149, ttl=62 (request in 3)
4 packets captured
```



If I want to write to a pcap file and save the content directly on my laptop:

```bash
➜  vxlan_dumps ssh ansible@172.18.100.103 "bash tcpdump -s 0 -v -vv -w - -i vmnicet5 icmp -c 2" > wireshark.pcap
(ansible@172.18.100.103) Password:
tcpdump: listening on vmnicet5, link-type EN10MB (Ethernet), snapshot length 262144 bytes
2 packets captured
2 packets received by filter
0 packets dropped by kernel
➜  vxlan_dumps
```

Now I can open it in Wireshark. All the different tcpdump options and variables is ofcourse options to play around with. It is the exact tcpdump tool you use in your everyday Linux operating system. Its not a Arista specific tcpdump tool. 



For more information using tcpdump and scp with Arista switches head over [here](https://arista.my.site.com/AristaCommunity/s/article/using-tcpdump-for-troubleshooting) and [here](https://arista.my.site.com/AristaCommunity/s/article/how-to-ftp-scp-winscp).



## Overlay in the compute stack

Up until now I have covered the underlay config briefly in a spine leaf, then the overlay in the spine leaf to overcome the layer 3 boundaries. But in the software or compute stack that is connecting to our fabric we can stumble upon other overlay protocols too. 

Even though VXLAN is the most common overlay protocol, there are other overlay protocols being used in the datacenter, like [Geneve](https://datatracker.ietf.org/doc/html/rfc8926), and even NVGre and STT. This blog will discuss some typical scenarios where we deal with "layers" of overlay protocols.

Yes, the services connecting to my network also happen to use some kind of overlay protocol, can I have encapsulation on top of encapsulation? Yes, why not? In some environments we may even end up with overlay on top of overlay on top of another overlay (three "layers" of overlay). That's not possible, you are pulling a joke here right? No I am not, yes that is fully possible and occurs very frequent. But I will loose all visibility!? Why? Using VXLAN or Geneve does not mean the traffic is being encrypted. For an network admin its not always obvious that such scenarios exist, but they do and should be something to be aware of in case something goes wrong or they suddenly discovers a new overlay protocol in their network.

In such scenarios though, like the movie Inception, it will be important to know how things fits together, where to monitor, how to monitor, what to think of making sure there is nothing in the way of the tunnels to be established. This is something I will try to go through in this post. How these thing fits together.  

One example of running overlay on top of overlay is in environments where VMware (by Broadcom) NSX is involved. VMware NSX is using Geneve[^1] to encapsulate their Layer2 NSX Segments over any fabric between their VTEPS (usually the ESXi host transport nodes, the NSX Edges is also considered TEPS in an NSX environment). If this is connected to a spine/leaf fabric we will have VXLAN and Geneve overlay protocols moving L2 segments between their own respective VTEPS (*VTEP for VXLAN, NSX just calls it TEP nowadays*). 



Below we have a spine leaf fabric using VXLAN and NSX in the compute layer using Geneve. All network segments created in NSX leaving and entering a ESXi host will be encapsulated using Geneve, and that also means all services ingressing the leafs from these ESXi hosts will get another round of encapsulation using VXLAN. I will describe this a bit better later, below is a very high level illustration.

![nsx-teps-arista-vteps](images/image-20241108111853681.png)

But what if we are also running Kubernetes in our VMware NSX environment, which also happens to use some kind of overlay protocol (common CNIs supports VXLAN/Geneve/NVGre/STT) between the control and worker nodes. That will be hard to do right? Should we disable encapsulation in our Kubernetes clusters then? No, well it depends of course, but if you dont have any specific requirements to NOT use overlay (*like no-snat*) between your Kubernetes nodes then it makes your Kubernetes network connectivity (like pod to pod across nodes) so much easier. 

How will this look like then?

![kubernetes-overlay](images/image-20241108122625081.png)

Doesn't look that bad? Now if I were Leonardo DiCaprio in Inception it would be a walk in the park. 

## Where is encapsulation and decapsulation done

It is important to know where the ethernet frames are being encapsulated and decapsulated so one can understand where things may go wrong. Lets start with the Spine/Leaf fabric. 

When traffic or the network services enters or ingresses on any of the leafs in the fabric its the leafs role to encapsulate and decapsulate the traffic. The leafs in a VXLAN spine/leaf fabric are considered our VTEP's (VXLAN Tunnel Endpoints). I have two servers connected to two different leafs, and also happens to be on two different VNIs (VXLAN Network Identifier), where server A needs to send a packet to server B the receiving leaf will encapsulate the ingress, then send it via any of the spines to the leaf where server B is connected and this leaf will then decapsulate the packet before its delivered to server B. See below:

![spine/leaf/encap-decap](images/image-20241110201118681.png)

How will this look if I add NSX into the mix? The below traffic flow will only be true if source and destination is not leaving the NSX "fabric", meaning it is traffic between two vms in same NSX segment or two different NSX segments. If traffic is destined to go outside the NSX fabric it will need to leave via the NSX edges which will "normalise" the traffic and decapsulate the traffic to regular MTU size 1500 if not adjusted in the Edge uplinks to use bigger mtu size than default 1500. 

![nsx-over-vxlan](images/image-20241110202627504.png)

What about Kubernetes as the third overlay layer?

![kubernetes-encapsulation](images/image-20241110203609485.png)

When traffic egresses a Kubernetes nodes configured to use VXLAN or Geneve it will encapsulate the original header, if the Kubernetes nodes are running in a NSX segment the ESXi hosts currently holding the Kubernetes nodes will then add its encapsulation before egressing the packet, and finally this traffic will hit the physical Arista VTEPS/Leaf switches in the physical fabric which will also add its encapsulation before egressing to the spines. Then from the leaf to the esxi hosts to the pods the traffic will slowly but surely be decapsulated to finally arrive at the destination as the original ethernet frame stripped from any additional encapsulation headers. 

## Will it fit then?

A default ethernet frame size is 1500MTU (Maximum Transmission Unit). When encapsulating a standard ethernet frame using VXLAN some headers are removed from the original frame, and additional headers are being added. See illustration:

![std-eth-frame](images/image-20241109101619428.png)

Standard Ethernet fram to a VXLAN encapsulated ethernet frame:

![headers-stripped-and-added](images/image-20241109102130032.png)

![vxlan-encapsulation](images/image-20241109102047130.png)





These additional headers requires some more room which makes the default size of 1500mtu too small. So in a very simple setup using VXLAN encapsulation we need to accomodate for this increase in size.  If this is not considered you will end up with nothing working. A general rule of thumb, VXLAN and Geneve will not handle fragmentation and will drop if it does not fit. A new buzzword will then become *its always MTU*.

Why is that? Imagine you have a rather big car and the road you are driving has a tunnel, this tunnel is not big enough to actually fit your car (One of the few times in your life, but assume its a monster truck you are driving). If you dont pay attention and just make a run for it, entering the tunnel will come to a hard stop. 

<img src=images/image-20241109103140283.png style="width:600px" />

And if something should happen to come out on the other side of the tunnel it will most likely be fragments of the car. Which we dont like. We do like our cars whole, as we like our network packets whole.

If the tunnel is big enough to accommodate the biggest monster truck, then it should be fine.

<img src=images/image-20241109103359204.png style="width:600px" />

The monster truck both enters and exits the tunnel safe and sound and in the exact same shape it entered. No pieces torn off or ripped off to fit the tunnel. 

If the tunnel will bearly fit the car, you can bet some pieces would be torn off, like side mirrors etc. This can be translated into dropped packets, which we dont want.

If the monster truck diagram is not depictive enough, lets try another illustration. Imagine you have two steel pipes of equal diameter and width and you want one pipe to be inserted into the other pipe to maybe extend the total length by combining the two. Pretty hard to do, welding is propably your best option here. But if one pipe had a smaller diameter so it could actually fit inside the other pipe, then it would slide in without any issue. 

![pipe-into-pipe-into-pipe](images/image-20241110194248212.png) 

Imagine the last pipe on the right is the Arista spine/leaf fabric. This should be the part of the infrastructure that must accommodate the biggest allowed MTU size. Then the green pipe will be the NSX environment which needs to tune their MTU setting on the TEP side (host profile) to fit the MTU size set in the Arista Fabric. Arista is default configured to use 9214 MTU. Then the Kubernetes cluster running in NSX segments also needs to adapt to the MTU size in the NSX environment.

This should be fairly easy to calculate as long as one know which overlay protocol being used, how much the additional headers will impose on the ethernet frame. See VXLAN above. Be aware that VXLAN has fixed headers so you will always know the exact MTU size, Geneve on the other hand (call it an VXLAN extension) is using dynamic headers and needs to be taken into consideration, it may need more room than VXLAN. 

For VLXLAN we need at least 50 additional bytes: 14b (outer ethernet header) + 20b (outer IP header) + 8b (outer udp header) + 8b (VXLAN header) = 50b

So, to summarize. As long as one are aware of these MTU requirements it should be fine to run multiple stacked overlay protocols.

## Simulating an environment with triple encapsulation

I have configured in my lab a spine leaf fabric using Arista vEOS switches. It is a full spine leaf fabric using EVPN and VXLAN. The fabric has been configured with 3 VRFS. A dedicated oob mgmt vrf called MGMT. Then VRF 10 for vlan 11-3 and VRF 11 for vlan 21-23. Then I have attached three virtual machines on each of their leaf switches. Server 1 is attached to leaf1a, server 2 is attached to leaf1b and server 3 is attached to leaf2a. These three servers have been configured with two network cards each.

NIC1 (ens18) on all three have been configured and placed in VRF10 but in their own vlan, vlan 11-13 respectively for their "management" interface. VRF 10 is the only VRF that is configured to reach internet. NIC2 (ens19) on all three servers have been configured and placed in an another VRF, VRF11, also placed in their separate vlan (vlan 21-23) respectively. NIC2 (ens19) have been configured to use VXLAN via a bridge called br-vxlan on all three servers to span a common layer 2 subnet across these 3 servers. Kubernetes is installed and configured on these servers. The pod network is using the second nic interfaces over VXLAN and the CNI inside Kubernetes has been configured to provide its own overlay protocol which happens to be Geneve. So in this scenario I have 3 overlay protocols in motion. VXLAN configured in my Arista spine leaf, VXLAN in the Ubuntu operating system layer, then Geneve in the pod network stack. 
*The only reason I have chosen to use a dedicated management interface is just so I can have a network that is only encapsulated in my Arista fabric. Kubernetes can work perfectly well with just on network card, also most common config.* 

I have tried to illustrate my setup below, to get some more context. 



![kubernetes-compute-layer](images/image-20241130160953187.png)

![three-overlays](images/image-20241201104907035.png)

| Server 1                                             | Server 2                                             | Server 3                                             |
| ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| ens18 - 10.20.11.10/24                               | ens18 - 10.20.12.10/24                               | ens18 - 10.20.13.10/24                               |
| ens19 - 10.21.21.10/24                               | ens19 - 10.21.22.10/24                               | ens19 - 10.21.23.10/24                               |
| br-vxlan (vxlan via ens19) - 192.168.100.11/24       | br-vxlan (vxlan via ens19) - 192.168.100.12/24       | br-vxlan (vxlan via ens19) - 192.168.100.13/24       |
| pod-cidr (Antrea geneve tun0 via ens19) 10.40.0.0/24 | pod-cidr (Antrea geneve tun0 via ens19) 10.40.1.0/24 | pod-cidr (Antrea geneve tun0 via ens19) 10.40.2.0/24 |

*K8s cluster pod cidr is 10.40.0.0/16, each node carves out pr default a /24.* 

When the 3 nodes communicate with each other using ens18 they will only be encapsulated once, but when using the br-vxlan interface it will be double encapsulated, first vxlan in the server, then in the Arista fabric. When the pods communicate between nodes I will end up with triple encapsulation, Geneve, VXLAN in the server then VXLAN in the Arista fabric. Now it starts to be interesting.
The Antrea CNI has been configured to use br-vxlan as pod transport interface:

```yaml
# traffic across Nodes.
transportInterface: "br-vxlan"
```



### Let see some triple encapsulation in action

I have two pods deployed called *ubuntu-1* and *ubuntu-2* with one Ubuntu container instance in each pod, these two are running on ther own Kubernetes node 1 and 2. So they have to egress the nodes to communicate. How will this look like if I do a TCP dump on spine 1 or 2 if I initiate a ping from pod ubuntu-1 and ubuntu-2?

![pod-2-pod](images/image-20241201114908055.png)

![triple-encap](images/image-20241201114323805.png)

Protocols in frame: vxlan, vxlan and geneve - look at that. Whats more inside? Lets have a look at the different headers:

```bash
Frame 10: 248 bytes on wire (1984 bits), 248 bytes captured (1984 bits)
    Encapsulation type: Ethernet (1)
    Arrival Time: Dec  1, 2024 11:41:13.749900000 CET
    UTC Arrival Time: Dec  1, 2024 10:41:13.749900000 UTC
    Epoch Arrival Time: 1733049673.749900000
    [Time shift for this packet: 0.000000000 seconds]
    [Time delta from previous captured frame: 0.092505000 seconds]
    [Time delta from previous displayed frame: 0.092505000 seconds]
    [Time since reference or first frame: 0.648590000 seconds]
    Frame Number: 10
    Frame Length: 248 bytes (1984 bits)
    Capture Length: 248 bytes (1984 bits)
    [Frame is marked: False]
    [Frame is ignored: False]
    [Protocols in frame: eth:ethertype:ip:udp:vxlan:eth:ethertype:ip:udp:vxlan:eth:ethertype:ip:udp:geneve:eth:ethertype:ip:icmp:data]
    [Coloring Rule Name: ICMP]
    [Coloring Rule String: icmp || icmpv6]
Ethernet II, Src: ProxmoxServe_4a:9a:d0 (bc:24:11:4a:9a:d0), Dst: ProxmoxServe_1d:5f:a1 (bc:24:11:1d:5f:a1)
    Destination: ProxmoxServe_1d:5f:a1 (bc:24:11:1d:5f:a1)
    Source: ProxmoxServe_4a:9a:d0 (bc:24:11:4a:9a:d0)
    Type: IPv4 (0x0800)
    [Stream index: 0]
Internet Protocol Version 4, Src: 10.255.1.4, Dst: 10.255.1.3
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0x00 (DSCP: CS0, ECN: Not-ECT)
        0000 00.. = Differentiated Services Codepoint: Default (0)
        .... ..00 = Explicit Congestion Notification: Not ECN-Capable Transport (0)
    Total Length: 234
    Identification: 0x0000 (0)
    010. .... = Flags: 0x2, Don't fragment
    ...0 0000 0000 0000 = Fragment Offset: 0
    Time to Live: 63
    Protocol: UDP (17)
    Header Checksum: 0x22ff [validation disabled]
    [Header checksum status: Unverified]
    Source Address: 10.255.1.4
    Destination Address: 10.255.1.3
    [Stream index: 1]
User Datagram Protocol, Src Port: 53766, Dst Port: 4789
    Source Port: 53766
    Destination Port: 4789
    Length: 214
    Checksum: 0x0000 [zero-value ignored]
    [Stream index: 7]
    [Stream Packet Number: 1]
    [Timestamps]
    UDP payload (206 bytes)
Virtual eXtensible Local Area Network
    Flags: 0x0800, VXLAN Network ID (VNI)
    Group Policy ID: 0
    VXLAN Network Identifier (VNI): 11
    Reserved: 0
Ethernet II, Src: ProxmoxServe_9b:8f:08 (bc:24:11:9b:8f:08), Dst: ProxmoxServe_1d:5f:a1 (bc:24:11:1d:5f:a1)
    Destination: ProxmoxServe_1d:5f:a1 (bc:24:11:1d:5f:a1)
    Source: ProxmoxServe_9b:8f:08 (bc:24:11:9b:8f:08)
    Type: IPv4 (0x0800)
    [Stream index: 1]
Internet Protocol Version 4, Src: 10.21.22.10, Dst: 10.21.21.10
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0x00 (DSCP: CS0, ECN: Not-ECT)
        0000 00.. = Differentiated Services Codepoint: Default (0)
        .... ..00 = Explicit Congestion Notification: Not ECN-Capable Transport (0)
    Total Length: 184
    Identification: 0x8d6a (36202)
    000. .... = Flags: 0x0
    ...0 0000 0000 0000 = Fragment Offset: 0
    Time to Live: 63
    Protocol: UDP (17)
    Header Checksum: 0xae8d [validation disabled]
    [Header checksum status: Unverified]
    Source Address: 10.21.22.10
    Destination Address: 10.21.21.10
    [Stream index: 2]
User Datagram Protocol, Src Port: 56889, Dst Port: 4789
    Source Port: 56889
    Destination Port: 4789
    Length: 164
    Checksum: 0x93c6 [unverified]
    [Checksum Status: Unverified]
    [Stream index: 8]
    [Stream Packet Number: 1]
    [Timestamps]
    UDP payload (156 bytes)
Virtual eXtensible Local Area Network
    Flags: 0x0800, VXLAN Network ID (VNI)
    Group Policy ID: 0
    VXLAN Network Identifier (VNI): 666
    Reserved: 0
Ethernet II, Src: 0e:a9:a0:1b:df:4b (0e:a9:a0:1b:df:4b), Dst: a6:58:bc:c5:47:62 (a6:58:bc:c5:47:62)
    Destination: a6:58:bc:c5:47:62 (a6:58:bc:c5:47:62)
    Source: 0e:a9:a0:1b:df:4b (0e:a9:a0:1b:df:4b)
    Type: IPv4 (0x0800)
    [Stream index: 2]
Internet Protocol Version 4, Src: 192.168.100.12, Dst: 192.168.100.13
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0x00 (DSCP: CS0, ECN: Not-ECT)
        0000 00.. = Differentiated Services Codepoint: Default (0)
        .... ..00 = Explicit Congestion Notification: Not ECN-Capable Transport (0)
    Total Length: 134
    Identification: 0x1921 (6433)
    010. .... = Flags: 0x2, Don't fragment
    ...0 0000 0000 0000 = Fragment Offset: 0
    Time to Live: 64
    Protocol: UDP (17)
    Header Checksum: 0xd7db [validation disabled]
    [Header checksum status: Unverified]
    Source Address: 192.168.100.12
    Destination Address: 192.168.100.13
    [Stream index: 3]
User Datagram Protocol, Src Port: 19380, Dst Port: 6081
    Source Port: 19380
    Destination Port: 6081
    Length: 114
    Checksum: 0x0000 [zero-value ignored]
    [Stream index: 9]
    [Stream Packet Number: 1]
    [Timestamps]
    UDP payload (106 bytes)
Generic Network Virtualization Encapsulation, VNI: 0x000000
Ethernet II, Src: ce:7f:43:8a:0e:3c (ce:7f:43:8a:0e:3c), Dst: aa:bb:cc:dd:ee:ff (aa:bb:cc:dd:ee:ff)
    Destination: aa:bb:cc:dd:ee:ff (aa:bb:cc:dd:ee:ff)
    Source: ce:7f:43:8a:0e:3c (ce:7f:43:8a:0e:3c)
    Type: IPv4 (0x0800)
    [Stream index: 4]
Internet Protocol Version 4, Src: 10.40.1.3, Dst: 10.40.2.4
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0x00 (DSCP: CS0, ECN: Not-ECT)
        0000 00.. = Differentiated Services Codepoint: Default (0)
        .... ..00 = Explicit Congestion Notification: Not ECN-Capable Transport (0)
    Total Length: 84
    Identification: 0x6661 (26209)
    010. .... = Flags: 0x2, Don't fragment
    ...0 0000 0000 0000 = Fragment Offset: 0
    Time to Live: 63
    Protocol: ICMP (1)
    Header Checksum: 0xbdf1 [validation disabled]
    [Header checksum status: Unverified]
    Source Address: 10.40.1.3
    Destination Address: 10.40.2.4
    [Stream index: 6]
Internet Control Message Protocol
    Type: 8 (Echo (ping) request)
    Code: 0
    Checksum: 0x1431 [correct]
    [Checksum Status: Good]
    Identifier (BE): 652 (0x028c)
    Identifier (LE): 35842 (0x8c02)
    Sequence Number (BE): 97 (0x0061)
    Sequence Number (LE): 24832 (0x6100)
    [Response frame: 11]
    Timestamp from icmp data: Dec  1, 2024 11:41:13.748161000 CET
    [Timestamp from icmp data (relative): 0.001739000 seconds]
    Data (40 bytes)

```



### Monitor and troubleshoot mtu issues 

Everything has been configured but nothing works. Could it be MTU? Lets quickly go through how to check for MTU issues and if it is related to any overlay protocols being dropped due to defragmentation.

As more or less everything in your datacenter needs to traverse the spine leaf fabric (unless VM to VM traffic on same host within same VLAN or two different NSX segments but still on same host) to gather as much information of whats going on in as few places as possible I will start by capturing some information from my spines. Looking for defragmentation also depends on where the defragmentation happens in the infrastructure. 

**How to see if the traffic is double or even triple encapsulated?**

Connected to my spine leaf fabric I have a Kubernetes cluster where the nodes are connected over a VXLAN tunnel, already there I have double encapsulation. Then the pods have been configured to use another overlay tunnel using Geneve.  The Kubernetes nodes uses VXLAN as they are placed on different leaves and on different vlans/subnets. For the sake of this post I have confgured the nodes to simulate the additional overlay layer as a potential NSX environment would have (I dont have access to NSX any longer in my lab). 

 

See VXLAN packets, look for defragmentation. 

VXLAN ports and Geneve ports

How can I see that double encapsulation is the case, or even triple encapsulation?

How can I see fragmentation... Could something be seen in the stream coming from TerminAttr?

What about performance?

There is nothing denying that running only overlay in the Arista fabric would be far the most performant way of doing it. There is nothing denying that if switching is done by the part in your network that has this as its sole role we often refer to terms like line rate speed. This is because network switches are purpose built devices with some very efficient CPU (ASICS) to handle switching and routing. 





[^1]: *(Earlier version of VMware NSX called NSX-V used VXLAN too, for a period VMware had two NSX versions NSX-V and NSX-T where the latter used Geneve and is the current NSX product, NSX-V is obsolete and NSX-T now is the only product and is just called NSX.)*

