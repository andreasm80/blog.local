---
author: "Andreas M"
title: "EVPN Route Type 5"
date: 2025-08-13T08:17:20+01:00
description: "What is EVPN route type 5"
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

summary: Going into details of EVPN route type 5
comment: false # Disable comment if false.
---



# EVPN Route Type 5 - (IP Prefix)

In my previous post [here](https://blog.andreasm.io/2025/01/23/evpn-route-types-2-and-3/) I wrote about EVPN Route type 2 and 3. I explored and demonstrated how these route types work together to advertise MAC and IP addresses and establish broadcast domains within the EVPN fabric using VXLAN. Route type 2 and 3 are the most common route types and necessary together. Understanding how these two route types work is important for the foundational knowledge in how EVPN provides layer 2 connectivity over an IP network. And as mentioned in this post about chronological order, this post will follow the same pattern as I will be covering route type 5 and not 4. That is because route type 5 will "build" upon route type 2 and 3. 

Think of your EVPN network as building a complete communication system.

- **Route Type 3 (Inclusive Multicast):** This is the first step. It's like building the rooms and defining their boundaries. A VTEP sends a Type 3 route to announce, "I am participating in this broadcast domain (VNI)." This establishes the Layer 2 domain and ensures that broadcast and multicast traffic gets to all the right places.
- **Route Type 2 (MAC/IP Advertisement):** Once the rooms are built, you need to know who is in them. A Type 2 route advertises the specific MAC and IP addresses of the hosts connected to a VTEP. This is how VTEPs learn where individual devices are, enabling basic Layer 2 forwarding within the same broadcast domain.
- **Route Type 5 (IP Prefix):** Now that you have rooms (RT3) with people in them (RT2), you need a way to communicate *between* the rooms. This is where Route Type 5 comes in. It advertises entire IP subnets (prefixes), not just individual hosts. This enables **Layer 3 routing** between different broadcast domains, allowing devices in different VNIs to communicate with each other.

This is why route type 5 will be a natural progression from my previous post on route type 3 and 2. 

To see the different route types in Arista EOS, run the command *show bgp evpn route-type ?*



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



## The anatomy of EVPN Route Type 5







Is EVPN required? Cant I just use RT 3 and 2?



## Egress

EVPN route type 2 is responsible for advertising mac-addresses and associated ip addresses (host routes) between VTEPS.

EVPN route type 3 advertises VTEPS participation in broadcast domains.

Now we know what EVPN route type 2 and 3 does, and why it is the two most common EVPN route types. 

