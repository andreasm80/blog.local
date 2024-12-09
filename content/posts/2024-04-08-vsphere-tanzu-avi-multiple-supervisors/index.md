---
author: "Andreas M"
title: "vSphere with Tanzu - Avi and Multiple Supervisors"
date: 2024-04-08T14:56:56+02:00 
description: "1 NSX manager cluster, multiple Supervisor clusters, 1 Avi controller cluster"
draft: false 
toc: true
#featureimage: ""
#thumbnail: "/images/logo-vmware-tanzu.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Kubernetes
  - Tanzu
  - NSX
  - AVI
tags:
  - kubernetes
  - loadbalancing
  - networking
  - avi
  - nsx
  - multi-tenancy

summary: In this post I will try to describe how to use the new NSX and Avi together integration in vSphere with Tanzu in combination with several Supervisor clusters using only 1 NSX manager cluster and 1 Avi controller cluster
comment: false # Disable comment if false.
---



# Introduction:

Since vSphere 8 U2 it is possible to combine NSX and Avi as the networking and loadbalancing stack for vSphere with Tanzu. For more information on how to configure that head over to [this post](https://blog.andreasm.io/2023/09/23/vsphere-with-tanzu-8-u2-using-nsx-and-nsx-advanced-loadbalancer/). In that post I also go through how this new integration works. But I only use one vSphere with Tanzu deployment in that post, meaning only a single Supervisor cluster is deployed. I have been contacted several times recently regarding how this new integration functions when planning to deploy multiple Supervisors (more than one vSphere cluster where vSphere with Tanzu is enabled on), while using the same NSX manager and Avi controller for all Supervisor clusters.    

Some context to these requests and before I dive into the actual configurations and deployment:

The plan is to have vSphere with Tanzu enabled on two or more vSphere clusters, but I dont want them to share any Avi Service Engines or NSX Edge clusters. The only thing they have in common is that they are being managed by the same vCenter Server, NSX manager and Avi controller. The keyword is as much separation on compute and network as possible where sharing some common management instances like NSX manager cluster, vCenter Server and Avi controller cluster.

In this post I will go through how to accomplish this, including some explanations how the components involved makes the decision which NSX cloud in Avi to use for the respective Supervisor Cluster. 
My lab consist of the following:

- 1x NSX manager cluster, managing both my vSphere clusters
- 1x vCenter Server, managing both my vSphere clusters
- 2x vSphere clusters, Supervisor installed on both of them 
- 1x Avi controller cluster



*To make this post a bit shorter I am skipping all the necessary requirements/preparation/installation of NSX and Avi and will just refer to my previous posts how to do that:*

[vSphere with Tanzu - NSX and Avi](https://blog.andreasm.io/2023/09/23/vsphere-with-tanzu-8-u2-using-nsx-and-nsx-advanced-loadbalancer/) 

[NSX and vSphere with Tanzu](https://blog.andreasm.io/2022/10/26/vsphere-8-with-tanzu-using-nsx-t-avi-loadbalancer/)



Before jumping in, this is a diagram of what I want to end up with:

![end-goal](images/image-20240408154123643.png)



So lets dig in to it and see how that goes.

## Preparations in NSX

In NSX the important part is to configure each vSphere cluster that will have their own instance of vSphere with Tanzu with their own unique NSX Overlay Transport Zone. This is a requirement for Avi to create dedicated Service Engine groups which will ultimately serve my two vSphere with Tanzu instances.

> **Transport Zone**: Collection of transport nodes that defines the maximum span for logical switches. A transport zone represents a set of similarly provisioned hypervisors and the logical switches that connect VMs on those hypervisors. It also has been registered with the NSX management plane and has NSX modules installed. For a hypervisor host or NSX Edge to be part of the NSX overlay, it must be added to the NSX transport zone.

So in my lab I have two vSphere clusters, both configured with NSX, but using two different NSX Overlay Transport Zones. It does not matter if they are utilizing the same TEP VLAN (*defined in your host uplink profile), but the logical boundary, as an Overlay Transport Zone is, is limited to only involve the clusters isolated.

> (*) **Tunnel Endpoint (TEP) Profile**: Each transport node has a Tunnel Endpoint (TEP) responsible for encapsulating the overlay VM traffic inside a VLAN header and routing the packet to a destination TEP for further processing. TEPs are the source and destination IP addresses used in the external IP header to identify the ESXi hosts that originate and end the NSX encapsulation of overlay frames. Traffic can be routed to another TEP on a different host or the NSX Edge gateway to access the physical network. TEPs create a GENEVE tunnel between the source and destination endpoints.

 Like this:

![two-overlay-transportzones](images/image-20240409140425099.png)



In my NSX Environment I have it configured like this.

![two-vsphere-clusters](images/image-20240409140555403.png)

Using two different Transport Node Profiles:



![tn-profile](images/image-20240409140633109.png)

![tn-profile-2](images/image-20240409140708087.png)

> **Transport Node Profile**: This specifies the common transport parameters for network virtualization components in an NSX environment. It includes configurations for both the overlay and underlay network settings, such as N-VDS (NSX Virtual Distributed Switch) settings, teaming policies, and uplink profiles. Transport profiles are used to streamline the deployment and management of transport nodes by applying a consistent set of networking settings, enhancing the network's efficiency and reliability.



Where in the respective Transport Node Profiles two different Overlay Transport Zones have been defined:



Cluster-1:

![tn-profile-cluster-1](images/image-20240409140821309.png)

Cluster-2:

![tn-profile-cluster-2](images/image-20240409140851985.png)

### NSX Edge Clusters

For many customers they have reasons to separate not only the compute part (different vSphere clusters for different departments, environments and customers (tenancy)) but also network separation. So I decided to deploy a dedicated Edge cluster per vSphere compute cluster. So I am in full control of the traffic coming in and out of my different vSphere clusters, not only logical but also physical. What I end up with is one Tier-0 router per vSphere cluster/Supervisor cluster. 

*vSphere with Tanzu supports multiple Tier-0 routers even in the same Supervisor cluster see this [post](https://blog.andreasm.io/2023/04/14/tanzu-with-vsphere-and-different-tier-0s/) how to configure vSphere with Tanzu using different Tier-0 routers.*

So here is my network topology in NSX:

![topology](images/image-20240409143947921.png)

In the picture above, I have my "Cluster-1" on the left where the Tier-0 **sfo-m01-ec01-to-gw01** is managing ingress and egress for my NSX overlay networks and on the right the Tier-0 ""**workload-tier-0**"" managing ingress and egress for my "Cluster-2". 

Thats it for the NSX preparations. Next up is the Avi preparations.



## AVI preparations

In Avi, I need to configure two NSX clouds using the same NSX manager cluster, but for Avi it will be considered as two different clouds. **The reason for that is because the Supervisor installation is using the NSX Overlay Transport Zone as an identifier** for which NSX cloud to use when it sends requests to Avi to create a Virtual Service to provide my K8s api endpoints. 

### AVI Clouds

In my Avi controller I have configured my two NSX clouds, using the same NSX manager, but as two different clouds in Avi.

![two-nsx-clouds](images/image-20240409145526586.png)

If we take a quick peek inside both of them, starting with the *nsx-m01* cloud, we will find some common values and some unique. 

**nsx-m01**

![nsx-m01](images/image-20240409150200997.png)

![nsx-m01-cont'd](images/image-20240409150835807.png)



The fields in red are common settings between the two clouds. The other values are unique. notice the different Transport Zones which should match the Transport Zone for each respective cluster. Under DNS Profile one could also define a custom DNS profile of course, I just went with the same DNS profile in my lab. It would make sense to have two different DNS profiles also to keep the red line of separation complete.

**nsx-m01-2**

![nsx-m01-2](images/image-20240409150613519.png)

![nsx-m01-2-cont'd](images/image-20240409150733963.png)

### Avi Cloud Resource - Service Engine Group and Networks

Under Avi Cloud Resources I have defined the Default Service Engine group according to the vSphere Clusters/NSX clouds they belong to. Cloud **nsx-m01** is using cluster **sfo-m01-cl01** so I have configured the Default SE group accordingly so they take SE placement into consideration. Meaning the SEs will be placed in the right vSphere Cluster. This is important as the Default Service Engine Group will be used as a template for vSphere with Tanzu to create the dedicated Service Engine group per cluster.

**Cloud nsx-m01**

![Defalt-Grp-nsx-m01](images/image-20240409151254258.png)

The important factor is under **Scope** here:
![Scope-1](images/image-20240409151536457.png)

![Scope-2](images/image-20240409151609857.png)

Here I have defined the scope for where the SEs should be placed for the Supervisor cluster deployed in my vSphere Cluster **sfo-m01-cl01**.

**Cloud nsx-m01-2**

On my next **nsx-m01-2** cloud I have configured the placement for this vSphere Cluster, which is the vSphere Cluster 

![nsx-m01-2](images/image-20240409151835119.png)

![nsx-m01-2-vcenter](images/image-20240409151910002.png)

Its the same vCenter again, but different vSphere Cluster:

![nsx-m01-2-cluster-scope](images/image-20240409151953799.png)

Under networks I have configured the necessary mgmt network and data network for my SEs accordingly. Meaning I have dedicated mgmt network and data network for my SEs in the **nsx-m01** cloud and **nsx-m01-2** cloud. The data network is only if you decide to also share or use the same SEs for other services, like Layer 7 from the TKC clusters. The vSphere with Tanzu installation will create its own data network name something like avi-domain-xxx.

**nsx-m01**

![nsx-m01-network](images/image-20240409152505326.png)

Management network is provided with DHCP, therefore empty in here. And I also have my Avi DNS service configured in this cloud.

**nsx-m01-2**

![nsx-m01-2-network](images/image-20240409152140667.png)

Thats it for the Avi configs. 

## vSphere with Tanzu setup

In my vCenter I have two vSphere clusters, where I have enabled the Workload Management, or the Supervisor using the above config to support my needs. This is how it looks, whith some explanations. 

### vSphere cluster sfo-m01-cl01

![supervisor-cluster-1](images/image-20240409152746287.png)

### vSphere cluster workload-1

![vsphere-cluster-workload-1](images/image-20240409152837285.png)



### Supervisors

![both-supervisors](images/image-20240409152944392.png)



### AVI virtual services for my k8s api endpoints

![vs-1](images/image-20240409153048188.png)

![avi-vs](images/image-20240409153132371.png)

Notice the domain-cXXX ids. They reflect my respective vSphere cluster domain ids. All managed by the same Avi controller. 

They are provisioned with different VIPs, not using the same VIP (or ingress as defined when installing vSphere with Tanzu). Lets have a look at the Service Engines, and inspect the networking for them as well. 



![service-engines](images/image-20240409153431022.png)

As we can see, they are being handled by two different pairs of Service Engines. We see that in vCenter also, see screenshot above.

For my vSphere Cluster **sfo-m01-cl01** 

![service-engine-sfo-m01-cl01](images/image-20240409153956315.png)

And the vSphere Cluster **workload-1**



![sercvice-for-cluster-workload-1](images/image-20240409153816856.png)





### NSX 

In NSX I can see two Distributed loadbalancers being created to serve as a **kube-proxy** replacement for the services internal to the Supervisor cluster itself (the Supervisor Controle Plane and ESXi worker nodes).

![nsx-dlb](images/image-20240409154347098.png)

![vs-inside-dlb-cluster-workload-1](images/image-20240409154419804.png)



![vs-inside-dlb-cluster-m01-cl01](images/image-20240409154444728.png)

**Note**

When I provisioned my second Supervisor Cluster I did not overlap the Services CIDR by using the same range as defined in my first Supervisor Cluster. See screenshot below:

From my **svc-1**

![svc-1](images/image-20240409154651911.png)

From my **svc-2**

![svc-2](images/image-20240409154727991.png)



## Outro

Thats it, it is possible to use 1 NSX manager cluster, 1 vCenter Server and 1 AVI controller cluster to manage multiple Supervisor Clusters, and still maintain a high level of separation, except on the mgmt layer. If that is a requirement, then one have to install these components separately also. But that was not the point of this post.

