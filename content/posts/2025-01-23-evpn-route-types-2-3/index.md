---
author: "Andreas M"
title: "EVPN Route Types 2 and 3 "
date: 2025-01-23T10:17:20+01:00
description: "What is EVPN route type 2 and 3"
draft: true
toc: true
#featureimage: ""
#thumbnail: "/images/thumbnail.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Networking
  - Overlay
  - EVPN
tags:
  - networking
  - overlay
  - EVPN

summary: Going into details of EVPN route type 2 and 3
comment: false # Disable comment if false.
---



# EVPN Route Types

As promised in my previous post [EVPN Introduction](https://blog.andreasm.io/2024/12/09/evpn-introduction/) I will now go into the different route types in EVPN, what they do and when they are used. In the previous post I mention that EVPN depends on [MP-BGP](https://blog.andreasm.io/2024/12/09/evpn-introduction/#mp-bgp) to add specific EVPN BGP NLRI, aka EVPN route types. The different EVPN route types if I ask Arista EOS:

```bash
veos-dc1-leaf1a#show bgp evpn route-type ?
  auto-discovery    Filter by Ethernet auto-discovery (A-D) route (type 1)
  count             Route-type based path count
  ethernet-segment  Filter by Ethernet segment route (type 4)
  imet              Filter by inclusive multicast Ethernet tag route (type 3)
  ip-prefix         Filter by IP prefix route (type 5)
  join-sync         Filter by multicast join sync route (type 7)
  leave-sync        Filter by multicast leave sync route (type 8)
  mac-ip            Filter by MAC/IP advertisement route (type 2)
  smet              Filter by selective multicast Ethernet tag route (type 6)
  spmsi             Filter by selective PMSI auto discovery route (type 10)
```

 Where in this post I will cover route type 2 (MAC/IP advertisement route) and route type 3 (inclusive multicast ethernet tag route).

In this post I will build upon the same environment and topology as in previous post, already configured with EVPN and VXLAN.

![l3ls](images/image-20250123110235437.png)



## Route Type 2

Why start with route type 2 and 3? Not because I wanted to do it in a chronological order, because I would then start with route type 1. Route type 2 and 3 are the most common route types, where route type 2 advertises MAC addresses learnt and and route type 3 advertises IP prefixes. But which mac addresses and IP prefixes is it? This is what I will try to explain and cover here. 

In the previous post mentioned above I covered how the EVPN peers (all the leafs and spines) were advertised using BGP in the underlay to establish a secure BGP connection between all the peers. Similarily BGP is used to advertise the VTEP peers in the fabric (all the leafs). This configuration is done so the VTEPs can be "found" in the fabric and establish tunnels between them. Why I mention a secure connection is because I am using authentication between all the peers in the fabric, including the spines. One cant just add a new BGP peer in the fabric without the correct authentication, these will be dropped, this to minimize unwanted BGP peers. One can probably do more to secure the BGP connection like ACLs, additional prefix lists etc. Not in the scope for this post. Using BGP instead of static routing brings a whole lot more flexibility, and as it removes any flood and learn my network is much more optimised and scale better. Now as this is a EVPN/VXLAN fabric stretching layer 2 over my layer 3 fabric, I need BGP to also advertise layer 2 mac addresses between the VTEPS. This is where EVPN route type 2 comes into play. 

To get some more context below is my topology with their respective leafs loopback interfaces:

![loopback_interfaces_underlay](images/image-20250124152144218.png)

Lets have a look at the bgp neighbors and routing table in the underlay from spine1 and leaf1a (10.255.255.x/x are the P2P links):

```bash
veos-dc1-spine1#show bgp summary
BGP summary information for VRF default
Router identifier 10.255.0.1, local AS number 65110
Neighbor               AS Session State AFI/SAFI                AFI/SAFI State   NLRI Rcd   NLRI Acc
------------- ----------- ------------- ----------------------- -------------- ---------- ----------
10.255.0.3          65111 Established   L2VPN EVPN              Negotiated             21         21
10.255.0.4          65112 Established   L2VPN EVPN              Negotiated             21         21
10.255.0.5          65113 Established   L2VPN EVPN              Negotiated             21         21
10.255.0.6          65114 Established   L2VPN EVPN              Negotiated             77         77
10.255.255.1        65111 Established   IPv4 Unicast            Negotiated              2          2
10.255.255.5        65112 Established   IPv4 Unicast            Negotiated              2          2
10.255.255.9        65113 Established   IPv4 Unicast            Negotiated              2          2
10.255.255.13       65114 Established   IPv4 Unicast            Negotiated              2          2
```

In the bgp routing table we can see both the EVPN and VXLAN loopback interfaces. Note that I only have 4 VTEP host entries as I only configure VXLAN on the leafs. Next hop is the respective switches P2P interfaces. 

```bash
veos-dc1-spine1#show ip bgp
BGP routing table information for VRF default
Router identifier 10.255.0.1, local AS number 65110
Route status codes: s - suppressed contributor, * - valid, > - active, E - ECMP head, e - ECMP
                    S - Stale, c - Contributing to ECMP, b - backup, L - labeled-unicast
                    % - Pending best path selection
Origin codes: i - IGP, e - EGP, ? - incomplete
RPKI Origin Validation codes: V - valid, I - invalid, U - unknown
AS Path Attributes: Or-ID - Originator ID, C-LST - Cluster List, LL Nexthop - Link Local Nexthop

          Network                Next Hop              Metric  AIGP       LocPref Weight  Path
 * >      10.255.0.1/32          -                     -       -          -       0       i
 * >      10.255.0.3/32          10.255.255.1          0       -          100     0       65111 i
 * >      10.255.0.4/32          10.255.255.5          0       -          100     0       65112 i
 * >      10.255.0.5/32          10.255.255.9          0       -          100     0       65113 i
 * >      10.255.0.6/32          10.255.255.13         0       -          100     0       65114 i
 * >      10.255.1.3/32          10.255.255.1          0       -          100     0       65111 i
 * >      10.255.1.4/32          10.255.255.5          0       -          100     0       65112 i
 * >      10.255.1.5/32          10.255.255.9          0       -          100     0       65113 i
 * >      10.255.1.6/32          10.255.255.13         0       -          100     0       65114 i
```

This is just to verify that all my peers are advertised as they should, now if I add an overlay network like this:

![image-20250127092740097](images/image-20250127092740097.png)



How is that reachability advertised between the leafs so the two servers 1 and 2 can reach each other? Lets have a look at the bgp evpn route type 2 at both leaf1a and leaf2b below (sorted on the VNI 10011):

Leaf1a:

```bash
veos-dc1-leaf1a#show bgp evpn route-type mac-ip vni 10011
BGP routing table information for VRF default
Router identifier 10.255.0.3, local AS number 65111
Route status codes: * - valid, > - active, S - Stale, E - ECMP head, e - ECMP
                    c - Contributing to ECMP, % - Pending best path selection
Origin codes: i - IGP, e - EGP, ? - incomplete
AS Path Attributes: Or-ID - Originator ID, C-LST - Cluster List, LL Nexthop - Link Local Nexthop

          Network                Next Hop              Metric  LocPref Weight  Path
 * >Ec    RD: 10.255.0.6:10011 mac-ip bc24.1140.f4e4
                                 10.255.1.6            -       100     0       65110 65114 i
 *  ec    RD: 10.255.0.6:10011 mac-ip bc24.1140.f4e4
                                 10.255.1.6            -       100     0       65110 65114 i
 * >Ec    RD: 10.255.0.6:10011 mac-ip bc24.1140.f4e4 10.20.11.14
                                 10.255.1.6            -       100     0       65110 65114 i
 *  ec    RD: 10.255.0.6:10011 mac-ip bc24.1140.f4e4 10.20.11.14
                                 10.255.1.6            -       100     0       65110 65114 i
 * >      RD: 10.255.0.3:10011 mac-ip bc24.1144.8595
                                 -                     -       -       0       i
 * >      RD: 10.255.0.3:10011 mac-ip bc24.1144.8595 10.20.11.10
                                 -                     -       -       0       i
```

Leaf2b:

```bash
veos-dc1-leaf2b#show bgp evpn route-type mac-ip vni 10011
BGP routing table information for VRF default
Router identifier 10.255.0.6, local AS number 65114
Route status codes: * - valid, > - active, S - Stale, E - ECMP head, e - ECMP
                    c - Contributing to ECMP, % - Pending best path selection
Origin codes: i - IGP, e - EGP, ? - incomplete
AS Path Attributes: Or-ID - Originator ID, C-LST - Cluster List, LL Nexthop - Link Local Nexthop

          Network                Next Hop              Metric  LocPref Weight  Path
 * >      RD: 10.255.0.6:10011 mac-ip bc24.1140.f4e4
                                 -                     -       -       0       i
 * >      RD: 10.255.0.6:10011 mac-ip bc24.1140.f4e4 10.20.11.14
                                 -                     -       -       0       i
 * >Ec    RD: 10.255.0.3:10011 mac-ip bc24.1144.8595
                                 10.255.1.3            -       100     0       65110 65111 i
 *  ec    RD: 10.255.0.3:10011 mac-ip bc24.1144.8595
                                 10.255.1.3            -       100     0       65110 65111 i
 * >Ec    RD: 10.255.0.3:10011 mac-ip bc24.1144.8595 10.20.11.10
                                 10.255.1.3            -       100     0       65110 65111 i
 *  ec    RD: 10.255.0.3:10011 mac-ip bc24.1144.8595 10.20.11.10
                                 10.255.1.3            -       100     0       65110 65111 i
```

At first glance they look very similar except some "opposite" information, we can see both the mac and IP addresses of *Server 1* and *Server 2* respectively. *Leaf1a* contains a single entry of the mac and mac-ip information of *Server 1* and multiple entries of the mac and mac-ip information of *Server 2*, while *leaf2b* contains the exact opposite. Why is that?

Leaf1a has the L2VNI locally configured, so do leaf2b. Leaf1a will install the *Server 1* mac but it will also install a mac-ip entry. The reason for both entries mac and mac-ip is because I have configured an anycast gateway (IRB - Integrated routing and bridging interface) for the L2VNI, (see [here](https://blog.andreasm.io/2024/12/09/evpn-introduction/#integrated-routing-and-bridging-irb)), which means it will install also the mac-ip as a host route (/32). The reason for /32 routes (or host routes) is because an anycast gateway is a distributed router and I cant have advertised a /24 on all gateways as they dont know where to forward the traffic if the destination is not local. So in summary, in my setup EVPN route-type 2 will advertise both mac and mac-ip. 

Leaf1a will also have the routes for *Server 2* installed, but with more entries. The reason for *almost* several identical entries is because it has multiple paths to reach the destination using ECMP (Equal Cost Multipath). The destination is Leaf2b (RD 10.255.0.6) and the paths it can take are via my two spines (using same BGP AS 65110). Where the active path is indicated like this * >Ec, the ECMP head.



To get more details on the routing table on my leaf1a for the entry of my remote *Server 2* I can get that by typing *show bgp evp detail* 



```bash
veos-dc1-leaf1a#show bgp evpn detail
BGP routing table information for VRF default
Router identifier 10.255.0.3, local AS number 65111
BGP routing table entry for mac-ip bc24.1140.f4e4, Route Distinguisher: 10.255.0.6:10011
 Paths: 2 available
  65110 65114
    10.255.1.6 from 10.255.0.1 (10.255.0.1)
      Origin IGP, metric -, localpref 100, weight 0, tag 0, valid, external, ECMP head, ECMP, best, ECMP contributor
      Extended Community: Route-Target-AS:10011:10011 TunnelEncap:tunnelTypeVxlan
      VNI: 10011 ESI: 0000:0000:0000:0000:0000
  65110 65114
    10.255.1.6 from 10.255.0.2 (10.255.0.2)
      Origin IGP, metric -, localpref 100, weight 0, tag 0, valid, external, ECMP, ECMP contributor
      Extended Community: Route-Target-AS:10011:10011 TunnelEncap:tunnelTypeVxlan
      VNI: 10011 ESI: 0000:0000:0000:0000:0000
BGP routing table entry for mac-ip bc24.1140.f4e4 10.20.11.14, Route Distinguisher: 10.255.0.6:10011
 Paths: 2 available
  65110 65114
    10.255.1.6 from 10.255.0.2 (10.255.0.2)
      Origin IGP, metric -, localpref 100, weight 0, tag 0, valid, external, ECMP head, ECMP, best, ECMP contributor
      Extended Community: Route-Target-AS:10:10 Route-Target-AS:10011:10011 TunnelEncap:tunnelTypeVxlan EvpnRouterMac:bc:24:11:5e:4a:59
      VNI: 10011 L3 VNI: 10 ESI: 0000:0000:0000:0000:0000
  65110 65114
    10.255.1.6 from 10.255.0.1 (10.255.0.1)
      Origin IGP, metric -, localpref 100, weight 0, tag 0, valid, external, ECMP, ECMP contributor
      Extended Community: Route-Target-AS:10:10 Route-Target-AS:10011:10011 TunnelEncap:tunnelTypeVxlan EvpnRouterMac:bc:24:11:5e:4a:59
      VNI: 10011 L3 VNI: 10 ESI: 0000:0000:0000:0000:0000
```

This gives me some additional information, if needed, including the mac addresses of the remote leaf (leaf2b). Notice the L3 VNI: 10 which is my VRF20 mapped to VNI 10 (L3VNI).

Now lets try to map that with the EVPN NLRI of a route type 2:

```bash
+----------------------------------------+
| RD (8 octets)                          | -> 10.255.0.6:10011
+----------------------------------------+
| Ethernet Segment Identifier (10 octets)| -> 0000:0000:0000:0000:0000
+----------------------------------------+
| Ethernet Tag ID (4 octets)             | -> 0 (using VXLAN)
+----------------------------------------+
| MAC Address Length (1 octet)           | -> 6
+----------------------------------------+
| MAC Address (6 octets)                 | -> bc.24.11.40.f4.e4
+----------------------------------------+
| IP Address Length (1 octet)            | -> 4
+----------------------------------------+
| IP Address (0, 4, or 16 octets)        | -> 10.20.11.14
+----------------------------------------+
| MPLS Label1 (3 octets)                 |
+----------------------------------------+
| MPLS Label2 (0 or 3 octets)            |
+----------------------------------------+

```







#### MAC-VRF vs IP-VRF

Sometimes the expressions mac-vrf and ip-vrf are being used without any explanation of what they are or what they do. So I decided to just quickly try to explain what these two are.

First some basics which these two build upon. 

   A VLAN is a way to create layer 2, or broadcast domain, isolation in the network, I can have overlapping mac-addresses between vlans. Every VLAN has its own mac address table. A VLAN is at the data link layer (OSI 2) and uses MAC addresses which is broadcasted in the same VLAN to find its "peers" MAC addresses it needs to communicate with. There is no sence of IP addresses within the same VLAN, it only comes into play if I need to communicate across VLANS, using layer 3.

   A VRF (Virtual Routing and Forwarding) is an isolated routing instance with its own isolated routing table, allowing multiple routing tables to coexist on a single device. IP addresses and IP prefixes within a VRF are separate from those in other VRFs, allowing for overlapping IP address spaces. VRF is primarily concerned with IP routing. In a physical network, VRFs can create isolated routing domains to maintain separation of routing decisions, such as for multi-tenancy. By default, there is no reachability between network segments in different VRFs, meaning network A in VRF A cannot reach network B in VRF B unless explicitly configured with inter-VRF routing or if traffic is routed in a firewall some allow rules between the VRFs.  

> - **MAC-VRF:** A Virtual Routing and Forwarding table for storing Media Access Control (MAC) addresses on a VTEP for a specific tenant.

Source: https://www.arista.com/en/um-eos/eos-evpn-overview

Why is mac-vrf good to know about in this context? MAC-vrf is the forwarding table for mac addresses, like BGP is maintaining regular ip address forwarding table BGP-EVPN can also maintain mac address forwarding table. These tables will be used by the VTEPS to know where the different mac-addresses are located, which VTEP currently has this mac-address. As seen above the mac address *bc24.1140.f4e4* is currently local to VTEP or Route Distinguisher 10.255.0.6 which is *leaf2b* which is then advertised to the other VTEP members through BGP. By enabling EVPN (using MP-BGP) we use BGP to maintain this mac address routing table instead of using a flood and learn which would not as these l2 networks is not part of the underlay so even with flood and learn they would not learn anything from any of the other leafs, as described in the EVPN introduction post. In a layer 3 spine leaf without any use of overlay or network virtualization the l2 segments/or broadcast domains will be isolated to their local leaf.  In this context the VLAN which is mapped to a VNI and then configured in BGP for mac-advertisement is my MAC-VRF.





Now we know what EVPN route type 2 and 3 does, and why it is the most common EVPN route types. 

