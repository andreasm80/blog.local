---
author: "Andreas M"
title: "GSLB With AKO & AMKO - NSX Advanced LoadBalancer"
date: 2022-10-23T08:22:35+02:00 
description: "How to configure GSLB with AKO/AMKO"
draft: false 
toc: true
#featureimage: ""
thumbnail: "/images/avi_networks.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Kubernetes
  - Tanzu
  - GSLB
tags:
  - NSX Advanced LoadBalancer
  - AKO
  - AMKO 

comment: false # Disable comment if false.
---



# Global Server LoadBalancing in VMware Tanzu with AMKO 

This post will go through how to configure AVI (NSX ALB) with GSLB in vSphere with Tanzu (TKGs) and an upstream k8s cluster in two different physical locations. I have already covered AKO in my previous posts, this post will assume knowledge of AKO (Avi Kubernetes Operator) and extend upon that with the use of AMKO (Avi Multi-Cluster Kubernetes Operator). The goal is to have the ability to scale my k8s applications between my "sites" and make them geo-redundant. For more information on AVI, AKO and AMKO head over [here](https://avinetworks.com/docs/)

## Preparations and diagram over environment used in this post

This post will involve a upstream Ubuntu k8s cluster in my home-lab and a remote vSphere with Tanzu cluster. I have deployed one Avi Controller in my home lab and one Avi controller in the remote site. The k8s cluster in my home-lab is defined as the "primary" k8s cluster, the same goes for the Avi controller in my home-lab. There are some networking connectivity between the AVI controllers that needs to be in place such as 443 (API) between the controllers, and the AVI SE's needs to reach the GSLB VS vips on their respective side for GSLB health checks. Site A SE's dataplane needs connectivity to the vip that is created for the GSLB service on site B and vice versa. The primary k8s cluster also needs connectivity to the "secondary" k8s clusters endpoint ip/fqdn, k8s api (port 6443). AMKO needs this connectivity to listen for "GSLB" enabled services in the remote k8s clusters which triggers AMKO to automatically put them in your GSLB service. More on that later in the article. When all preparations are done the final diagram should look something like this:

<img src=images/image-20221115113124820.png style="width:1000px" />



 (I will not cover what kind of infrastructure that connects the sites together as that is a completely different topic and can be as much). But there will most likely be a firewall involved between the sites, and the above mentioned connectivity needs to be adjusted in the firewall.
In this post the following ip subnets will be used:

1. SE Dataplane network home-lab: 10.150.1.0/24 (I only have two se's so there will be two addresses from this subnet) (I am running the all services on the same two SE's which is not recommended, one should atleast have dedicated SE's for the AVI DNS service)
2. SE Dataplane network remote-site: 192.168.102.0/24 (Two SE's here also, in remote site I do have dedicated SE's for the AVI DNS Service but they will not be touched upon in this post only the SE's responsible for the GSLB services being created)
3. VIP subnet for services exposed in home-lab k8s cluster: 10.150.12.0/24 (a dedicated vip subnet for all services exposed from this cluster)
4. VIP subnet for services exposed in remote-site tkgs cluster: 192.168.151.0/24 (a dedicated vip subnet for all services exposed from this cluster)

For this network setup to work one needs to have routing in place, either with BGP enabled in AVI or static routes. Explanation: The SE's have their own dataplane network, they are also the ones responsible for creating the VIPs you define for your VS. So, if you want your VIPs to be reachable you have to make sure there are routes in your network to the VIPS where the SEs are next hops either with BGP or static routes. The VIP is what it is, a Virtual IP meaning it dont have its own VLAN and gateway in your infrastructure. It is created and realised by the SE's. The SE's are then the gateways for your VIPS. A VIP address could be anything. At the same time the SEs dataplane network needs connectivity to the backend servers it is supposed to loadbalance, so this dataplane network also needs routes to reach those. In this post that means the SE's dataplane network will need reachability to the k8s worker nodes where your apps are running in the home-lab site and in the remote site it needs reachability to the TKGs workers. On a sidenote I am not running routable pods, they are nat-ed trough my workers, and I am using Antrea as CNI with NodePortLocal configured.  I also prefer to have a different network for the SE dataplane, different VIP subnets as it is easier to maintain control, isolation, firewall rules etc. 

The diagram above is very high level, as it does not go into all networking details, firewall rules etc but it gives an overview of the communication needed.

When one have an clear idea of the connectivity requirements we need to form the GSLB "partnership" between the AVI controllers. I was thinking back and forth whether I should cover these steps also but instead I will link to a good friends blog site [here](https://vmware.fqdn.nl/2022/09/06/avi-gslb-part-1/) that does this brilliantly. Its all about saving the environment of unnecessary digital ink :smile:. This also goes for AKO deployment. This is also covered [here](https://yikes.guzware.net/2020/10/08/nsx-advanced-loadbalancer-with-antrea-on-native-k8s/#install-ako) or from the AVI docs page [here](https://avinetworks.com/docs/ako/1.8/ako-installation/)  
It should look like this on both controllers when everything is up and ready for GSLB:
<img src=images/image-20221115143831355.png style="width:1000px" />
It should be reflected on the secondary controller as well, except there will be no option to edit. 


## Time to deploy AMKO in K8s

AMKO can be deployed in two ways. It can be sufficient with only one instance of AMKO deployed in your primary k8s cluster, or you can go the federation approach and deploy AMKO in all your clusters that you want to use GSLB on. Then you will end up with one master instance of AMKO and "followers" or federation member on the others. One of the benefit is that you can promote one of the follower members if the primary is lost. 
I will go with the simple approach, deploy AMKO once, in my primary k8s cluster in my home-lab. 

<img src=images/image-20221115115946070.png style="width:1000px" />

### AMKO preparations before deploy with Helm

AMKO will be deployed by using Helm, so if Helm is not installed do that. 
To successfully install AMKO there is a couple of things to be done. First, decide which is your primary cluster (where to deploy AMKO). When you have decided that (the easy step) then you need to prepare a secret that contains the context/clusters/users for all the k8s clusters you want to use GSLB on. 
An example file can be found [here](https://github.com/avinetworks/avi-helm-charts/blob/master/docs/AMKO/kubeconfig.md). Create this content in a regular file and name the file `gslb-members`. The naming of the file is important, if you name it differently AMKO will fail as it cant find the secret. I have tried to find a variable that is able override this in the value.yaml for the Helm chart but has not succeeded, so I went with the default naming. When that is populated with the k8s clusters you want, we need to create a secret in our primary k8s cluster like this: `kubectl create secret generic gslb-config-secret --from-file gslb-members -n avi-system`. The namespace here is the namespace where AKO is already deployed in.

This should give you a secret like this:

```bash
gslb-config-secret                      Opaque                                1      20h
```

#### A note on kubeconfig for vSphere with Tanzu (TKGs)

When logging into a guest cluster in TKGs we usually do this through the supervisor with either vSphere local users or AD users defined in vSphere and we get a timebased token. Its not possible to use this approach. So what I went with was to grab the admin credentials for my TKGs guest cluster and used that context instead. [Here](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-C099E736-43A6-464C-9BFA-29B8509F0DA1.html) is how to do that. This is not a recommended approach, instead one should create and use a service account. Maybe I will get back to this later and update how.

Back to the AMKO deployment...

The secret is ready, now we need to get the value.yaml for the AMKO version we will install. I am using AMKO 1.8.1 (same for AKO).
The Helm repo for AMKO is already added if AKO has been installed using Helm, the same repo. If not, add the repo:

```bash
helm repo add ako https://projects.registry.vmware.com/chartrepo/ako
```

Download the value.yaml: 

```bash
 helm show values ako/amko --version 1.8.1 > values.yaml   (there is a typo in the official doc - it points to just amko)
```

Now edit the values.yaml:

```yaml
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 1

image:
  repository: projects.registry.vmware.com/ako/amko
  pullPolicy: IfNotPresent

# Configs related to AMKO Federator
federation:
  # image repository
  image:
    repository: projects.registry.vmware.com/ako/amko-federator
    pullPolicy: IfNotPresent
  # cluster context where AMKO is going to be deployed
  currentCluster: 'k8slab-admin@k8slab' #####use the context name - for your leader/primary cluster
  # Set to true if AMKO on this cluster is the leader
  currentClusterIsLeader: true
  # member clusters to federate the GSLBConfig and GDP objects on, if the
  # current cluster context is part of this list, the federator will ignore it
  memberClusters:
  - 'k8slab-admin@k8slab' #####use the context name
  - 'tkgs-cluster-1-admin@tkgs-cluster-1' #####use the context name
# Configs related to AMKO Service discovery
serviceDiscovery:
  # image repository
  # image:
  #   repository: projects.registry.vmware.com/ako/amko-service-discovery
  #   pullPolicy: IfNotPresent

# Configs related to Multi-cluster ingress. Note: MultiClusterIngress is a tech preview.
multiClusterIngress:
  enable: false

configs:
  gslbLeaderController: '172.18.5.51' ##### MGMT ip leader/primary avi controller
  controllerVersion: 22.1.1
  memberClusters:
  - clusterContext: 'k8slab-admin@k8slab' #####use the context name
  - clusterContext: 'tkgs-cluster-1-admin@tkgs-cluster-1' #####use the context name
  refreshInterval: 1800
  logLevel: INFO
  # Set the below flag to true if a different GSLB Service fqdn is desired than the ingress/route's
  # local fqdns. Note that, this field will use AKO's HostRule objects' to find out the local to global
  # fqdn mapping. To configure a mapping between the local to global fqdn, configure the hostrule
  # object as:
  # [...]
  # spec:
  #  virtualhost:
  #    fqdn: foo.avi.com
  #    gslb:
  #      fqdn: gs-foo.avi.com
  useCustomGlobalFqdn: true    ####### set this to true if you want to define custom FQDN for GSLB - I use this

gslbLeaderCredentials:
  username: 'admin'  ##### username/password AVI Controller
  password: 'password' ##### username/password AVI Controller

globalDeploymentPolicy:
  # appSelector takes the form of:
  appSelector:
    label:
      app: 'gslb'     #### I am using this selector for services to be used in GSLB
  # Uncomment below and add the required ingress/route/service label
  # appSelector:

  # namespaceSelector takes the form of:
  # namespaceSelector:
  #   label:
  #     ns: gslb   <example label key-value for namespace>
  # Uncomment below and add the reuqired namespace label
  # namespaceSelector:

  # list of all clusters that the GDP object will be applied to, can take any/all values
  # from .configs.memberClusters
  matchClusters:
  - cluster: 'k8slab-admin@k8slab' ####use the context name
  - cluster: 'tkgs-cluster-1-admin@tkgs-cluster-1' ####use the context name

  # list of all clusters and their traffic weights, if unspecified, default weights will be
  # given (optional). Uncomment below to add the required trafficSplit.
  # trafficSplit:
  #   - cluster: "cluster1-admin"
  #     weight: 8
  #   - cluster: "cluster2-admin"
  #     weight: 2

  # Uncomment below to specify a ttl value in seconds. By default, the value is inherited from
  # Avi's DNS VS.
  # ttl: 10

  # Uncomment below to specify custom health monitor refs. By default, HTTP/HTTPS path based health
  # monitors are applied on the GSs.
  # healthMonitorRefs:
  # - hmref1
  # - hmref2

  # Uncomment below to specify a Site Persistence profile ref. By default, Site Persistence is disabled.
  # Also, note that, Site Persistence is only applicable on secure ingresses/routes and ignored
  # for all other cases. Follow https://avinetworks.com/docs/20.1/gslb-site-cookie-persistence/ to create
  # a Site persistence profile.
  # sitePersistenceRef: gap-1

  # Uncomment below to specify gslb service pool algorithm settings for all gslb services. Applicable
  # values for lbAlgorithm:
  # 1. GSLB_ALGORITHM_CONSISTENT_HASH (needs a hashMask field to be set too)
  # 2. GSLB_ALGORITHM_GEO (needs geoFallback settings to be used for this field)
  # 3. GSLB_ALGORITHM_ROUND_ROBIN (default)
  # 4. GSLB_ALGORITHM_TOPOLOGY
  #
  # poolAlgorithmSettings:
  #   lbAlgorithm:
  #   hashMask:           # required only for lbAlgorithm == GSLB_ALGORITHM_CONSISTENT_HASH
  #   geoFallback:        # fallback settings required only for lbAlgorithm == GSLB_ALGORITHM_GEO
  #     lbAlgorithm:      # can only have either GSLB_ALGORITHM_ROUND_ROBIN or GSLB_ALGORITHM_CONSISTENT_HASH
  #     hashMask:         # required only for fallback lbAlgorithm as GSLB_ALGORITHM_CONSISTENT_HASH

serviceAccount:
  # Specifies whether a service account should be created
  create: true
  # Annotations to add to the service account
  annotations: {}
  # The name of the service account to use.
  # If not set and create is true, a name is generated using the fullname template
  name:

resources:
  limits:
    cpu: 250m
    memory: 300Mi
  requests:
    cpu: 100m
    memory: 200Mi

service:
  type: ClusterIP
  port: 80

rbac:
  # creates the pod security policy if set to true
  pspEnable: false

persistentVolumeClaim: ''
mountPath: /log
logFile: amko.log

federatorLogFile: amko-federator.log


```



When done, its time to install AMKO like this:

```bash
helm install  ako/amko  --generate-name --version 1.8.1 -f /path/to/values.yaml  --set configs.gslbLeaderController=<leader_controller_ip> --namespace=avi-system    ####There is a typo in the official docs - its pointing to amko only
```

If everything went well you should se a couple of things in your k8s cluster under the namespace `avi-system`.

```bash
k get pods -n avi-system
NAME     READY   STATUS    RESTARTS   AGE
ako-0    1/1     Running   0          25h
amko-0   2/2     Running   0          20h

k get amkocluster amkocluster-federation -n avi-system
NAME                     AGE
amkocluster-federation   20h

k get gc -n avi-system gc-1
NAME   AGE
gc-1   20h

k get gdp -n avi-system
NAME         AGE
global-gdp   20h

```

AMKO is up and running. Time create a GSLB service



## Create GSLB service

You probably already have a bunch of ingress services running, and to make them GSLB "aware" there is not much to be done to achieve that. 
If you noticed in our value.yaml for the AMKO Helm chart we defined this:

```yaml
globalDeploymentPolicy:
  # appSelector takes the form of:
  appSelector:
    label:
      app: 'gslb'     #### I am using this selector for services to be used in GSLB
```

So what we need to in our ingress service is to add the below, and then a new section where we define our gslb fqdn.

Here is my sample ingress applied in my primary k8s cluster:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-example
  labels:    #### This is added for GSLB 
    app: gslb #### This is added for GSLB - Using the selector I chose in the value.yaml
  namespace: fruit

spec:
  ingressClassName: avi-lb
  rules:
    - host: fruit-global.guzware.net  #### Specific for this site (Home Lab)
      http:
        paths:
        - path: /apple
          pathType: Prefix
          backend:
            service:
              name: apple-service
              port:
                number: 5678
        - path: /banana
          pathType: Prefix
          backend:
            service:
              name: banana-service
              port:
                number: 5678
---       #### New section to define a host rule
apiVersion: ako.vmware.com/v1alpha1
kind: HostRule
metadata:
  namespace: fruit
  name: gslb-host-rule-fruit
spec:
  virtualhost:
    fqdn: fruit-global.guzware.net #### Specific for this site (Home Lab)
    enableVirtualHost: true
    gslb:
      fqdn: fruit.gslb.guzware.net  ####This is common for both sites
```



As soon as it is applied, and there are no errors in AMKO or AKO, it should be visible in your AVI controller GUI:
<img src=images/image-20221115143557024.png style="width:1000px" />

If you click on the name it should take you to next page where it show the GSLB pool members and the status:
Screenshot below is when both sites have applied their GSLB services:
<img src=images/image-20221115144244361.png style="width:1000px" />"

Next we need to apply gslb settings on the secondary site also:

This is what I have deployed on the secondary site (note the difference in domain names specific for that site)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-example
  labels: #### This is added for GSLB
    app: gslb #### This is added for GSLB - Using the selector I chose in the value.yaml
  namespace: fruit

spec:
  ingressClassName: avi-lb
  rules:
    - host: fruit-site-2.lab.guzware.net #### Specific for this site (Remote Site)
      http:
        paths:
        - path: /apple
          pathType: Prefix
          backend:
            service:
              name: apple-service
              port:
                number: 5678
        - path: /banana
          pathType: Prefix
          backend:
            service:
              name: banana-service
              port:
                number: 5678
---     #### New section to define a host rule
apiVersion: ako.vmware.com/v1alpha1
kind: HostRule
metadata:
  namespace: fruit
  name: gslb-host-rule-fruit
spec:
  virtualhost:
    fqdn: fruit-site-2.lab.guzware.net  #### Specific for this site (Remote Site)
    enableVirtualHost: true
    gslb:
      fqdn: fruit.gslb.guzware.net   ##### Common for both sites

```

When this is applied Avi will go ahead and put this into the same GSLB service as above, and the screenshot above will be true. 

Now I have the same application deployed in both sites, but equally available whether I am sitting in my home-lab or at the remote-site. 
There is a bunch of parameters that can be tuned, which I will not go into now (maybe getting back to this and update with further possibilities with GSLB). But one of them can be LoadBalancing algorithms such as Geo Location Source. Say I want the application to be accessed from clients as close to the application as possible. And should one of the sites become unavailable it will still be accessible from one of the sites that are still online. Very cool indeed. For the sake of the demo I am about to show the only thing I change in the default GSLB settings is the TTL, I am setting it to 2 seconds so I can showcase that the application is being load balanced between both sites. Default algorithm is Round-Robin so it should balance between them regardless of the latency difference (accessing the application from my home network in my home lab vs from my home network in the remote-site which has several ms in distance). 
Heres where I am setting these settings:
<img src=images/image-20221115145714718.png style="width:1000px" />

<img src=images/image-20221115150022532.png style="width:700px" />

With a TTL of 2 seconds it should switch faster so I can see the balancing between the two sites.
Let me try to access the application from my browser using the gslb fqdn: *fruit.gslb.guzware.net/apple*

<img src=images/image-20221115151702858.png style="width:700px" />

A refresh of the page and now:
<img src=images/image-20221115151857580.png style="width:700px" />

To even illustrate more I will run a curl command against the gslb fqdn:
<img src=images/image-20221115152318642.png style="width:700px" />

Now a ping against the FQDN to show the ip of the corresponding site that answer on the call:
<img src=images/image-20221115152805493.png style="width:700px" />

Notice the change in ip address but also the latency in ms

Now I can go ahead and disable one of the site to simulate failover, and the application is still available on the same FQDN. So many possibilities with GSLB.



Thats it then. NSX ALB, AKO with AMKO between two sites, same application available in two physical location, redundancy, scale-out, availability. 
Stay tuned for more updates in advanced settings - in the future :smile:
