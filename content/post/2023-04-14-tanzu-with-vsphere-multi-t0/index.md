---
author: "Andreas M"
title: "Tanzu with vSphere and different Tier-0s"
date: 2023-04-14T13:24:41+02:00 
description: "Article description."
draft: false 
toc: true
#featureimage: ""
thumbnail: "/images/logo-vmware-tanzu.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Kubernetes
  - Tanzu
  - Networking
tags:
  - nsx
  - tanzu
  - network 

comment: false # Disable comment if false.
---



# Tanzu with vSphere using NSX with multiple T0s

In this post I will go through how to configure Tanzu with different T0 routers in NSX for separation and network isolation.
The first part will involve spinning up dedicated NSX Tier-0 by utlizing several NSX Edges and NSX Edge Clusters. The second part will involve using NSX VRF. Same needs, two different approaches, and some different configs in NSX. In vSphere with Tanzu with NSX we have the option to override network setting pr vSphere Namespace. That means we can place TKC clusters on different subnets/segments in NSX for ip separation, but we can also override and define separate NSX Tier-0 routers for separation all the way out to the physical infrastructure.  

The end-goal would be something like this (high level):

<img src=images/image-20230414134727247.png style="width:1000px" />

## NSX and Tanzu configurations with different individual Tier-0s

In this post I will assume a working NSX with the "first" T0 alredy peered and configured with BGP to its upstream router and Tanzu environment configured and running and maybe a couple of TKC cluster deployed in the "original" Namespace/Workload Network. In other words a fully functional Tanzu with vSphere environment.
My lab is looking like this "networking wise":

<img src=images/image-20230414150018939.png style="width:600px" />



In my lab I use the following IP addresses for the following components:

- Tanzu Management network: 10.13.10.0/24 - connected to a NSX Overlay segment - manually created by me

- Tanzu Workload network (the initial Workload network): 10.13.96.0/20 (could be much smaller) - will be created automatically as a NSX overlay segment. 

- Ingress: 10.13.200.0/24

- Egress: 10.13.201.0/24 I am doing NAT on this network (important to have in mind for later)

- The first Tier-0 has been configured to use uplinks on vlan 1304 in the following cidr: 10.13.4.0/24 

- The second (new) Tier-0 will be using uplink on vlan 1305 in the follwing cidr: 10.13.5.0/24

  

### Deploy new Edge(s) to support a new Tier-0

As this is my lab, I will not deploy redundant amount of Edges, but will stick with one Edge just to get connectivity up and working. NSX Edge do not support more than 1 SR T0 pr Edge, so we need 1:1 mapping between the SR T0 and Edge. 
The first thing we need to do is to deploy a new Edge vm from the NSX manager. The new edge will be part of my "common" overlay transportzone as I cant deploy any TKC cluster on other vSphere clusters than where my Supervisor cluster has been enabled. For the VLAN transportzones one can reuse the existing Edge vlan transportzone and the same profile so they get their correct TEP VLAN. For the Uplinks it can be same VLAN trunkport (VDS or NSX VLAN segment) if the vlan trunk range includes the VLAN for the new T0 uplink.

So my new edge for this second T0 will be deployed like this:

<img src=images/image-20230414144118736.png style="width:700px" />

<img src=images/image-20230414144300850.png style="width:600px" />



After the Edge has been deployed its time to create a Edge cluster. 
<img src=images/image-20230414144431614.png style="width:600px" />

Now we need to create a new segment for the coming new Tier-0 router. 
<img src=images/image-20230414144707087.png style="width:800px" />

The segment has been configured to use the edge-vlan-transportzone, and with the vlan I will be using to peer with the upstream router. 

Now we can go ahead and create the new Tier-0:

<img src=images/image-20230414152027299.png style="width:800px" />

Give the Tier-0 a name, select your new Edge cluster. Save and go back to edit it.
We need to add a interface: 
<img src=images/image-20230414152204319.png style="width:700px" />

Give the interface a name, IP address and select the segment we create above for the new Tier-0 uplink.
Select the Edge node and Save
Now we have a interface, to test if it is up and running you can ping it from your upstream router. 
Next configure BGP and the BGP peering with your upstream router:

<img src=images/image-20230414152420114.png style="width:700px" />

The last thing we need to do in our newly created Tier-0 is to create a static route that can help us reach the Workload Network on the Supervisor Control Plane nodes. The TKC cluster need this connectivity.
Click on Routing -> Static Routes and add the following route (svc workload network): 

<img src=images/image-20230414152757615.png style="width:700px" />

And the next-hop is defined with the ip of the other (first) Tier-0 interface on the "linknett" between the T0s (not configured yet):

<img src=images/image-20230414152955696.png style="width:700px" />

Add and Save. In my lab I like to create these routes in the T0s themselves instead of in the physical router. It could be done from there also. 





Now on the first Tier-0 we need a second or two interface (depending on the number of edges) and create a static route there also. 
The second interface will need to be in the same segment as the new Tier-0 or a dedicated link-net/segment so the Tier-0s can exchange routes between each other there. I just took the lazy approach and reused the same uplink segment my new T0 is already been configured to use. Then I saved a couple of clicks. 
In the first Tier-0 this is the new interface:

<img src=images/image-20230414153644055.png style="width:700px" />

Name it, ip address in the same range as the uplink for the new Tier-0 and same segment used in the new T0. 
Select the edge(s) that will have this/these new interface(s).
Save.

Next up is the route:
This route (dmz I have called it) should point to the TKC workload network cidr we decide to use. The correct cidr is something we get when we create the vSphere Namespace (it is base on the Subnet prefix you configure) 

<img src=images/image-20230414153901023.png style="width:700px" />

And next-hop (yes you guessed correct) is the uplink interface on the new Tier-0.

<img src=images/image-20230414154020667.png style="width:700px" />



So we should have something like this now:

<img src=images/image-20230414154511864.png style="width:700px" />

As mentioned above, these routes is maybe easier to create after we have create the vSphere Network with the correct network definition. As we can see them being realized in the NSX manager. 


### Create a vSphere Namespace to use our new Tier-0

Head over to vCenter -Workload Management and create a new Namespace:

<img src=images/image-20230414155025700.png style="width:500px" />

<img src=images/image-20230414155222954.png style="width:700px" />

Give the NS a dns compliant name, select the *Override Supervisor network settings*. From the dropdown select our new Tier-0 router.
Uncheck NAT (dont need NAT). Fill in the IP addresses you want to use for the TKC worker nodes, and then the ingress cidr you want. 

Click Create. Wait a couple of second and head over to NSX and check what has been created there.

In the NSX Manager you should now see the following:

Segments

<img src=images/image-20230414155535867.png style="width:800px" />

This network is always created pr vSphere Namespace and is reserved for vSphere Pods/vSphere Services.
A second segment is created which is of our interest:

<img src=images/image-20230414155729832.png style="width:800px" />

This is where our first TKC Nodes in this vSphere Namespace will be placed. And we can now get the correct cidr for our static routes created above. The subnet here is 10.13.51.32727 as NSX is showing is the GW address to be 10.13.51.33/27.

Under LoadBalancing we also got a new object:

<img src=images/image-20230414155956341.png style="width:800px" />

This is our Ingress for the TKC API. 

<img src=images/image-20230414160053703.png style="width:800px" />



Under Tier-1 gateways we have a new Tier-1 gateway:

<img src=images/image-20230414160704104.png style="width:800px" />

(Strangely enough placed in the old Edge cluster). 

Now it is time to deploy your new TKC cluster with the new Tier-0. Its the same procedure as every other TKC cluster. Give it a name and place it in the correct Namespace:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: stc-tkc-cluster-dmz
  namespace: stc-ns-dmz
spec:
  clusterNetwork:
    services:
      cidrBlocks: ["20.30.0.0/16"]
    pods:
      cidrBlocks: ["20.40.0.0/16"]
    serviceDomain: "cluster.local"
  topology:
    class: tanzukubernetescluster
    version: v1.23.8---vmware.2-tkg.2-zshippable
    controlPlane:
      replicas: 1
      metadata:
        annotations:
          run.tanzu.vmware.com/resolve-os-image: os-name=ubuntu
    workers:
      machineDeployments:
        - class: node-pool
          name: node-pool-01
          replicas: 2
          metadata:
            annotations:
              run.tanzu.vmware.com/resolve-os-image: os-name=ubuntu
    variables:
      - name: vmClass
        value: best-effort-small #machineclass, get the available classes by running 'k get virtualmachineclass' in vSphere ns context
      - name: storageClass
        value: vsan-default-storage-policy
```



Then it is just running: 

```bash
kubectl apply -f yaml.file
```

And a couple of minutes later (if all preps have been done correctly) you should have a new TKC cluster using the new T0. 

<img src=images/image-20230414161125662.png style="width:600px" />





## NSX and Tanzu configurations with NSX VRF



## Firewall openings - network diagram

tcpdump 

## Troubleshooting

```bash
curl --interface eth1 https://10.13.52.1:6443
```

 from a Supervisor controlplane vm

 
