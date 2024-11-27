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

summary: Describng typical deployments where we end up with double encapsulation, how to monitor, troubleshoot
comment: false # Disable comment if false.i
---



# Spine/Leaf with EVPN and VXLAN - underlay and overlay

In a typical datacenter today a common architecture is the Spine/Leaf design ([Clos](https://en.wikipedia.org/wiki/Clos_network)). This architecture comes with many benefits such as:

- Performance 
- Scalability 
- Redundancy
- High Availability
- Simplified Network Management
- Supports East-West

***Underlay***

There are two ways to design a spine leaf fabric. We can do layer 2 designs and layer 3 designs. I will be focusing on the layer 3 design in this post as this is the most common design. Layer 3 scales and performs better, we dont need to consider STP and we get Equal Cost Multi Path in the whole fabric. In a layer3 design all switches in the fabric are connected using routed ports, which also means there is no layer 2 possibilities between the switches, unless we introduce some kind of layer on top that can carry this layer 2 over the layer 3 links. This layer is what this post will cover and is often referrred to as the overlay layer. Before going all in on overlay I need to also cover the underlay. The underlay in a spine leaf fabric is the physical ports configured as routed ports connecting the switches together. All switches in a layer 3 fabric is being connected to each other using routed ports. All leaves exchange routes/peers with the spines.

As everything is routed we need to add some routing information in the underlay to let all switches know where to go to reach certain destinations. This can in theory be any kind of routing protocols (even static routes) supported by the [IETF](https://www.ietf.org/) such as OSFP, ISIS and BGP.

In Arista the preferred and recommended routing protocol in both the underlay and overlay is BGP. Why? BGP is the most commonly used routing protocol, it is very robust, feature rich and customisable. It supports EVPN, and if you know you are going to use EVPN why consider a different routing protocol in the underlay? That just adds more complexity and management overhead. Using BGP in both the underlay and the overlay gives a much more consistent config and benefits like BGP does not need multicast. 

So if you read any Arista deployment recommendations, use Arista Validated Design, Arista's protocol of choice will always be BGP. It just makes everything so much easier. 

In a spine leaf fabric, all leaves peers with the spines. The leaves do not peer with the other leaves in the underlay, unless there is an mlag config between to leaf pairs. All leaves have their own BGP AS, the spines usually share the same BGP AS.  

A diagram of the fabric underlay:

![layer-3-ls](images/image-20241127103701406.png)

In the above diagram I have confgured my underlay with layer 3 routing, BGP exhanges route information between the leaves. So far in my configuration I can not have two servers connected to different leaves on the same layer 2 subnet. Only if they are connected to the same leaf I can have layer 2 adjacency. So when server 1, connected to leaf1a, wants to talk to server 2, connected on leaf2a, it has to be over layer 3 and both servers needs to be in their own subnet. Leaf1a and leaf2a advertises its subnets to both spine1 and spine2, server 1 and 2 has been configured to use their connected leaf switches  as gateway respectively. This is fine, I can go home and rest, no one needs to use layer 2. Or... 

Having solved a well performing layer 3 fabric, the routing in the underlay does not help me if I want layer 2 mobility between servers, virtual machines etc connected to different layer 3 leafs. This is where the overlay part comes in to the rescue. And to make it a bit more interesting, I will add several overlay layers into the mix.  

***Overlay***

In a Spine/Leaf architecture **the** most used overlay protocol is [VXLAN](https://datatracker.ietf.org/doc/html/rfc7348) as the transport plane and BGP EVPN as the control plane. Why use overlay in the physical network you say? Well its the best way of moving L2 over L3, and in a "distributed world" as the services in the datacenter today mostly is we need to make sure this can be done in a controlled and effective way in our network. Doing pure L2 will not scale, L3 is the way. EVPN for multi-tenancy.

Adding VXLAN as the overlay protocol in my spine leaf fabric I can stretch my layer 2 networks across all my layer 3 leaves without worries. This means I can now suddenly have multiple servers physical as virtual in the same layer 2 subnet. To make that happen as effectively and with as low admin overhead as possible VXLAN will be the transport plane (overlay protocol) and again BGP will be used as the control plane. This means we now need to configure BGP in the overlay, on top of our BGP in the underlay. BGP EVPN will be used to create isolation and multi tenancy on top of the underlay. To quickly summarize, VXLAN is the transport protocol responsible of carrying the layer 2 subnets over any layer 3 link in the fabric. BGP and EVPN will be the control plane that always knows where things are located and can effectively inform where the traffic should go. This is stil all in the physical network fabric. As we will see a bit later, we can also introduce network overlay protocols in other parts of the infrastructure. 

![vxlan-l2-over-l3](images/image-20241127110441121.png)

In the diagram above all my leaf switches has become VTEPs, VXLAN Tunnel Endpoints. Meaning they are responsible of taking my ethernet packet coming from server 1, encapsulate it, send it over the layer 3 links in my fabric, to the destination leaf where server 2 is located. The BGP configured in the overlay here is using an EVPN address family to advertise mac addresses. If one have a look at the ethernet frame coming from server 1 and destined to server 2 we will see some differerent mac addresses. Lets quickly illustrate that.

The two switches in the diagram above that will be the best place to look at all packages using wireshark will be the spine 1 and spine 2 as they are connecting everything together and there is no direct communication between any leaf, they have to go through spine 1 and spine 2. 

If I do a ping from server 1 to server 2, how will the ethernet packet look like when captured at spine1s ethernet interface 1 (the one connected to leaf1a)?

Looking at the tcpdump below from *spine 1* I can clearly see some additional information added to the packet. First I see two mac addresses where source `bc:24:11:1d:5f:a1` is my *leaf1a*  a the destination mac address, `bc:24:11:4a:9a:d0` is my *spine1* switch. The first two ip addresses `10.255.1.3` and `10.255.1.4` is *leaf1a* and *leaf1b* VXLAN loopback interfaces respectively with the corresponding mac addresses `bc:24:11:1d:5f:a1`and `bc:24:11:9b:8f:08`. Then I get to the actual payload itself, the ICMP, between my *server 1* and *server 2* where I can see the source and destination ip of the actual servers doing the ping. 

```yaml
15:44:33.125961 bc:24:11:1d:5f:a1 > bc:24:11:4a:9a:d0, ethertype IPv4 (0x0800), length 148: (tos 0x0, ttl 64, id 0, offset 0, flags [DF], proto UDP (17), length 134)
    10.255.1.3.53892 > 10.255.1.4.4789: VXLAN, flags [I] (0x08), vni 10
bc:24:11:1d:5f:a1 > bc:24:11:9b:8f:08, ethertype IPv4 (0x0800), length 98: (tos 0x0, ttl 63, id 6669, offset 0, flags [DF], proto ICMP (1), length 84)
    10.20.11.10 > 10.20.12.10: ICMP echo request, id 10, seq 108, length 64
```

 How does this all happen? The ICMP request comes in from *server 1* to *leaf1a* and leaf1a already knows where to send it, but before it can it have to encapsulate the packet adding both removing and adding som information to the packet. As seen above it is adding an outer header including the source and destination VTEP mac addresses. More info on that further down.

Even though VXLAN is the most common overlay protocol, there are other overlay protocols being used in the datacenter too, like [Geneve](https://datatracker.ietf.org/doc/html/rfc8926), and even NVGre and STT. This blog will discuss some typical scenarios where we deal with "layers" of overlay protocols.

Yes, the services connecting to my network also happen to use some kind of overlay protocol, can I have encapsulation on top of encapsulation? Yes, why not? In some environments we may even end up with overlay on top of overlay on top of another overlay (three "layers" of overlay). That's not possible, you are pulling a joke here right? No I am not, yes that is fully possible and occurs very frequent. But I will loose all visibility!? Why? Using VXLAN or Geneve does not mean the traffic is being encrypted. 

In such scenarios though, like the movie Inception, it will be important to know how things fits together, where to monitor, how to monitor, what to think of making sure there is nothing in the way of the tunnels to be established. This is something I will try to go through in this post. How these thing fits together.  

One example of running overlay on top of overlay is in environments where VMware (by Broadcom) NSX is involved. VMware NSX is using Geneve[^1] to encapsulate their Layer2 NSX Segments over any fabric between their VTEPS (usually the ESXi host transport nodes, the NSX Edges is also considered TEPS in an NSX environment). If this is connected to a spine/leaf fabric we will have VXLAN and Geneve overlay protocols moving L2 segments between VTEPS. 



Below we have a spine leaf fabric using VXLAN and NSX in the compute layer using Geneve. All network segments created in NSX leaving and entering a ESXi host will be encapsulated using Geneve, and that also means all services ingressing the leafs from these ESXi hosts will get another round of encapsulation using VXLAN. I will describe this a bit better later, below is a very high level illustration.

![nsx-teps-arista-vteps](images/image-20241108111853681.png)

But what if we are also running Kubernetes in our VMware NSX environment, which also happens to use some kind of overlay protocol (common CNIs supports VXLAN/Geneve/NVGre/STT) between the control and worker nodes. That will be hard to do right? Should we disable encapsulation in our Kubernetes clusters then? No, well it depends of course, but if you dont have any specific requirements (like no-snat) to NOT use overlay between your Kubernetes nodes then it makes your Kubernetes network connectivity (like pod to pod across nodes) so much easier. 

How will this look like then?

![kubernetes-overlay](images/image-20241108122625081.png)

Doesn't look that bad? Now if I were Leonardo DiCaprio in Inception it would be a walk in the park. 

## Where is encapsulation and decapsulation done

It is important to know where the ethernet frames are being encapsulated and decapsulated so one can understand where things may go wrong. Lets start with the Spine/Leaf fabric. 

When traffic or the network services enters or ingresses on any of the leafs in the fabric its the leafs role to encapsulate and decapsulate the traffic. The leafs in a VXLAN spine/leaf fabric are considered our VTEP's (VXLAN Tunnel Endpoints). I have two servers connected to two different leafs, and also happens to be on two different VNIs (VXLAN Network Identifier), where server A needs to send a packet to server B the receiving leaf will encapsulate the ingress, then send it via any of the spines to the leaf where server B is connected and this leaf will then decapsulate the packet before its delivered to server B. See below:

![spine/leaf/encap-decap](images/image-20241110201118681.png)

How will this look if I add NSX into the mix? The below traffic flow will only be true if source and destination is not leaving the NSX "fabric", meaning it is traffic between two vms in same NSX segment or two different segments. If traffic is destined to go outside the NSX fabric it will need to leave via the NSX edges which will "normalise" the traffic and decapsulate the traffic to regular MTU size 1500 if not adjusted in the Edge uplinks to use bigger mtu size than default 1500. 

![nsx-over-vxlan](images/image-20241110202627504.png)

What about Kubernetes as an additional layer?

![kubernetes-encapsulation](images/image-20241110203609485.png)

## What about MTU - kind of important then?

A default ethernet frame size is 1500MTU (Maximum Transmission Unit). When encapsulating a standard ethernet frame using VXLAN some headers are remove from the original frame, and additional headers are being added. See illustration:

![std-eth-frame](images/image-20241109101619428.png)

VXLAN encapsulated ethernet frame:

![vxlan-encapsulation](images/image-20241109102047130.png)

![headers-stripped-and-added](images/image-20241109102130032.png)



These additional headers requires some more room which makes the default size of 1500mtu too small. So in a very simple setup using VXLAN encapsulation we need to accomodate for this increase in size.  If this is not considered you will end up with nothing working. A new buzzword will then become *its always MTU*.

Why is that? Imagine you have a rather big car and the road you are driving has a tunnel, this tunnel is not big enough to actually fit your car (very seldom, but assume its a monster truck you are driving). If you dont pay attention and just make a run for it, entering the tunnel will come to a hard stop. 

![too-small-tunnel](images/image-20241109103140283.png)

And if something should happen to come out on the other side of the tunnel it will most likely be fragments of the car. Which we dont like. We do like our cars whole, as we like our network packets whole.

If the tunnel is big enough to accommodate the biggest monster truck, then it should be fine.

![fits](images/image-20241109103359204.png)

The monster truck both enters and exits the tunnel safe and sound and in the exact same shape it entered. No pieces torn off or ripped off to fit the tunnel. 

If the tunnel will bearly fit the car, you can bet some pieces would be torn off, like side mirrors etc. This can be translated into dropped packets, which we dont want, I dont think we wont pieces being dropped from the car/monster truck either.   

If the monster truck diagram is not depictive enough, lets try another illustration. Imagine you have two steel pipes of equal diameter and width and you want one pipe to be inserted into the other pipe to maybe extend the total length by combining the two. Pretty hard to do, welding is propably your best option here. But if one pipe had a smaller diameter so it could actually fit inside the other pipe, then it would slide in without any issue. 

![pipe-into-pipe-into-pipe](images/image-20241110194248212.png) 

Imagine the last pipe on the right is the Arista spine/leaf fabric. This should be the part of the infrastructure that must accommodate the biggest allowed MTU size. Then the green pipe will be the NSX environment which needs to tune their MTU setting on the TEP side (host profile) to fit the MTU size sat in the Arista Fabric. Arista is default configured to use 9214 MTU. Then the Kubernetes cluster running in NSX segments also needs to adapt to the MTU size in the NSX environment.

This should be fairly easy to calculate as long as one know which overlay protocol being used, how much the additional headers will impose on the ethernet frame. Se VXLAN above. Be aware that VXLAN has fixed headers so you will always know the exact MTU size, Geneve on the other (call it an VXLAN extension) is using dynamic headers and needs to be taken into consideration. 

Watch your MTU, MTU is your friend if you know it. 

The first thing one need to be aware of and in full control of is the MTU size from top to bottom. If you have that, then running overlay on overlay on overlay should be straight forward. 

What about performance?

There is nothing denying that running only overlay in the Arista fabric would be far the most performant way of doing it. There is nothing denying that if switching is done by the part in your network that has this as its sole role we often refer to terms like line rate speed. This is because network switches are purpose built devices with some very efficient CPU (ASICS) to handle switching and routing. 



What about security? Can this be combined too? Like NSX Distributed Firewall for VM east-west and MSS in the physical fabric?



[^1]: *(Earlier version of VMware NSX called NSX-V used VXLAN too, for a period VMware had two NSX versions NSX-V and NSX-T where the latter used Geneve and is the current NSX product, NSX-V is obsolete and NSX-T now is the only product and is just called NSX.)*

