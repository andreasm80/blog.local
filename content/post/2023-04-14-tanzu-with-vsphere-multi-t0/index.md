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

To troubleshoot networking scenarios with Tanzu it can sometimes help to SSH into the Supervisor Controlplane VMs and the TKC worker nodes. When I tested out this multi Tier-0 setup I had an issue that only the control plane node of my TKC cluster were being spun up, it never came to deploying the worker nodes. I knew it had to do with connectivity between the Supervisor and TKC.
I used NSX Traceflow to verify that connectivity worked as intended which my traceflow in NSX did show me, but still it did not work. So sometimes it is better to see whats going on from the workloads perspective themselves. 

### SSH Supervisor VM

To log in to the Supervisor VMs we need the root password. This password can be retreived from the vCenter server. SSH into the vCenter server:

```bash
root@vcsa [ /lib/vmware-wcp ]# ./decryptK8Pwd.py
Read key from file

Connected to PSQL

Cluster: domain-c35:dd5825a9-8f62-4823-9347-a9723b6800d5
IP: 172.21.102.81
PWD: PASSWORD-IS-HERE
------------------------------------------------------------

Cluster: domain-c8:dd5825a9-8f62-4823-9347-a9723b6800d5
IP: 10.101.10.21
PWD: PASSWORD-IS-HERE
------------------------------------------------------------
```

Now that we have the root password one can log into the Supervisor VM with SSH and password through the Management Interface (the Workload Interface IP is probably behind NAT so is not reachable OOB):

```bash
andreasm@andreasm:~/from_ubuntu_vm/tkgs/tkgs-stc-cpod$ ssh root@10.101.10.22
The authenticity of host '10.101.10.22 (10.101.10.22)' can't be established.
ED25519 key fingerprint is SHA256:vmeHlDgquXrZTK3yyevmY2QfISW1WNoTC5TZJblw1J4.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

And from in here we can use some basic troubleshooting tools to verify if the different networks can be reached from the Supervisor VM. In the example below I try to verify if it can reach the K8s API VIP for the TKC cluster deployed behind the new Tier-0. I am adding *--interface eth1* as I want to specifically use the Workload Network interface on the SVM. 

```bash
curl --interface eth1 https://10.13.52.1:6443
```

 The respons should be immediate, if not you have network reachability issues:

```bash
curl: (28) Failed to connect to 10.13.52.1 port 6443 after 131108 ms: Couldn't connect to server
```

What you should see is this:

```bash
root@423470e48788edd2cd24398f794c5f7b [ ~ ]# curl --interface eth1 https://10.13.52.1:6443
curl: (60) SSL certificate problem: unable to get local issuer certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
```

 

### SSH TKC nodes

The nodes in a TKC cluster can also be SSH'ed into. If you dont do NAT on your vSphere Namespace network they can be reach directly on their IPs (if from where your SSH jumpbox is allowed routing wise/firewall wise). But if you are NAT'ing then you have to place your SSH jumpbox in the same segment as the TKC nodes you want to SSH into. Or add a second interface on your jumpbox placed in this network. The segment is created in NSX and is called something like this:

<img src=images/image-20230415093000226.png style="width:800px" />

To get the password for the TKC nodes you can get them with kubectl like this:
Put yourselves in the context of the namespace where your workload nodes is deployed:

```bash
andreasm@andreasm:~$ vsphere-kubectl login --server=10.101.11.2 --insecure-skip-tls-verify --vsphere-username=andreasm@cpod-nsxam-wdc.az-wdc.cloud-garage.net --tanzu-kubernetes-cluster-namespace ns-wdc-1-nat

```

```bash
andreasm@andreasm:~$ k config current-context
tkc-cluster-nat
```

Then get the SSH secret:

```bash
andreasm@andreasm:~$ k get secrets
NAME                                                   TYPE                                  DATA   AGE
default-token-fqvbp                                    kubernetes.io/service-account-token   3      127d
tkc-cluster-1-antrea-data-values                       Opaque                                1      127d
tkc-cluster-1-auth-svc-cert                            kubernetes.io/tls                     3      127d
tkc-cluster-1-ca                                       cluster.x-k8s.io/secret               2      127d
tkc-cluster-1-capabilities-package                     clusterbootstrap-secret               1      127d
tkc-cluster-1-encryption                               Opaque                                1      127d
tkc-cluster-1-etcd                                     cluster.x-k8s.io/secret               2      127d
tkc-cluster-1-extensions-ca                            kubernetes.io/tls                     3      127d
tkc-cluster-1-guest-cluster-auth-service-data-values   Opaque                                1      127d
tkc-cluster-1-kapp-controller-data-values              Opaque                                2      127d
tkc-cluster-1-kubeconfig                               cluster.x-k8s.io/secret               1      127d
tkc-cluster-1-metrics-server-package                   clusterbootstrap-secret               0      127d
tkc-cluster-1-node-pool-01-bootstrap-j2r7s-fgmm2       cluster.x-k8s.io/secret               2      42h
tkc-cluster-1-node-pool-01-bootstrap-j2r7s-r5lcm       cluster.x-k8s.io/secret               2      42h
tkc-cluster-1-node-pool-01-bootstrap-j2r7s-w96ft       cluster.x-k8s.io/secret               2      42h
tkc-cluster-1-pinniped-package                         clusterbootstrap-secret               1      127d
tkc-cluster-1-proxy                                    cluster.x-k8s.io/secret               2      127d
tkc-cluster-1-sa                                       cluster.x-k8s.io/secret               2      127d
tkc-cluster-1-secretgen-controller-package             clusterbootstrap-secret               0      127d
tkc-cluster-1-ssh                                      kubernetes.io/ssh-auth                1      127d
tkc-cluster-1-ssh-password                             Opaque                                1      127d
tkc-cluster-1-ssh-password-hashed                      Opaque                                1      127d
```

I am interested in this one:

```bash
tkc-cluster-1-ssh-password
```

 So I will go ahead and retrieve the content of it:

```bash
andreasm@andreasm:~$ k get secrets tkc-cluster-1-ssh-password -oyaml
apiVersion: v1
data:
  ssh-passwordkey: aSx--redacted---KJS=    #Here is the ssh password in base64
kind: Secret
metadata:
  creationTimestamp: "2022-12-08T10:52:28Z"
  name: tkc-cluster-1-ssh-password
  namespace: stc-tkc-ns-1
  ownerReferences:
  - apiVersion: cluster.x-k8s.io/v1beta1
    kind: Cluster
    name: tkc-cluster-1
    uid: 4a9c6137-0223-46d8-96d2-ab3564e375fc
  resourceVersion: "499590"
  uid: 75b163a3-4e62-4b33-93de-ae46ee314751
type: Opaque
```

Now I just need to decode the base64 encoded pasword:

```bash
andreasm@andreasm:~$ echo 'aSx--redacted---KJS=' |base64 --decode
passwordinplaintexthere=andreasm@andreasm:~$
```

Now we can use this password to log in to the TKC nodes with the user: vmware-system-user

```bash
ssh vmware-system-user@10.101.51.34
```

