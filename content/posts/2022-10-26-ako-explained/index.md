---
author: "Andreas M"
title: "AKO Explained"
date: 2022-10-26T12:02:39+02:00 
description: "Article description."
draft: false 
toc: true
#featureimage: ""
#thumbnail: "/images/avi_networks.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Kubernetes
  - LoadBalancing
  - AVI
tags:
  - kubernetes
  - ingress
  - loadbalancing
  - ako

comment: false # Disable comment if false.
---



# What is AKO?

*AKO is an operator which works as an ingress controller and performs Avi-specific functions in an OpenShift/Kubernetes environment with the Avi Controller. It runs as a pod in the cluster and translates the required OpenShift/Kubernetes objects to Avi objects and automates the implementation of ingresses/routes/services on the Service Engines (SE) via the Avi Controller.* ref: [link](https://avinetworks.com/docs/ako/1.8/avi-kubernetes-operator/)

<img src=images/image-20230302084251150.png style="width:800px" />



## How to install AKO

AKO is very easy installed with Helm. Four basic steps needs to be done.

1. Create a namespace for AKO in your kubernetes cluster: `kubectl create ns avi-system`
2. Add AKO Helm reposistory: `helm repo add ako https://projects.registry.vmware.com/chartrepo/ako `
3. Get the current values for the versions you want:  `helm show values ako/ako --version 1.9.1 > values.yaml`
4. Deploy (after values have been edited to suit your environment): `helm install ako/ako --generate-name --version 1.9.1 -f values.yaml -n avi-system`



## AKO Helm values explained

Before deploying AKO there are some parameters that should be configured, or most likely the deployment will fail. Below is an example file where the different fields are explained:

```yaml
# Default values for ako.
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 1

image:
  repository: projects.registry.vmware.com/ako/ako #If using your own registry update accordingly
  pullPolicy: IfNotPresent

### This section outlines the generic AKO settings
AKOSettings:
  primaryInstance: true # Defines AKO instance is primary or not. Value `true` indicates that AKO instance is primary. In a multiple AKO deployment in a cluster, only one AKO instance should be primary. Default value: true.
  enableEvents: 'true' # Enables/disables Event broadcasting via AKO 
  logLevel: WARN   # enum: INFO|DEBUG|WARN|ERROR
  fullSyncFrequency: '1800' # This frequency controls how often AKO polls the Avi controller to update itself with cloud configurations.
  apiServerPort: 8080 # Internal port for AKO's API server for the liveness probe of the AKO pod default=8080
  deleteConfig: 'false' # Has to be set to true in configmap if user wants to delete AKO created objects from AVI 
  disableStaticRouteSync: 'false' # If the POD networks are reachable from the Avi SE, set this knob to true.
  clusterName: my-cluster   # A unique identifier for the kubernetes cluster, that helps distinguish the objects for this cluster in the avi controller. // MUST-EDIT
  cniPlugin: '' # Set the string if your CNI is calico or openshift. enum: calico|canal|flannel|openshift|antrea|ncp
  enableEVH: false # This enables the Enhanced Virtual Hosting Model in Avi Controller for the Virtual Services
  layer7Only: false # If this flag is switched on, then AKO will only do layer 7 loadbalancing.Must be true if used in a TKC cluster / Tanzu with vSphere
  # NamespaceSelector contains label key and value used for namespacemigration
  # Same label has to be present on namespace/s which needs migration/sync to AKO
  namespaceSelector:
    labelKey: ''
    labelValue: ''
  servicesAPI: false # Flag that enables AKO in services API mode: https://kubernetes-sigs.github.io/service-apis/. Currently implemented only for L4. This flag uses the upstream GA APIs which are not backward compatible 
                     # with the advancedL4 APIs which uses a fork and a version of v1alpha1pre1 
  vipPerNamespace: 'false' # Enabling this flag would tell AKO to create Parent VS per Namespace in EVH mode
  istioEnabled: false # This flag needs to be enabled when AKO is be to brought up in an Istio environment
  # This is the list of system namespaces from which AKO will not listen any Kubernetes or Openshift object event.
  blockedNamespaceList: []
  # blockedNamespaceList:
  #   - kube-system
  #   - kube-public
  ipFamily: '' # This flag can take values V4 or V6 (default V4). This is for the backend pools to use ipv6 or ipv4. For frontside VS, use v6cidr


### This section outlines the network settings for virtualservices. 
NetworkSettings:
  ## This list of network and cidrs are used in pool placement network for vcenter cloud.
  ## Node Network details are not needed when in nodeport mode / static routes are disabled / non vcenter clouds.
  nodeNetworkList: []
  # nodeNetworkList:
  #   - networkName: "network-name"
  #     cidrs:
  #       - 10.0.0.1/24
  #       - 11.0.0.1/24
  enableRHI: false # This is a cluster wide setting for BGP peering.
  nsxtT1LR: '' # T1 Logical Segment mapping for backend network. Only applies to NSX-T cloud.
  bgpPeerLabels: [] # Select BGP peers using bgpPeerLabels, for selective VsVip advertisement.
  # bgpPeerLabels:
  #   - peer1
  #   - peer2
  vipNetworkList: [] # Network information of the VIP network. Multiple networks allowed only for AWS Cloud.
  # vipNetworkList:
  #  - networkName: net1
  #    cidr: 100.1.1.0/24
  #    v6cidr: 2002::1234:abcd:ffff:c0a8:101/64 # Setting this will enable the VS networks to use ipv6 
### This section outlines all the knobs  used to control Layer 7 loadbalancing settings in AKO.
L7Settings:
  defaultIngController: 'true'
  noPGForSNI: false # Switching this knob to true, will get rid of poolgroups from SNI VSes. Do not use this flag, if you don't want http caching. This will be deprecated once the controller support caching on PGs.
  serviceType: ClusterIP # enum NodePort|ClusterIP|NodePortLocal. NodePortLocal can only be used if Antrea is the CNI
  shardVSSize: LARGE   # Use this to control the layer 7 VS numbers. This applies to both secure/insecure VSes but does not apply for passthrough. ENUMs: LARGE, MEDIUM, SMALL, DEDICATED
  passthroughShardSize: SMALL   # Control the passthrough virtualservice numbers using this ENUM. ENUMs: LARGE, MEDIUM, SMALL
  enableMCI: 'false' # Enabling this flag would tell AKO to start processing multi-cluster ingress objects.

### This section outlines all the knobs  used to control Layer 4 loadbalancing settings in AKO.
L4Settings:
  defaultDomain: '' # If multiple sub-domains are configured in the cloud, use this knob to set the default sub-domain to use for L4 VSes.
  autoFQDN: default   # ENUM: default(<svc>.<ns>.<subdomain>), flat (<svc>-<ns>.<subdomain>), "disabled" If the value is disabled then the FQDN generation is disabled.

### This section outlines settings on the Avi controller that affects AKO's functionality.
ControllerSettings:
  serviceEngineGroupName: Default-Group   # Name of the ServiceEngine Group.
  controllerVersion: '' # The controller API version
  cloudName: Default-Cloud   # The configured cloud name on the Avi controller.
  controllerHost: '' # IP address or Hostname of Avi Controller
  tenantName: admin   # Name of the tenant where all the AKO objects will be created in AVI.

nodePortSelector: # Only applicable if serviceType is NodePort
  key: ''
  value: ''

resources:
  limits:
    cpu: 350m
    memory: 400Mi
  requests:
    cpu: 200m
    memory: 300Mi

securityContext: {}

podSecurityContext: {}

rbac:
  # Creates the pod security policy if set to true
  pspEnable: false


avicredentials:
  username: ''
  password: ''
  authtoken:
  certificateAuthorityData:


persistentVolumeClaim: ''
mountPath: /log
logFile: avi.log

```



More info [here](https://avinetworks.com/docs/ako/1.8/configuring-ako/)

