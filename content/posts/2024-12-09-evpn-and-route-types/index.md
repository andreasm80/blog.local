---
author: "Andreas M"
title: "EVPN introduction"
date: 2024-12-09T14:55:58+01:00
description: "What is EVPN? An introduction to EVPN"
draft: true
toc: true
#featureimage: ""
#thumbnail: "/images/thumbnail.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Networking
  - EVPN
  - Encapsulation
  - Overlay
tags:
  - evpn
  - networking
  - multi-tenancy
  - vxlan
  - overlay

summary: First post in a series of posts covering EVPN and getting to know EVPN
comment: false # Disable comment if false.
---



# Ethernet Virtual Private Network

This post marks the begining of a series I am covering on EVPN. The first informational RFC([RFC7209](https://datatracker.ietf.org/doc/rfc7209/)) for EVPN was posted May 2014. It is just a coincidence that EVPN is now on its 10th year and I am writing this blog series. As I have the pleasure of working together with some of the best in the industry, which is motivating on its own, I highly encourage everyone to have a look at this [video](https://youtu.be/QIfClRUl3Bg?si=0I_bhpR3S05iwTp9) from my colleague Johan where he takes us brilliantly through EVPN's 10 year history. 

As this blog series will evolve I will cover EVPN and its different Route Types and EVPN gateways to get a better understanding of what they are, and why they are needed. But first, a quick introduction to EVPN in general. What is EVPN, what is EVPN's responsibilities in the datacenter, and why EVPN. Lets go ahead and try to cast some light on this.

## Layer 2 over layer 3

As the datacenter networking (and campus to a certain degree) has evolved from the traditional core, distribution and access topology to the much more scalable spine-leaf topology, the need for layer 2 did not disappear. MAC mobility/vMotion of virtual machines, application requirements like cluster services, iot devices etc are examples that rely on layer 2 reachability. The move away from large broadcast domains in the networks to IP fabric solved a lot of challenges in terms of scalability, performance and resilience. In its own it was a case closed for any loops, broadcast storms scenarios and poor utilization. Though many services in your network still relies on layer 2 though, so how to solve that in a pure layer 3 IP fabric like spine-leaf? 

Existing services as VPLS and Ethernet L2VPN existed, but had its limitations.

To quote the RFC7209:

>    The widespread adoption of Ethernet L2VPN services and the advent of
>    new applications for the technology (e.g., data center interconnect)
>    have culminated in a new set of requirements that are not readily
>    addressable by the current Virtual Private LAN Service (VPLS)
>    solution.  In particular, multihoming with all-active forwarding is
>    not supported, and there's no existing solution to leverage
>    Multipoint-to-Multipoint (MP2MP) Label Switched Paths (LSPs) for
>    optimizing the delivery of multi-destination frames.  Furthermore,
>    the provisioning of VPLS, even in the context of BGP-based auto-
>    discovery, requires network operators to specify various network
>    parameters on top of the access configuration.  This document
>    specifies the requirements for an Ethernet VPN (EVPN) solution, which
>    addresses the above issues.





## EVPN, BGP and Network Virtualization Overlay - control plane vs dataplane

What is EVPN? The short answer is that EVPN is an extension to BGP. But that doesn't help much does it? Lets see if I can go a bit deeper. 

In a spine-leaf fabric all switches are connected using layer 3 links. If all the services connected to the fabric can do fine with layer 3 and be in their own IP subnet, I am fine. Traffic is routed as needed and full reachability is taken care of.

![l3-reachability](images/image-20241219095711506.png)

If I need to extend layer 2 beyond any leaf I am not so fine. 

![layer2](images/image-20241219100258542.png)

Without any form of mechanisms like overlay control-/and dataplane I am not able to extend my layer 2 network beyond a single leaf. So if I need layer 2 reachability across leafs in the same fabric I need mechanisms that can handle layer 2 over layer 3. The first thing we need is a protocol to create overlay networks that can tunnel, or simulate, layer 2 subnets over layer 3, this can be VXLAN as an example. 

![vxlan-encapsulation](images/image-20241219101030140.png)

By having protocols like VXLAN to create overlay networks in place it provides the ability to extend my layer 2 subnets across my layer 3 fabric. Managing this at scale though can be hard if not the right mechanisms is in place to accommodate a very dynamic environment such as vm sprawl, multiple tenants etc, we need something that can manage the reachability information in a clever, controlled and scalable way and something that understands network virtualization overlay.  

I can use static routes then? Well in theory I could, but that will just defeat the purpose of scalability and simpler management and there is no reason to build a spine-leaf fabric to begin with. 

BGP? Yes, it is a very good start. But I cant use regular BGP. 

Regular BGP ([RFC4271](https://datatracker.ietf.org/doc/html/rfc4271)):

> The only three pieces of information carried by BGP-4 [BGP-4] that
>    are IPv4 specific are (a) the NEXT_HOP attribute (expressed as an
>    IPv4 address), (b) AGGREGATOR (contains an IPv4 address), and (c)
>    NLRI (expressed as IPv4 address prefixes).

Source: https://datatracker.ietf.org/doc/html/rfc4760

As regular BGP can only handle IP addresses and IP prefixes it is not sufficient. We need something that can handle a richer set of reachability information, to be able to handle network reachability information when using overlay protocols like VXLAN.

In a spine-leaf fabric these layer 2 networks can be referred to as tenants, virtualized network segments or VPN instances. The need for multiple tenants could be to allow several layer 2 networks sharing the same physical underlay fabric, multiple customers and services sharing the same fabric and even overlapping layer 2 subnets. EVPN allows for these tenants to be configured and isloated in the shared fabric as it enables BGP to have MAC addresses and MAC plus IP addresses as routing entries. In a regular layer 2 switch network, the switches learn how to forward traffic by looking at the Ethernet Frame's MAC headers. An Ethernet Frame consists of a source MAC header and destination MAC header. With an overlay protocol like VXLAN, the standard Ethernet frame is encapsulated adding some additional headers including the source and destination MAC address of the VTEPS and the source and destination IP address of the VTEPS. With EVPN we have a way to capture this additional information and add it to the routing table dynamically allowing the VXLAN tunnels to be established to relevant peers (VTEPS). The peers in VXLAN is called VTEPs, VXLAN Tunnel End Points. 

After the first informational [RFC7209](https://datatracker.ietf.org/doc/rfc7209/) that specified the intention and requirements with EVPN, just under a year later, the initial EVPN standard [RFC7432](https://datatracker.ietf.org/doc/rfc7432/) was posted. The initial EVPN standard (RFC7432) was written with MPLS in mind, however some years later (2018) the [RFC8365](https://datatracker.ietf.org/doc/rfc8365/) was posted describing how EVPN can be used as a network virtualization overlay in combinaton with various encapsulation options like VXLAN, NVGRE, MPLS over GRE and even Geneve. Now why do I mention these RFCs in addtion to the initial RFC7209 from 2014? Well stay tuned to get some clarity on this point.  

First, EVPN stands for Ethernet VPN. EVPN is capable of managing both layer 2 (Ethernet MAC) and IP (layer 3) reachability information. That means EVPN is **not** the carrier of the actual ethernet frames or IP packets, it just informs the interested parties whats the source and destination. And to do that, it uses BGP or rather MP-BGP (Multi-Protocol BGP [RFC4760](https://datatracker.ietf.org/doc/html/rfc4760) an extension to the regular BGP). One of the benefits of BGP is that it does not rely on flood-and-learn in the dataplane, but uses instead a control-plane based learning allowing to restrict who learns what and the ability to apply policies. This reduces unnecessary flooding and is much more scalable. Wasn't this a post about EVPN? Well EVPN uses BGP as its control plane, and the extension to BGP, MP-BGP, makes BGP capable of handle the advertising of additional EVPN routes. Suddenly there is MP-BGP into the mix? 

### MP-BGP

Yes, it is. MP-BGP extends BGP to carry multiple address families, which is needed to handle overlay encapsulation that comes with the use of e.g VXLAN.

>    To provide backward compatibility, as well as to simplify
>    introduction of the multiprotocol capabilities into BGP-4, this
>    document uses two new attributes, Multiprotocol Reachable NLRI
>    (MP_REACH_NLRI) and Multiprotocol Unreachable NLRI (MP_UNREACH_NLRI).
>    The first one (MP_REACH_NLRI) is used to carry the set of reachable
>    destinations together with the next hop information to be used for
>    forwarding to these destinations.  The second one (MP_UNREACH_NLRI)
>    is used to carry the set of unreachable destinations.  Both of these
>    attributes are optional and non-transitive.  This way, a BGP speaker
>    that doesn't support the multiprotocol capabilities will just ignore
>    the information carried in these attributes and will not pass it to
>    other BGP speakers.



> Multiprotocol Reachable NLRI - MP_REACH_NLRI (Type Code 14):
>
> This is an optional non-transitive attribute that can be used for the
> following purposes:
>
> (a) to advertise a feasible route to a peer
>
> (b) to permit a router to advertise the Network Layer address of the
>     router that should be used as the next hop to the destinations
>     listed in the Network Layer Reachability Information field of the
>     MP_NLRI attribute.
>
> The attribute is encoded as shown below:

Source: https://datatracker.ietf.org/doc/html/rfc4760

```bash
        MP-BGP Reachable NLRI
        +---------------------------------------------------------+
        | Address Family Identifier (2 octets)                    |
        +---------------------------------------------------------+
        | Subsequent Address Family Identifier (1 octet)          |
        +---------------------------------------------------------+
        | Length of Next Hop Network Address (1 octet)            |
        +---------------------------------------------------------+
        | Network Address of Next Hop (variable)                  |
        +---------------------------------------------------------+
        | Reserved (1 octet)                                      |
        +---------------------------------------------------------+
        | Network Layer Reachability Information (variable)       |
        +---------------------------------------------------------+
```



EVPN will use MP-BGP to add new BGP Network Layer Reachability Information (NLRI), the EVPN NLRI. This is where we will get a set of different EVPN route types, which I will cover in separate posts later. 
The EVPN NLRI is carried in BGP using MP-BGP with an Address Family Identifier of 25 (L2VPN) and a Subsequent Address Family Identifier of 70 (EVPN).

The different route types of EVPN will be covered in detail in their own as part of this EVPN blog post series. 

I will just quickly use EVPN route type 2, MAC/IP advertisement, as an example for clarification of how this fits in.

This is how a EVPN MAC/IP, route type 2, advertisement specific NLRI consists of (scroll down inside code viewer to see all):

```bash
                +---------------------------------------+
                |  RD (8 octets)                        |
                +---------------------------------------+
                |Ethernet Segment Identifier (10 octets)|
                +---------------------------------------+
                |  Ethernet Tag ID (4 octets)           |
                +---------------------------------------+
                |  MAC Address Length (1 octet)         |
                +---------------------------------------+
                |  MAC Address (6 octets)               |
                +---------------------------------------+
                |  IP Address Length (1 octet)          |
                +---------------------------------------+
                |  IP Address (0, 4, or 16 octets)      |
                +---------------------------------------+
                |  MPLS Label1 (3 octets)               |
                +---------------------------------------+
                |  MPLS Label2 (0 or 3 octets)          |
                +---------------------------------------+
```

 


All fields above are necessary to describe the complete EVPN route, though the fields Ethernet Segment Identifier, MPLS Label 1 and MPLS Label 2 are all in the NLRI, but not part of the route prefix used for route uniqueness. If reading the RFC7432:

>    **For the purpose of BGP route key processing, only the Ethernet Tag*
>    *ID, MAC Address Length, MAC Address, IP Address Length, and IP*
>    *Address fields are considered to be part of the prefix in the NLRI.*
>    *The Ethernet Segment Identifier, MPLS Label1, and MPLS Label2 fields*
>    *are to be treated as route attributes as opposed to being part of the*
>    "route".  Both the IP and MAC address lengths are in bits.*

This can be a bit confusing. In terms of BGP they are not to be seen as attributes in a traditional "BGP sense" like AS_PATH or COMMUNITY etc. 
Note: Even though there are two fields called MPLS Label 1 and 2 does not mean EVPN is not multi-protocol aware. Overlay related information like VNI is carried through EVPN extended communities defined here:

>    In order to indicate which type of data-plane encapsulation (i.e.,
>    VXLAN, NVGRE, MPLS, or MPLS in GRE) is to be used, the BGP
>    Encapsulation Extended Community defined in [RFC5512] is included
>    with all EVPN routes (i.e., MAC Advertisement, Ethernet A-D per EVI,
>    Ethernet A-D per ESI, IMET, and Ethernet Segment) advertised by an
>    egress PE.  Five new values have been assigned by IANA to extend the
>    list of encapsulation types defined in [RFC5512]; they are listed in
>    Section 11.

Now the RFC5512 referred to above has been updated with RFC9012:

>    This document defines a BGP path attribute known as the "Tunnel
>    Encapsulation attribute", which can be used with BGP UPDATEs of
>    various Subsequent Address Family Identifiers (SAFIs) to provide
>    information needed to create tunnels and their corresponding
>    encapsulation headers.  It provides encodings for a number of tunnel
>    types, along with procedures for choosing between alternate tunnels
>    and routing packets into tunnels.



 

So EVPN just solved extending layer 2 networks its own? Well no. I mentioned the RFC7432 and RFC8365 earlier.  EVPN is not the "carrier" of the layer 2 networks, EVPN is the control-plane, the single control-plane for multiple network virtualization overlays (VXLAN, MPLS over GRE, Geneve). We also need something that can transport these networks. We need something that creates a tunnel for our layer 2 ethernet frames, to be able to actually transport these layer 2 networks over layer 3. This is can be VXLAN (RFC8365) or MPLS over GRE ([RFC4023](https://datatracker.ietf.org/doc/html/rfc4023)). EVPN may also be referred to as EVPN-VXLAN, EVPN-MPLS or BGP-EVPN. I have already covered VXLAN to some extent in this [post](https://blog.andreasm.io/2024/11/08/overlay-on-overlay-arista-in-the-underlay/#overlay-in-the-underlay). But a quick section on VXLAN will probably make sense. *I will mainly focus on EVPN-VXLAN in this blog series.* 

### VXLAN - the dataplane



Now we understand what EVPN does right? Not quite. 
TL;DR: 
Well it has the ability to segment and isolate tenants (layer 2) effectively using a single control plane, BGP, in a shared layer 3 spine-leaf fabric and VXLAN (or Geneve, NVGRE) as the dataplane creating the tunnels between the involved VTEPS (leafs). This allows for an effective, scalable and controllable way to transport layer 2 over layer 3.





## How is EVPN configured with Arista EOS

To configure EVPN with VXLAN in Arista switches in a spine leaf there is two distinctions that needs to be made. First we have the underlay, that is where all the peer to peer links (routed interfaces) between the spines and leafs are configured. These are the carriers for whatever communication goes between any leaf in the fabric. The second is the overlay, this is where we will have our overlay networks configured, carrying all our layer 2 networks over the layer 3 peer to peer links configured in the underlay. Common for both the underlay and the overlay is BGP, as BGP is configured in both underlay and overlay. This could also be OSPF but why have two different routing protocols when one can just one to handle bot the underlay and overlay for simpler management. For this section I have 2 spines and 4 leafs that I will configure EVPN and VXLAN on. 

![fabric](images/image-20241219133604129.png)



Lets start by configuring the underlay in a fabric consisting of 2 spines and 4 leafs.

### The underlay

In the underlay I need to configure both the ptp links, but also the underlay BGP configuration, starting with the peer to peer links for my BGP in the underlay to have something to peer with. 

#### Peer to Peer links

As I have 6 switches in total, I need to allocate 16 ipv4 addresses for the ptp links. There will be one uplink from every leaf to every spine. To save on IP addresses I will define the submask for these links as small as possible and it should only make room for 2 ip addresses per link (1 for the leaf uplink and 1 for the spine downlink to respective leaf (spine leaf "pair")), and that should be a /31 netmask. It may make sense to reserve a range for all the potential future expansion in the same range for several reasons. As in my example below I will be using 10.255.255.x/31 for each ptp interface, this may again be carved out of a bigger /24 subnet giving me a total of 255 addresses. 255 addresses? 0 and 255 is broadcast isnt it? Arista EOS supports the [RFC3021](https://datatracker.ietf.org/doc/rfc3021/) which states the following:  

>    With ever-increasing pressure to conserve IP address space on the
>    Internet, it makes sense to consider where relatively minor changes
>    can be made to fielded practice to improve numbering efficiency.  One
>    such change, proposed by this document, is to halve the amount of
>    address space assigned to point-to-point links (common throughout the
>    Internet infrastructure) by allowing the use of 31-bit subnet masks
>    in a very limited way.

This means I can perfectly well use .0 as a useable address as long as it is a /31 submask wich gives me exactly two useable addresses, perfect fit for a peer to peer link. 

Each interface on every switch used for these peer to peer links should look like this, from my spine-1:

```bash
interface Ethernet1
   description P2P_LINK_TO_VEOS-DC1-LEAF1A_Ethernet1
   mtu 9214
   no switchport
   ip address 10.255.255.0/31
!
interface Ethernet2
   description P2P_LINK_TO_VEOS-DC1-LEAF1B_Ethernet1
   mtu 9214
   no switchport
   ip address 10.255.255.4/31
!
interface Ethernet3
   description P2P_LINK_TO_VEOS-DC1-LEAF2A_Ethernet1
   mtu 9214
   no switchport
   ip address 10.255.255.8/31
!
interface Ethernet4
   description P2P_LINK_TO_VEOS-DC1-LEAF2B_Ethernet1
   mtu 9214
   no switchport
   ip address 10.255.255.12/31
!
```

*Notice the .0 in Ethernet1?*

The same config is done on my spine 2 using other ip addresses obviously. For the leafs the peer to peer links looks like this:

```bash
interface Ethernet1
   description P2P_LINK_TO_VEOS-DC1-SPINE1_Ethernet1
   mtu 9214
   no switchport
   ip address 10.255.255.1/31
!
interface Ethernet2
   description P2P_LINK_TO_VEOS-DC1-SPINE2_Ethernet1
   mtu 9214
   no switchport
   ip address 10.255.255.3/31
!
```

The same is done on the remaing leafs accordingly. 

Here is the ip table for all the PTP links I am using:

| Type   | Node            | Node Interface | Leaf IP Address  | Peer Type | Peer Node       | Peer Interface | Peer IP Address  |
| ------ | --------------- | -------------- | ---------------- | --------- | --------------- | -------------- | ---------------- |
| l3leaf | veos-dc1-leaf1a | Ethernet1      | 10.255.255.1/31  | spine     | veos-dc1-spine1 | Ethernet1      | 10.255.255.0/31  |
| l3leaf | veos-dc1-leaf1a | Ethernet2      | 10.255.255.3/31  | spine     | veos-dc1-spine2 | Ethernet1      | 10.255.255.2/31  |
| l3leaf | veos-dc1-leaf1b | Ethernet1      | 10.255.255.5/31  | spine     | veos-dc1-spine1 | Ethernet2      | 10.255.255.4/31  |
| l3leaf | veos-dc1-leaf1b | Ethernet2      | 10.255.255.7/31  | spine     | veos-dc1-spine2 | Ethernet2      | 10.255.255.6/31  |
| l3leaf | veos-dc1-leaf2a | Ethernet1      | 10.255.255.9/31  | spine     | veos-dc1-spine1 | Ethernet3      | 10.255.255.8/31  |
| l3leaf | veos-dc1-leaf2a | Ethernet2      | 10.255.255.11/31 | spine     | veos-dc1-spine2 | Ethernet3      | 10.255.255.10/31 |
| l3leaf | veos-dc1-leaf2b | Ethernet1      | 10.255.255.13/31 | spine     | veos-dc1-spine1 | Ethernet4      | 10.255.255.12/31 |
| l3leaf | veos-dc1-leaf2b | Ethernet2      | 10.255.255.15/31 | spine     | veos-dc1-spine2 | Ethernet4      | 10.255.255.14/31 |



#### BGP in the underlay

Next up is the BGP part that is responsible for exchanging routes in the underlay. This BGP configuration is quite straightforward and minimal.  

On the spine my underlay BGP configuration looks like this:

```bash
router bgp 65110
   router-id 10.255.0.1 ## is not defined yet but will be my overlay loopback interface
   no bgp default ipv4-unicast
   maximum-paths 4 ecmp 4
   neighbor IPv4-UNDERLAY-PEERS peer group
   neighbor IPv4-UNDERLAY-PEERS password 7 7x4B4rnJhZB438m9+BrBfQ==
   neighbor IPv4-UNDERLAY-PEERS send-community
   neighbor IPv4-UNDERLAY-PEERS maximum-routes 12000
   neighbor 10.255.255.1 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.1 remote-as 65111
   neighbor 10.255.255.1 description veos-dc1-leaf1a_Ethernet1
   neighbor 10.255.255.5 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.5 remote-as 65112
   neighbor 10.255.255.5 description veos-dc1-leaf1b_Ethernet1
   neighbor 10.255.255.9 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.9 remote-as 65113
   neighbor 10.255.255.9 description veos-dc1-leaf2a_Ethernet1
   neighbor 10.255.255.13 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.13 remote-as 65114
   neighbor 10.255.255.13 description veos-dc1-leaf2b_Ethernet1
   !
   address-family ipv4
      neighbor IPv4-UNDERLAY-PEERS activate
```

And similarly on my leaf1a:

```bash
router bgp 65111
   router-id 10.255.0.3 ## is not defined yet but will be my overlay loopback interface
   no bgp default ipv4-unicast
   maximum-paths 4 ecmp 4
   neighbor IPv4-UNDERLAY-PEERS peer group
   neighbor IPv4-UNDERLAY-PEERS password 7 7x4B4rnJhZB438m9+BrBfQ==
   neighbor IPv4-UNDERLAY-PEERS send-community
   neighbor IPv4-UNDERLAY-PEERS maximum-routes 12000
   neighbor 10.255.255.0 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.0 remote-as 65110
   neighbor 10.255.255.0 description veos-dc1-spine1_Ethernet1
   neighbor 10.255.255.2 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.2 remote-as 65110
   neighbor 10.255.255.2 description veos-dc1-spine2_Ethernet1
   !
   address-family ipv4
      neighbor IPv4-UNDERLAY-PEERS activate
```

AS table:

| Device  | AS       |
| ------- | -------- |
| Spine 1 | AS 65110 |
| Spine 2 | AS 65110 |
| Leaf1a  | AS 65111 |
| Leaf1b  | AS 65112 |
| Leaf2a  | AS 65113 |
| Leaf2b  | AS 65114 |

When configured in all my switches lets have a look at the BGP status from my spine 1:

```bash
veos-dc1-spine1#show bgp summary
BGP summary information for VRF default
Router identifier 10.255.0.1, local AS number 65110
Neighbor               AS Session State AFI/SAFI                AFI/SAFI State   NLRI Rcd   NLRI Acc
------------- ----------- ------------- ----------------------- -------------- ---------- ----------
10.255.255.1        65111 Established   IPv4 Unicast            Negotiated              2          2
10.255.255.5        65112 Established   IPv4 Unicast            Negotiated              2          2
10.255.255.9        65113 Established   IPv4 Unicast            Negotiated              2          2
10.255.255.13       65114 Established   IPv4 Unicast            Negotiated              2          2
```

Thats it for the underlay configurations. Next up is the overlay parts.

### The overlay

Now the more interesting parts is up, BGP in the overlay, loopback interfaces and VXLAN configurations. 

#### BGP in the overlay

Configuring BGP in the overlay will just build on top of already existing BGP config, I do not need to create any additional BGP router AS'es. Its all about adding the necessary overlay config to support EVPN.

On my spine 1 I have added these configurations, in addition to the already configured BGP settings:

```bash
!
interface Loopback0
   description EVPN_Overlay_Peering
   ip address 10.255.0.1/32
!
ip prefix-list PL-LOOPBACKS-EVPN-OVERLAY
   seq 10 permit 10.255.0.0/27 eq 32
!
route-map RM-CONN-2-BGP permit 10
   match ip address prefix-list PL-LOOPBACKS-EVPN-OVERLAY
!
router bgp 65110
   neighbor EVPN-OVERLAY-PEERS peer group
   neighbor EVPN-OVERLAY-PEERS next-hop-unchanged
   neighbor EVPN-OVERLAY-PEERS update-source Loopback0
   neighbor EVPN-OVERLAY-PEERS bfd
   neighbor EVPN-OVERLAY-PEERS ebgp-multihop 3
   neighbor EVPN-OVERLAY-PEERS password 7 Q4fqtbqcZ7oQuKfuWtNGRQ==
   neighbor EVPN-OVERLAY-PEERS send-community
   neighbor EVPN-OVERLAY-PEERS maximum-routes 0
   neighbor 10.255.0.3 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.3 remote-as 65111
   neighbor 10.255.0.3 description veos-dc1-leaf1a
   neighbor 10.255.0.4 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.4 remote-as 65112
   neighbor 10.255.0.4 description veos-dc1-leaf1b
   neighbor 10.255.0.5 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.5 remote-as 65113
   neighbor 10.255.0.5 description veos-dc1-leaf2a
   neighbor 10.255.0.6 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.6 remote-as 65114
   neighbor 10.255.0.6 description veos-dc1-leaf2b
   redistribute connected route-map RM-CONN-2-BGP
   !
   address-family evpn
      neighbor EVPN-OVERLAY-PEERS activate
   !
   address-family ipv4
      no neighbor EVPN-OVERLAY-PEERS activate
!
```

A short explanation of what is added:

The added Loopback0 interface is used for overlay peering as we will see a bit later in the BGP summary and routes. Then the IP prefix is created and mapped to the route map telling BGP only redistribute the overlay loopback interfaces subnet. There is no need to redistribute the underlay peer to peer links as they are directly connected. Then all the *EVPN-OVERLAY-PEERS* are added to BGP using their respective Loopback interfaces and AS numbers accordingly. Then the EVPN address family is added and the EVPN-OVERLAY-PEERS group is added. The same group is negated under the address family ipv4. 

The complete BGP related config on spine 1 looks like this now:

```bash
interface Loopback0
   description EVPN_Overlay_Peering
   ip address 10.255.0.1/32
!
ip prefix-list PL-LOOPBACKS-EVPN-OVERLAY
   seq 10 permit 10.255.0.0/27 eq 32
!
route-map RM-CONN-2-BGP permit 10
   match ip address prefix-list PL-LOOPBACKS-EVPN-OVERLAY
!
router bgp 65110
   router-id 10.255.0.1
   no bgp default ipv4-unicast
   maximum-paths 4 ecmp 4
   neighbor EVPN-OVERLAY-PEERS peer group
   neighbor EVPN-OVERLAY-PEERS next-hop-unchanged
   neighbor EVPN-OVERLAY-PEERS update-source Loopback0
   neighbor EVPN-OVERLAY-PEERS bfd
   neighbor EVPN-OVERLAY-PEERS ebgp-multihop 3
   neighbor EVPN-OVERLAY-PEERS password 7 Q4fqtbqcZ7oQuKfuWtNGRQ==
   neighbor EVPN-OVERLAY-PEERS send-community
   neighbor EVPN-OVERLAY-PEERS maximum-routes 0
   neighbor IPv4-UNDERLAY-PEERS peer group
   neighbor IPv4-UNDERLAY-PEERS password 7 7x4B4rnJhZB438m9+BrBfQ==
   neighbor IPv4-UNDERLAY-PEERS send-community
   neighbor IPv4-UNDERLAY-PEERS maximum-routes 12000
   neighbor 10.255.0.3 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.3 remote-as 65111
   neighbor 10.255.0.3 description veos-dc1-leaf1a
   neighbor 10.255.0.4 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.4 remote-as 65112
   neighbor 10.255.0.4 description veos-dc1-leaf1b
   neighbor 10.255.0.5 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.5 remote-as 65113
   neighbor 10.255.0.5 description veos-dc1-leaf2a
   neighbor 10.255.0.6 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.6 remote-as 65114
   neighbor 10.255.0.6 description veos-dc1-leaf2b
   neighbor 10.255.255.1 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.1 remote-as 65111
   neighbor 10.255.255.1 description veos-dc1-leaf1a_Ethernet1
   neighbor 10.255.255.5 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.5 remote-as 65112
   neighbor 10.255.255.5 description veos-dc1-leaf1b_Ethernet1
   neighbor 10.255.255.9 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.9 remote-as 65113
   neighbor 10.255.255.9 description veos-dc1-leaf2a_Ethernet1
   neighbor 10.255.255.13 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.13 remote-as 65114
   neighbor 10.255.255.13 description veos-dc1-leaf2b_Ethernet1
   redistribute connected route-map RM-CONN-2-BGP
   !
   address-family evpn
      neighbor EVPN-OVERLAY-PEERS activate
   !
   address-family ipv4
      no neighbor EVPN-OVERLAY-PEERS activate
      neighbor IPv4-UNDERLAY-PEERS activate
```



Similarly on my leaf1a the additional BGP config:

```bash
interface Loopback0
   description EVPN_Overlay_Peering
   ip address 10.255.0.3/32
!
ip prefix-list PL-LOOPBACKS-EVPN-OVERLAY
   seq 10 permit 10.255.0.0/27 eq 32
   seq 20 permit 10.255.1.0/27 eq 32
!
route-map RM-CONN-2-BGP permit 10
   match ip address prefix-list PL-LOOPBACKS-EVPN-OVERLAY
!
router bgp 65111
   neighbor EVPN-OVERLAY-PEERS peer group
   neighbor EVPN-OVERLAY-PEERS update-source Loopback0
   neighbor EVPN-OVERLAY-PEERS bfd
   neighbor EVPN-OVERLAY-PEERS ebgp-multihop 3
   neighbor EVPN-OVERLAY-PEERS password 7 Q4fqtbqcZ7oQuKfuWtNGRQ==
   neighbor EVPN-OVERLAY-PEERS send-community
   neighbor EVPN-OVERLAY-PEERS maximum-routes 0
   neighbor 10.255.0.1 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.1 remote-as 65110
   neighbor 10.255.0.1 description veos-dc1-spine1
   neighbor 10.255.0.2 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.2 remote-as 65110
   neighbor 10.255.0.2 description veos-dc1-spine2
   redistribute connected route-map RM-CONN-2-BGP
   !
   address-family evpn
      neighbor EVPN-OVERLAY-PEERS activate
   !
   address-family ipv4
      no neighbor EVPN-OVERLAY-PEERS activate
      neighbor IPv4-UNDERLAY-PEERS activate
```

Then the full BGP related config on my leaf1a:

```bash
interface Loopback0
   description EVPN_Overlay_Peering
   ip address 10.255.0.3/32
!
ip prefix-list PL-LOOPBACKS-EVPN-OVERLAY
   seq 10 permit 10.255.0.0/27 eq 32
   seq 20 permit 10.255.1.0/27 eq 32
!
route-map RM-CONN-2-BGP permit 10
   match ip address prefix-list PL-LOOPBACKS-EVPN-OVERLAY
!
router bgp 65111
   router-id 10.255.0.3
   no bgp default ipv4-unicast
   maximum-paths 4 ecmp 4
   neighbor EVPN-OVERLAY-PEERS peer group
   neighbor EVPN-OVERLAY-PEERS update-source Loopback0
   neighbor EVPN-OVERLAY-PEERS bfd
   neighbor EVPN-OVERLAY-PEERS ebgp-multihop 3
   neighbor EVPN-OVERLAY-PEERS password 7 Q4fqtbqcZ7oQuKfuWtNGRQ==
   neighbor EVPN-OVERLAY-PEERS send-community
   neighbor EVPN-OVERLAY-PEERS maximum-routes 0
   neighbor IPv4-UNDERLAY-PEERS peer group
   neighbor IPv4-UNDERLAY-PEERS password 7 7x4B4rnJhZB438m9+BrBfQ==
   neighbor IPv4-UNDERLAY-PEERS send-community
   neighbor IPv4-UNDERLAY-PEERS maximum-routes 12000
   neighbor 10.255.0.1 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.1 remote-as 65110
   neighbor 10.255.0.1 description veos-dc1-spine1
   neighbor 10.255.0.2 peer group EVPN-OVERLAY-PEERS
   neighbor 10.255.0.2 remote-as 65110
   neighbor 10.255.0.2 description veos-dc1-spine2
   neighbor 10.255.255.0 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.0 remote-as 65110
   neighbor 10.255.255.0 description veos-dc1-spine1_Ethernet1
   neighbor 10.255.255.2 peer group IPv4-UNDERLAY-PEERS
   neighbor 10.255.255.2 remote-as 65110
   neighbor 10.255.255.2 description veos-dc1-spine2_Ethernet1
   redistribute connected route-map RM-CONN-2-BGP
   !
   address-family evpn
      neighbor EVPN-OVERLAY-PEERS activate
   !
   address-family ipv4
      no neighbor EVPN-OVERLAY-PEERS activate
      neighbor IPv4-UNDERLAY-PEERS activate
```

The BGP EVPN loopback0 interfaces on all my devices for context and reference:

```bash
### Loopback Interfaces (BGP EVPN Peering)

| Loopback Pool | Available Addresses | Assigned addresses | Assigned Address % |
| ------------- | ------------------- | ------------------ | ------------------ |
| 10.255.0.0/27 | 32 | 6 | 18.75 % |

### Loopback0 Interfaces Node Allocation

| POD | Node | Loopback0 |
| --- | ---- | --------- |
| VEOS_FABRIC | veos-dc1-leaf1a | 10.255.0.3/32 |
| VEOS_FABRIC | veos-dc1-leaf1b | 10.255.0.4/32 |
| VEOS_FABRIC | veos-dc1-leaf2a | 10.255.0.5/32 |
| VEOS_FABRIC | veos-dc1-leaf2b | 10.255.0.6/32 |
| VEOS_FABRIC | veos-dc1-spine1 | 10.255.0.1/32 |
| VEOS_FABRIC | veos-dc1-spine2 | 10.255.0.2/32 |
```

When showing ip bgp summary on spine 1 after all switches are configured:

```bash
veos-dc1-spine1#show ip bgp summary
BGP summary information for VRF default
Router identifier 10.255.0.1, local AS number 65110
Neighbor Status Codes: m - Under maintenance
  Description              Neighbor      V AS           MsgRcvd   MsgSent  InQ OutQ  Up/Down State   PfxRcd PfxAcc
  veos-dc1-leaf1a_Ethernet 10.255.255.1  4 65111          45087     45068    0    0   26d15h Estab   2      2
  veos-dc1-leaf1b_Ethernet 10.255.255.5  4 65112          45139     45097    0    0   16d23h Estab   2      2
  veos-dc1-leaf2a_Ethernet 10.255.255.9  4 65113          45046     45081    0    0   26d15h Estab   2      2
  veos-dc1-leaf2b_Ethernet 10.255.255.13 4 65114          45096     45138    0    0   26d14h Estab   2      2
```

And on leaf1a:

```bash
veos-dc1-leaf1a#show ip bgp summary
BGP summary information for VRF default
Router identifier 10.255.0.3, local AS number 65111
Neighbor Status Codes: m - Under maintenance
  Description              Neighbor     V AS           MsgRcvd   MsgSent  InQ OutQ  Up/Down State   PfxRcd PfxAcc
  veos-dc1-spine1_Ethernet 10.255.255.0 4 65110          45056     45078    0    0   26d15h Estab   7      7
  veos-dc1-spine2_Ethernet 10.255.255.2 4 65110          45056     45080    0    0   26d15h Estab   7      7
```



Now the BGP is configured in both the underlay and the overlay and the EVPN address family is activated. Next up is VXLAN and some networks in the overlay.

#### VXLAN configurations

Now it is time to configure the dataplane, where my layer 2 networks reside. For that I need to configure VXLAN. 





Loopback, ID host id, host address.  



Who does what etc.. EVPN routes in leaf, spine etc.. BGP in the leaf, BGP in the spine. What is the BGP version in the spine vs the leaf MP-BGP vs BGP, do the spine need to have MP-BGP? See this: 

>    This document defines extensions to BGP-4 to enable it to carry
>    routing information for multiple Network Layer protocols (e.g., IPv6,
>    IPX, L3VPN, etc.).  The extensions are backward compatible - a router
>    that supports the extensions can interoperate with a router that
>    doesn't support the extensions.
>
> The only three pieces of information carried by BGP-4 [BGP-4] that
>    are IPv4 specific are (a) the NEXT_HOP attribute (expressed as an
>    IPv4 address), (b) AGGREGATOR (contains an IPv4 address), and (c)
>    NLRI (expressed as IPv4 address prefixes).  This document assumes
>    that any BGP speaker (including the one that supports multiprotocol
>    capabilities defined in this document) has to have an IPv4 address
>    (which will be used, among other things, in the AGGREGATOR
>    attribute).  Therefore, to enable BGP-4 to support routing for
>    multiple Network Layer protocols, the only two things that have to be
>    added to BGP-4 are (a) the ability to associate a particular Network
>    Layer protocol with the next hop information, and (b) the ability to
>    associate a particular Network Layer protocol with NLRI.  To identify
>    individual Network Layer protocols associated with the next hop
>    information and semantics of NLRI, this document uses a combination
>    of Address Family, as defined in [IANA-AF], and Subsequent Address
>    Family (as described in this document).
>
>    One could further observe that the next hop information (the
>    information provided by the NEXT_HOP attribute) is meaningful (and
>    necessary) only in conjunction with the advertisements of reachable
>    destinations - in conjunction with the advertisements of unreachable
>    destinations (withdrawing routes from service), the next hop
>    information is meaningless.  This suggests that the advertisement of
>    reachable destinations should be grouped with the advertisement of
>    the next hop to be used for these destinations, and that the
>    advertisement of reachable destinations should be segregated from the
>    advertisement of unreachable destinations.
>
>    To provide backward compatibility, as well as to simplify
>    introduction of the multiprotocol capabilities into BGP-4, this
>    document uses two new attributes, Multiprotocol Reachable NLRI
>    (MP_REACH_NLRI) and Multiprotocol Unreachable NLRI (MP_UNREACH_NLRI).
>    The first one (MP_REACH_NLRI) is used to carry the set of reachable
>    destinations together with the next hop information to be used for
>    forwarding to these destinations.  The second one (MP_UNREACH_NLRI)
>    is used to carry the set of unreachable destinations.  Both of these
>    attributes are optional and non-transitive.  This way, a BGP speaker
>    that doesn't support the multiprotocol capabilities will just ignore
>    the information carried in these attributes and will not pass it to
>    other BGP speakers.



## Sources

- IETF RFC7209 https://datatracker.ietf.org/doc/rfc7209/
- IETF RFC7432 https://datatracker.ietf.org/doc/rfc7432/
- IETF RFC8365 https://datatracker.ietf.org/doc/rfc8365/
- IETF RFC9012 https://datatracker.ietf.org/doc/rfc9012/
- IETF RFC4760 https://datatracker.ietf.org/doc/html/rfc4760
- IETF RFC9014 https://datatracker.ietf.org/doc/rfc9014/
- IETF draft-ietf-bess-evpn-geneve-08 https://datatracker.ietf.org/doc/html/draft-ietf-bess-evpn-geneve-08
- IETF RFC2858 https://datatracker.ietf.org/doc/html/rfc2858
- IETF RFC4271 https://datatracker.ietf.org/doc/html/rfc4271
- IETF RFC4023 https://datatracker.ietf.org/doc/html/rfc4023
- IETF RFC7348 https://datatracker.ietf.org/doc/html/rfc7348
- IETF RFC3021 https://datatracker.ietf.org/doc/rfc3021/
- Arista Networks https://www.arista.com/en/um-eos/eos-evpn-overview

