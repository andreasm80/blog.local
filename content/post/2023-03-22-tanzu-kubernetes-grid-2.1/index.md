---
author: "Andreas M"
title: "Tanzu Kubernetes Grid 2.1"
date: 2023-03-22T09:24:01+01:00 
description: "Article description."
draft: false 
toc: true
#featureimage: ""
thumbnail: "/images/logo-vmware-tanzu.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Tanzu
  - Kubernetes
tags:
  - TKG 2.1
  - AVI
  - AKO
  - NSX
  - KUBERNETES
  - TANZU 

comment: false # Disable comment if false.
---



# Tanzu Kubernetes Grid 

This post will go through how to deploy TKG 2.1, the management cluster, a workload cluster (or two), and the necessary preparations to be done on the underlaying infrastructure to support TKG 2.1. In this post I will use vSphere 8 with vSAN, Avi LoadBalancer, and NSX. So what we want to end up with it something like this:

<img src=images/image-20230324095947018.png style="width:800px" />

## Preparations before deployment

This post will assume the following:

- vSphere is already installed configured. See more info [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-reqs-prep-vsphere.html) and [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-reqs-prep-vsphere.html#vsphere-permissions)

- NSX has already been configured (see this [post](https://blog.andreasm.io/2022/10/26/vsphere-8-with-tanzu-using-nsx-t-avi-loadbalancer/#preparations---nsx-config) for how to configure NSX). *Segments used for both Management cluster and Workload clusters should have DHCP server available. We dont need DHCP for Workload Cluster, but Management needs DHCP. NSX can provide DHCP server functionality for this use* *

- NSX Advanced LoadBalancer has been deployed (and configured with a NSX cloud). See this [post](https://blog.andreasm.io/2022/10/26/vsphere-8-with-tanzu-using-nsx-t-avi-loadbalancer/#configure-avi-as-ingress-controller-l7-with-nsx-as-l4-lb) for how to configure this. ** 

- Import the VM template for TKG, see [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-reqs-prep-vsphere.html#import-base)

- A dedicated Linux machine/VM we can use as the bootstrap host, with the Tanzu CLI installed. See more info [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/install-cli.html) 

  

(*) *TKG 2.1 is not tied to NSX the same way as TKGs - So we can choose to use NSX for Security only or the full stack with networking and security. The built in NSX loadbalancer will not be used, I will use the NSX Advanced Loadbalancer (Avi)* 

(**) *I want to use the NSX cloud in Avi as it gives several benefits such as integration into the NSX manager where Avi automatically creates security groups, tags and services to easily be used in security policy creation and automatic "route plumbing" for the VIPs.*

### TKG Management cluster - deployment

The first step after all the pre-requirements have been done is to prepare a bootstrap yaml for the management cluster. I will post an example file here and go through what the different fields means and why I have configured them and why I have uncommented some of them. Start by logging into the bootstrap machine, or if you decide to create the bootstrap yaml somewhere else go ahead but we need to copy it over to the bootstrap machine when we are ready to create the the management cluster. 

To get started with a bootstrap yaml file we can either grab an example from [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-deploy-config-vsphere.html) or in your bootstrap machine there is a folder which contains a default config you can start out with:

```bash
andreasm@tkg-bootstrap:~/.config/tanzu/tkg/providers$ ll
total 120
drwxrwxr-x 18 andreasm andreasm  4096 Mar 24 09:10 ./
drwx------  9 andreasm andreasm  4096 Mar 16 11:32 ../
drwxrwxr-x  2 andreasm andreasm  4096 Mar 16 06:52 ako/
drwxrwxr-x  3 andreasm andreasm  4096 Mar 16 06:52 bootstrap-kubeadm/
drwxrwxr-x  4 andreasm andreasm  4096 Mar 16 06:52 cert-manager/
drwxrwxr-x  3 andreasm andreasm  4096 Mar 16 06:52 cluster-api/
-rw-------  1 andreasm andreasm  1293 Mar 16 06:52 config.yaml
-rw-------  1 andreasm andreasm 32007 Mar 16 06:52 config_default.yaml
drwxrwxr-x  3 andreasm andreasm  4096 Mar 16 06:52 control-plane-kubeadm/
drwxrwxr-x  5 andreasm andreasm  4096 Mar 16 06:52 infrastructure-aws/
drwxrwxr-x  5 andreasm andreasm  4096 Mar 16 06:52 infrastructure-azure/
drwxrwxr-x  6 andreasm andreasm  4096 Mar 16 06:52 infrastructure-docker/
drwxrwxr-x  3 andreasm andreasm  4096 Mar 16 06:52 infrastructure-ipam-in-cluster/
drwxrwxr-x  5 andreasm andreasm  4096 Mar 16 06:52 infrastructure-oci/
drwxrwxr-x  4 andreasm andreasm  4096 Mar 16 06:52 infrastructure-tkg-service-vsphere/
drwxrwxr-x  5 andreasm andreasm  4096 Mar 16 06:52 infrastructure-vsphere/
drwxrwxr-x  2 andreasm andreasm  4096 Mar 16 06:52 kapp-controller-values/
-rwxrwxr-x  1 andreasm andreasm    64 Mar 16 06:52 providers.sha256sum*
-rw-------  1 andreasm andreasm     0 Mar 16 06:52 v0.28.0
-rw-------  1 andreasm andreasm   747 Mar 16 06:52 vendir.lock.yml
-rw-------  1 andreasm andreasm   903 Mar 16 06:52 vendir.yml
drwxrwxr-x  8 andreasm andreasm  4096 Mar 16 06:52 ytt/
drwxrwxr-x  2 andreasm andreasm  4096 Mar 16 06:52 yttcb/
drwxrwxr-x  7 andreasm andreasm  4096 Mar 16 06:52 yttcc/
andreasm@tkg-bootstrap:~/.config/tanzu/tkg/providers$
```

The file you should be looking for is called *config_default.yaml* . It could be a smart choice to use this as it will include the latest config parameters following the TKG version you have downloaded (Tanzu CLI).

Now copy this file to a folder of preference and start to edit it. 
Below is a copy of an example I am using:

```yaml
#! ---------------
#! Basic config
#! -------------
CLUSTER_NAME: tkg-stc-mgmt-cluster #Name of the TKG mgmt cluster
CLUSTER_PLAN: dev #Dev or Prod, defines the amount of control plane nodes of the mgmt cluster
INFRASTRUCTURE_PROVIDER: vsphere #We are deploying on vSphere, could be AWS, Azure 
ENABLE_CEIP_PARTICIPATION: "false" #Customer Experience Improvement Program - set to true if you will participate
ENABLE_AUDIT_LOGGING: "false" #Audit logging should be true in production environments
CLUSTER_CIDR: 100.96.0.0/11 #Kubernetes Cluster CIDR
SERVICE_CIDR: 100.64.0.0/13 #Kubernetes Services CIDR
TKG_IP_FAMILY: ipv4 #ipv4 or ipv6
DEPLOY_TKG_ON_VSPHERE7: "true" #Yes to deploy standalone tkg mgmt cluster on vSphere

#! ---------------
#! vSphere config
#! -------------
VSPHERE_DATACENTER: /cPod-NSXAM-STC #Name of vSphere Datacenter
VSPHERE_DATASTORE: /cPod-NSXAM-STC/datastore/vsanDatastore #Name and path of vSphere datastore to be used
VSPHERE_FOLDER: /cPod-NSXAM-STC/vm/TKGm #Name and path to VM folder
VSPHERE_INSECURE: "false" #True if you dont want to verify vCenter thumprint below
VSPHERE_NETWORK: /cPod-NSXAM-STC/network/ls-tkg-mgmt #A network portgroup (VDS or NSX Segment) for VM placement
VSPHERE_CONTROL_PLANE_ENDPOINT: "" #Required if using Kube-Vip, I am using Avi Loadbalancer for this
VSPHERE_PASSWORD: "password" #vCenter account password for account defined below
VSPHERE_RESOURCE_POOL: /cPod-NSXAM-STC/host/Cluster/Resources #If you want to use a specific vSphere Resource Pool for the mgmt cluster. Leave it as is if not.
VSPHERE_SERVER: vcsa.cpod-nsxam-stc.az-stc.cloud-garage.net #DNS record to vCenter Server
VSPHERE_SSH_AUTHORIZED_KEY: ssh-rsa sdfgasdgadfgsdg sdfsdf@sdfsdf.net # your bootstrap machineSSH public key
VSPHERE_TLS_THUMBPRINT: 22:FD # Your vCenter SHA1 Thumbprint
VSPHERE_USERNAME: user@vspheresso/or/ad/user/domain #A user with the correct permissions

#! ---------------
#! Node config
#! -------------
OS_ARCH: amd64
OS_NAME: ubuntu
OS_VERSION: "20.04"
VSPHERE_CONTROL_PLANE_DISK_GIB: "20"
VSPHERE_CONTROL_PLANE_MEM_MIB: "4096"
VSPHERE_CONTROL_PLANE_NUM_CPUS: "2"
VSPHERE_WORKER_DISK_GIB: "20"
VSPHERE_WORKER_MEM_MIB: "4096"
VSPHERE_WORKER_NUM_CPUS: "2"
CONTROL_PLANE_MACHINE_COUNT: 1
WORKER_MACHINE_COUNT: 2

#! ---------------
#! Avi config
#! -------------
AVI_CA_DATA_B64: #Base64 of the Avi Certificate  
AVI_CLOUD_NAME: stc-nsx-cloud #Name of the cloud defined in Avi
AVI_CONTROL_PLANE_HA_PROVIDER: "true" #True as we want to use Avi as K8s API endpoint 
AVI_CONTROLLER: 172.24.3.50 #IP or Hostname Avi controller or controller cluster
# Network used to place workload clusters' endpoint VIPs - If you want to use a separate vip for Workload clusters Kubernetes API endpoint
AVI_CONTROL_PLANE_NETWORK: vip-tkg-wld-l4 #Corresponds with network defined in Avi
AVI_CONTROL_PLANE_NETWORK_CIDR: 10.13.102.0/24 #Corresponds with network defined in Avi
# Network used to place workload clusters' services external IPs (load balancer & ingress services)
AVI_DATA_NETWORK: vip-tkg-wld-l7 #Corresponds with network defined in Avi
AVI_DATA_NETWORK_CIDR: 10.13.103.0/24 #Corresponds with network defined in Avi
# Network used to place management clusters' services external IPs (load balancer & ingress services)
AVI_MANAGEMENT_CLUSTER_VIP_NETWORK_CIDR: 10.13.101.0/24 #Corresponds with network defined in Avi
AVI_MANAGEMENT_CLUSTER_VIP_NETWORK_NAME: vip-tkg-mgmt-l7 #Corresponds with network defined in Avi
# Network used to place management clusters' endpoint VIPs
AVI_MANAGEMENT_CLUSTER_CONTROL_PLANE_VIP_NETWORK_NAME: vip-tkg-mgmt-l4 #Corresponds with network defined in Avi
AVI_MANAGEMENT_CLUSTER_CONTROL_PLANE_VIP_NETWORK_CIDR: 10.13.100.0/24 #Corresponds with network defined in Avi
AVI_NSXT_T1LR: /infra/tier-1s/Tier-1 #Path to the NSX T1 you have configured, click on three dots in NSX on the T1 to get the full path.
AVI_CONTROLLER_VERSION: 22.1.2 #Latest supported version of Avi for TKG 2.1
AVI_ENABLE: "true" # Enables Avi as Loadbalancer for workloads
AVI_LABELS: "" #When used Avi is enabled only workload cluster with corresponding label
AVI_PASSWORD: "password" #Password for the account used in Avi, username defined below
AVI_SERVICE_ENGINE_GROUP: stc-nsx #Service Engine group for Workload clusters if you want to have separate groups for Workload clusters and Management cluster
AVI_MANAGEMENT_CLUSTER_SERVICE_ENGINE_GROUP: tkgm-se-group #Dedicated Service Engine group for management cluster
AVI_USERNAME: admin
AVI_DISABLE_STATIC_ROUTE_SYNC: true #Pod network reachable or not from the Avi Service Engines
AVI_INGRESS_DEFAULT_INGRESS_CONTROLLER: true #If you want to use AKO as default ingress controller, false if you plan to use other ingress controllers also.
AVI_INGRESS_SHARD_VS_SIZE: SMALL #Decides the amount of shared vs pr ip.
AVI_INGRESS_SERVICE_TYPE: NodePortLocal #NodePortLocal only when using Antrea, otherwise NodePort or ClusterIP
AVI_CNI_PLUGIN: antrea

#! ---------------
#! Proxy config
#! -------------
TKG_HTTP_PROXY_ENABLED: "false"

#! ---------------------------------------------------------------------
#! Antrea CNI configuration
#! ---------------------------------------------------------------------
# ANTREA_NO_SNAT: false
# ANTREA_TRAFFIC_ENCAP_MODE: "encap"
# ANTREA_PROXY: false
# ANTREA_POLICY: true
# ANTREA_TRACEFLOW: false
ANTREA_NODEPORTLOCAL: true
ANTREA_PROXY: true
ANTREA_ENDPOINTSLICE: true
ANTREA_POLICY: true
ANTREA_TRACEFLOW: true
ANTREA_NETWORKPOLICY_STATS: false
ANTREA_EGRESS: true
ANTREA_IPAM: false
ANTREA_FLOWEXPORTER: false
ANTREA_SERVICE_EXTERNALIP: false
ANTREA_MULTICAST: false

#! ---------------------------------------------------------------------
#! Machine Health Check configuration
#! ---------------------------------------------------------------------
ENABLE_MHC: "true"
ENABLE_MHC_CONTROL_PLANE: true
ENABLE_MHC_WORKER_NODE: true
MHC_UNKNOWN_STATUS_TIMEOUT: 5m
MHC_FALSE_STATUS_TIMEOUT: 12m

#! ---------------------------------------------------------------------
#! Identity management configuration
#! ---------------------------------------------------------------------

IDENTITY_MANAGEMENT_TYPE: none #I have disabled this, use kubeconfig instead
#LDAP_BIND_DN: CN=Andreas M,OU=Users,OU=GUZWARE,DC=guzware,DC=local
#LDAP_BIND_PASSWORD: <encoded:UHNAc=>
#LDAP_GROUP_SEARCH_BASE_DN: DC=guzware,DC=local
#LDAP_GROUP_SEARCH_FILTER: (objectClass=group)
#LDAP_GROUP_SEARCH_GROUP_ATTRIBUTE: member
#LDAP_GROUP_SEARCH_NAME_ATTRIBUTE: cn
#LDAP_GROUP_SEARCH_USER_ATTRIBUTE: distinguishedName
#LDAP_HOST: guzad07.guzware.local:636
#LDAP_ROOT_CA_DATA_B64: LS0tLS1CRUd
#LDAP_USER_SEARCH_BASE_DN: DC=guzware,DC=local
#LDAP_USER_SEARCH_FILTER: (objectClass=person)
#LDAP_USER_SEARCH_NAME_ATTRIBUTE: uid
#LDAP_USER_SEARCH_USERNAME: uid
#OIDC_IDENTITY_PROVIDER_CLIENT_ID: ""
#OIDC_IDENTITY_PROVIDER_CLIENT_SECRET: ""
#OIDC_IDENTITY_PROVIDER_GROUPS_CLAIM: ""
#OIDC_IDENTITY_PROVIDER_ISSUER_URL: ""
#OIDC_IDENTITY_PROVIDER_NAME: ""
#OIDC_IDENTITY_PROVIDER_SCOPES: ""
#OIDC_IDENTITY_PROVIDER_USERNAME_CLAIM: ""
```

*For additional explanations of the different values see [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-deploy-config-ref.html)*

When you feel you are ready with the bootstrap yaml file its time to deploy the management cluster.
From your bootstrap machine where Tanzu CLI have been installed enter the following command:

```bash
tanzu mc create --file path/to/cluster-config-file.yaml
```

For more information around this process have a look [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-deploy-file.html#mc-create)

The first thing that happens is some validation checks, if those pass it will continue to build a local bootstrap cluster on your bootstrap machine before building the TKG Management cluster in your vSphere cluster. 

> ***Note***! If you happen to use a an IP range within 172.16.0.0/12 on your computer you are accessing the bootstrap machine through you should edit the default Docker network. Otherwise you will loose connection to your bootstrap machine. This is done like this:

Add or edit, if it exists, the /etc/docker/daemon.json file with the following content:

```bash
{
 "default-address-pools":
 [
 {"base":"192.168.0.0/16","size":24}
 ]
}
```

Restart docker service or reboot the machine.

Now back to the tanzu create process, you can monitor the progress from the terminal of your bootstrap machine, and you should after a while see machines being cloned from your template and powered on. In the Avi controller you should also see a new virtual service being created:

<img src=images/image-20230324125509069.png style="width:700px" />



<img src=images/image-20230324125531897.png style="width:700px" />

The ip address depicted above is the sole control plane node as I am deploying a TKG management cluster using plan dev. 
If the progress in your bootstrap machine indicates that it is done, you can check the status with the following command:

```bash
tanzu mc get
```

This will give you this output:

```bash
  NAME                  NAMESPACE   STATUS   CONTROLPLANE  WORKERS  KUBERNETES        ROLES       PLAN  TKR
  tkg-stc-mgmt-cluster  tkg-system  running  1/1           2/2      v1.24.9+vmware.1  management  dev   v1.24.9---vmware.1-tkg.1


Details:

NAME                                                                 READY  SEVERITY  REASON  SINCE  MESSAGE
/tkg-stc-mgmt-cluster                                                True                     8d
├─ClusterInfrastructure - VSphereCluster/tkg-stc-mgmt-cluster-xw6xs  True                     8d
├─ControlPlane - KubeadmControlPlane/tkg-stc-mgmt-cluster-wrxtl      True                     8d
│ └─Machine/tkg-stc-mgmt-cluster-wrxtl-gkv5m                         True                     8d
└─Workers
  └─MachineDeployment/tkg-stc-mgmt-cluster-md-0-vs9dc                True                     3d3h
    ├─Machine/tkg-stc-mgmt-cluster-md-0-vs9dc-55c649d9fc-gnpz4       True                     8d
    └─Machine/tkg-stc-mgmt-cluster-md-0-vs9dc-55c649d9fc-gwfvt       True                     8d


Providers:

  NAMESPACE                          NAME                            TYPE                    PROVIDERNAME     VERSION  WATCHNAMESPACE
  caip-in-cluster-system             infrastructure-ipam-in-cluster  InfrastructureProvider  ipam-in-cluster  v0.1.0
  capi-kubeadm-bootstrap-system      bootstrap-kubeadm               BootstrapProvider       kubeadm          v1.2.8
  capi-kubeadm-control-plane-system  control-plane-kubeadm           ControlPlaneProvider    kubeadm          v1.2.8
  capi-system                        cluster-api                     CoreProvider            cluster-api      v1.2.8
  capv-system                        infrastructure-vsphere          InfrastructureProvider  vsphere          v1.5.1
```



When cluster is ready deployed and before we can access it with our kubectl cli tool we must set the context to it.

```bash
kubectl config use-context my-mgmnt-cluster-admin@my-mgmnt-cluster
```

 But you probably have a dedicated workstation you want to acces the cluster from, then you can export the kubeconfig like this:

```bash
tanzu mc kubeconfig get --admin --export-file MC-ADMIN-KUBECONFIG
```

Now copy the file to your workstation and accessed the cluster from there. 

> Tip! Test out [this](https://github.com/sunny0826/kubecm) tool to easy manage your Kubernetes configs: https://github.com/sunny0826/kubecm 

The above is a really great tool:

```bash
amarqvardsen@amarqvards1MD6T:~$ kubecm switch --ui-size 10
Use the arrow keys to navigate: ↓ ↑ → ←  and / toggles search
Select Kube Context
  😼 tkc-cluster-1(*)
    tkgs-cluster-1-admin@tkgs-cluster-1
    wdc-2-tkc-cluster-1
    10.13.200.2
    andreasmk8slab-admin@andreasmk8slab-pinniped
    ns-wdc-3
    tkc-cluster-1-routed
    tkg-mgmt-cluster-admin@tkg-mgmt-cluster
    stc-tkgm-mgmt-cluster
↓   tkg-wld-1-cluster-admin@tkg-wld-1-cluster

--------- Info ----------
Name:           tkc-cluster-1
Cluster:        10.13.202.1
User:           wcp:10.13.202.1:andreasm@cpod-nsxam-stc.az-stc.cloud-garage.net
```

Now your TKG management cluster is ready and we can deploy a workload cluster. 

If you noticed some warnings around conciliation during deployment, you can check whether they failed or not by issuing this command after you have gotten the kubeconfig context in place to the Management cluster with this command:

```bash
andreasm@tkg-bootstrap:~$ kubectl get pkgi -A
NAMESPACE       NAME                                                     PACKAGE NAME                                         PACKAGE VERSION                    DESCRIPTION           AGE
stc-tkgm-ns-1   stc-tkgm-wld-cluster-1-kapp-controller                   kapp-controller.tanzu.vmware.com                     0.41.5+vmware.1-tkg.1              Reconcile succeeded   7d22h
stc-tkgm-ns-2   stc-tkgm-wld-cluster-2-kapp-controller                   kapp-controller.tanzu.vmware.com                     0.41.5+vmware.1-tkg.1              Reconcile succeeded   7d16h
tkg-system      ako-operator                                             ako-operator-v2.tanzu.vmware.com                     0.28.0+vmware.1-tkg.1-zshippable   Reconcile succeeded   8d
tkg-system      tanzu-addons-manager                                     addons-manager.tanzu.vmware.com                      0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tanzu-auth                                               tanzu-auth.tanzu.vmware.com                          0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tanzu-cliplugins                                         cliplugins.tanzu.vmware.com                          0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tanzu-core-management-plugins                            core-management-plugins.tanzu.vmware.com             0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tanzu-featuregates                                       featuregates.tanzu.vmware.com                        0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tanzu-framework                                          framework.tanzu.vmware.com                           0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tkg-clusterclass                                         tkg-clusterclass.tanzu.vmware.com                    0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tkg-clusterclass-vsphere                                 tkg-clusterclass-vsphere.tanzu.vmware.com            0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tkg-pkg                                                  tkg.tanzu.vmware.com                                 0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-antrea                              antrea.tanzu.vmware.com                              1.7.2+vmware.1-tkg.1-advanced      Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-capabilities                        capabilities.tanzu.vmware.com                        0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-load-balancer-and-ingress-service   load-balancer-and-ingress-service.tanzu.vmware.com   1.8.2+vmware.1-tkg.1               Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-metrics-server                      metrics-server.tanzu.vmware.com                      0.6.2+vmware.1-tkg.1               Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-pinniped                            pinniped.tanzu.vmware.com                            0.12.1+vmware.2-tkg.3              Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-secretgen-controller                secretgen-controller.tanzu.vmware.com                0.11.2+vmware.1-tkg.1              Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-tkg-storageclass                    tkg-storageclass.tanzu.vmware.com                    0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-vsphere-cpi                         vsphere-cpi.tanzu.vmware.com                         1.24.3+vmware.1-tkg.1              Reconcile succeeded   8d
tkg-system      tkg-stc-mgmt-cluster-vsphere-csi                         vsphere-csi.tanzu.vmware.com                         2.6.2+vmware.2-tkg.1               Reconcile succeeded   8d
tkg-system      tkr-service                                              tkr-service.tanzu.vmware.com                         0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tkr-source-controller                                    tkr-source-controller.tanzu.vmware.com               0.28.0+vmware.1                    Reconcile succeeded   8d
tkg-system      tkr-vsphere-resolver                                     tkr-vsphere-resolver.tanzu.vmware.com                0.28.0+vmware.1                    Reconcile succeeded   8d
```



### TKG Workload cluster deployment

Now that we have done all the initial configs to support our TKG environment on vSphere, NSX and Avi, to deploy a workload cluster is as simple as loading a game on the Commodore 64 :vhs:
From your bootstrap machine make sure you are in the context of your TKG Managment cluster:

```bash
andreasm@tkg-bootstrap:~/.config/tanzu/tkg/providers$ kubectl config current-context
tkg-stc-mgmt-cluster-admin@tkg-stc-mgmt-cluster
```

I you prefer to deploy your workload clusters in its own Kubernetes namespace go ahead and create a namespace for your workload cluster like this:

```bash
kubectl create ns "name-of-namespace"
```

Now to create a workload cluster, this also needs a yaml definition file. The easiest way to achieve such a file is to re-use the bootstramp yaml we created for our TKG Management cluster. For more information deploying a workload cluster in TKG read [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/using-tkg-21/workload-clusters-deploy.html#dry-run).By using the Tanzu CLI we can convert this bootstrap file to a workload cluster yaml definiton file, this is done like this:

```bash
tanzu cluster create stc-tkgm-wld-cluster-1 --namespace=stc-tkgm-ns-1 --file tkg-mgmt-bootstrap-tkg-2.1.yaml --dry-run > stc-tkg-wld-cluster-1.yaml
```

The command above read the bootstrap yaml file we used to deploy the TKG management cluster, converts it into a yaml file we can use to deploy a workload cluster. It alse removes unnecessary fields not needed for our workload cluster. 
I am also using the --namespace field to point the config to use the correct namespace and automatically put that into the yaml file. then I am pointing to the TKG Management bootstrap yaml file and finally the --dry-run command to pipe it to a file called *stc-tkg-wld-cluster-1.yaml*. The result should look something like this:

```yaml
apiVersion: cpi.tanzu.vmware.com/v1alpha1
kind: VSphereCPIConfig
metadata:
  name: stc-tkgm-wld-cluster-1
  namespace: stc-tkgm-ns-1
spec:
  vsphereCPI:
    ipFamily: ipv4
    mode: vsphereCPI
    tlsCipherSuites: TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
---
apiVersion: csi.tanzu.vmware.com/v1alpha1
kind: VSphereCSIConfig
metadata:
  name: stc-tkgm-wld-cluster-1
  namespace: stc-tkgm-ns-1
spec:
  vsphereCSI:
    config:
      datacenter: /cPod-NSXAM-STC
      httpProxy: ""
      httpsProxy: ""
      noProxy: ""
      region: null
      tlsThumbprint: 22:FD
      useTopologyCategories: false
      zone: null
    mode: vsphereCSI
---
apiVersion: run.tanzu.vmware.com/v1alpha3
kind: ClusterBootstrap
metadata:
  annotations:
    tkg.tanzu.vmware.com/add-missing-fields-from-tkr: v1.24.9---vmware.1-tkg.1
  name: stc-tkgm-wld-cluster-1
  namespace: stc-tkgm-ns-1
spec:
  additionalPackages:
  - refName: metrics-server*
  - refName: secretgen-controller*
  - refName: pinniped*
  cpi:
    refName: vsphere-cpi*
    valuesFrom:
      providerRef:
        apiGroup: cpi.tanzu.vmware.com
        kind: VSphereCPIConfig
        name: stc-tkgm-wld-cluster-1
  csi:
    refName: vsphere-csi*
    valuesFrom:
      providerRef:
        apiGroup: csi.tanzu.vmware.com
        kind: VSphereCSIConfig
        name: stc-tkgm-wld-cluster-1
  kapp:
    refName: kapp-controller*
---
apiVersion: v1
kind: Secret
metadata:
  name: stc-tkgm-wld-cluster-1
  namespace: stc-tkgm-ns-1
stringData:
  password: Password
  username: andreasm@cpod-nsxam-stc.az-stc.cloud-garage.net
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  annotations:
    osInfo: ubuntu,20.04,amd64
    tkg/plan: dev
  labels:
    tkg.tanzu.vmware.com/cluster-name: stc-tkgm-wld-cluster-1
  name: stc-tkgm-wld-cluster-1
  namespace: stc-tkgm-ns-1
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 100.96.0.0/11
    services:
      cidrBlocks:
      - 100.64.0.0/13
  topology:
    class: tkg-vsphere-default-v1.0.0
    controlPlane:
      metadata:
        annotations:
          run.tanzu.vmware.com/resolve-os-image: image-type=ova,os-name=ubuntu
      replicas: 1
    variables:
    - name: controlPlaneCertificateRotation
      value:
        activate: true
        daysBefore: 90
    - name: auditLogging
      value:
        enabled: false
    - name: podSecurityStandard
      value:
        audit: baseline
        deactivated: false
        warn: baseline
    - name: apiServerEndpoint
      value: ""
    - name: aviAPIServerHAProvider
      value: true
    - name: vcenter
      value:
        cloneMode: fullClone
        datacenter: /cPod-NSXAM-STC
        datastore: /cPod-NSXAM-STC/datastore/vsanDatastore
        folder: /cPod-NSXAM-STC/vm/TKGm
        network: /cPod-NSXAM-STC/network/ls-tkg-mgmt #Notice this - if you want to place your workload clusters in a different network change this to your desired portgroup.
        resourcePool: /cPod-NSXAM-STC/host/Cluster/Resources
        server: vcsa.cpod-nsxam-stc.az-stc.cloud-garage.net
        storagePolicyID: ""
        template: /cPod-NSXAM-STC/vm/ubuntu-2004-efi-kube-v1.24.9+vmware.1
        tlsThumbprint: 22:FD
    - name: user
      value:
        sshAuthorizedKeys:
        - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC/mavk4j/oS88qv2fowMT65qwpBHUIybHz5Ra2L53zwsv/5yvUej48QLmyAalSNNeH+FIKTkFiuX/WjsHiCI0JoMeVLx5CFwmpSiNzF5ITZ9MFisn5dqpc/6x8=
    - name: controlPlane
      value:
        machine:
          diskGiB: 20
          memoryMiB: 4096
          numCPUs: 2
    - name: worker
      value:
        count: 2
        machine:
          diskGiB: 20
          memoryMiB: 4096
          numCPUs: 2
    version: v1.24.9+vmware.1
    workers:
      machineDeployments:
      - class: tkg-worker
        metadata:
          annotations:
            run.tanzu.vmware.com/resolve-os-image: image-type=ova,os-name=ubuntu
        name: md-0
        replicas: 2
```

Read through the result, edit if you find something you would like to change. 
If you want to deploy your workload cluster on a different network than your Management cluster edit this field to reflect the correct portgroup in vCenter:

```yaml
 network: /cPod-NSXAM-STC/network/ls-tkg-mgmt
```

Now that the yaml defintion is ready we can create the first workload cluster like this:

```bash
tanzu cluster create --file stc-tkg-wld-cluster-1.yaml
```

You can monitor the progress from the terminal of your bootstrap machine. When done check your cluster status with Tanzu CLI (remember to either use -n "nameofnamespace" or just -A):

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster list -A
  NAME                    NAMESPACE      STATUS   CONTROLPLANE  WORKERS  KUBERNETES        ROLES   PLAN  TKR
  stc-tkgm-wld-cluster-1  stc-tkgm-ns-1  running  1/1           2/2      v1.24.9+vmware.1  <none>  dev   v1.24.9---vmware.1-tkg.1
  stc-tkgm-wld-cluster-2  stc-tkgm-ns-2  running  1/1           2/2      v1.24.9+vmware.1  <none>  dev   v1.24.9---vmware.1-tkg.1
```

Further verifications can be done with this command:

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster get stc-tkgm-wld-cluster-1 -n stc-tkgm-ns-1
  NAME                    NAMESPACE      STATUS   CONTROLPLANE  WORKERS  KUBERNETES        ROLES   TKR
  stc-tkgm-wld-cluster-1  stc-tkgm-ns-1  running  1/1           2/2      v1.24.9+vmware.1  <none>  v1.24.9---vmware.1-tkg.1


Details:

NAME                                                                   READY  SEVERITY  REASON  SINCE  MESSAGE
/stc-tkgm-wld-cluster-1                                                True                     7d22h
├─ClusterInfrastructure - VSphereCluster/stc-tkgm-wld-cluster-1-lzjxq  True                     7d22h
├─ControlPlane - KubeadmControlPlane/stc-tkgm-wld-cluster-1-22z8x      True                     7d22h
│ └─Machine/stc-tkgm-wld-cluster-1-22z8x-jjb66                         True                     7d22h
└─Workers
  └─MachineDeployment/stc-tkgm-wld-cluster-1-md-0-2qmkw                True                     3d3h
    ├─Machine/stc-tkgm-wld-cluster-1-md-0-2qmkw-6c4789d7b5-lj5wl       True                     7d22h
    └─Machine/stc-tkgm-wld-cluster-1-md-0-2qmkw-6c4789d7b5-wb7k9       True                     7d22h
```

If everything is green its time to get the kubeconfig for the cluster so we can start consume it. This is done like this:

```bash
tanzu cluster kubeconfig get stc-tkgm-wld-cluster-1 --namespace stc-tkgm-ns-1 --admin --export-file stc-tkgm-wld-cluster-1-k8s-config.yaml
```

Now you can copy this to your preferred workstation and start consuming.

> Note! The kubeconfigs I have used here is all admin privileges and is not something you will use in production where you want to have granular user access. I will create a post around user management in both TKGm and TKGs later.

The next sections will cover how to upgrade TKG, some configs on the workload clusters themselves around AKO and Antrea. 



## Antrea configs

If there is a feature you would like to enable in Antrea in one of your workload clusters, we need to create an AntreaConfig by using the AntreaConfig CRD (this is one way of doing it) and apply it on the Namespace where your workload cluster resides. This is the same approach as we do in vSphere 8 with Tanzu - see [here](https://blog.andreasm.io/2022/10/26/vsphere-8-with-tanzu-using-vds-and-avi-loadbalancer/#antrea-nodeportlocal)

```yaml
apiVersion: cni.tanzu.vmware.com/v1alpha1
kind: AntreaConfig
metadata:
  name: stc-tkgm-wld-cluster-1-antrea-package  # notice the naming-convention cluster name-antrea-package
  namespace: stc-tkgm-ns-1 # your vSphere Namespace the TKC cluster is in.
spec:
  antrea:
    config:
      featureGates:
        AntreaProxy: true
        EndpointSlice: false
        AntreaPolicy: true
        FlowExporter: true
        Egress: true
        NodePortLocal: true
        AntreaTraceflow: true
        NetworkPolicyStats: true

```



## Avi/AKO configs

In TKGm we can override the default AKO settings by using AKODeploymentConfig CRD. We apply this configuration from the TKG Managment cluster on the respective Workload cluster by using labels. An example of such a config yaml:

```yaml
apiVersion: networking.tkg.tanzu.vmware.com/v1alpha1
kind: AKODeploymentConfig
metadata:
  name: ako-stc-tkgm-wld-cluster-1
spec:
  adminCredentialRef:
    name: avi-controller-credentials
    namespace: tkg-system-networking
  certificateAuthorityRef:
    name: avi-controller-ca
    namespace: tkg-system-networking
  cloudName: stc-nsx-cloud
  clusterSelector:
    matchLabels:
      ako-stc-wld-1: "ako-l7"
  controller: 172.24.3.50
  dataNetwork:
    cidr: 10.13.103.0/24
    name: vip-tkg-wld-l7
  controlPlaneNetwork:
    cidr: 10.13.102.0/24
    name: vip-tkg-wld-l4
  extraConfigs:
    cniPlugin: antrea
    disableStaticRouteSync: false                               # required
    ingress:
      defaultIngressController: true
      disableIngressClass: false                                # required
      nodeNetworkList:                                          # required
        - cidrs:
            - 10.13.21.0/24
          networkName: ls-tkg-wld-1
      serviceType: NodePortLocal                                # required
      shardVSSize: SMALL                                        # required
    l4Config:
      autoFQDN: default
    networksConfig:
      nsxtT1LR: /infra/tier-1s/Tier-1
  serviceEngineGroup: tkgm-se-group
```

Notice the:

```yaml
  clusterSelector:
    matchLabels:
      ako-stc-wld-1: "ako-l7"
```

We need to apply this label to our workload cluster. From the TKG management cluster list all your clusters:

```bash
amarqvardsen@amarqvards1MD6T:~/Kubernetes-library/tkgm/stc-tkgm/stc-tkgm-wld-cluster-1$ k get cluster -A
NAMESPACE       NAME                     PHASE         AGE     VERSION
stc-tkgm-ns-1   stc-tkgm-wld-cluster-1   Provisioned   7d23h   v1.24.9+vmware.1
stc-tkgm-ns-2   stc-tkgm-wld-cluster-2   Provisioned   7d17h   v1.24.9+vmware.1
tkg-system      tkg-stc-mgmt-cluster     Provisioned   8d      v1.24.9+vmware.1
```

Apply the above label:

```bash
kubectl label cluster -n stc-tkgm-ns-1 stc-tkgm-wld-cluster-1 ako-stc-wld-1=ako-l7
```

Now run the get cluster command again but with the value --show-labels to see if it has been applied:

```bash
amarqvardsen@amarqvards1MD6T:~/Kubernetes-library/tkgm/stc-tkgm/stc-tkgm-wld-cluster-1$ k get cluster -A --show-labels
NAMESPACE       NAME                     PHASE         AGE     VERSION            LABELS
stc-tkgm-ns-1   stc-tkgm-wld-cluster-1   Provisioned   7d23h   v1.24.9+vmware.1   ako-stc-wld-1=ako-l7,cluster.x-k8s.io/cluster-name=stc-tkgm-wld-cluster-1,networking.tkg.tanzu.vmware.com/avi=ako-stc-tkgm-wld-cluster-1,run.tanzu.vmware.com/tkr=v1.24.9---vmware.1-tkg.1,tkg.tanzu.vmware.com/cluster-name=stc-tkgm-wld-cluster-1,topology.cluster.x-k8s.io/owned=
```

Looks good. Then we can apply the AKODeploymentConfig above.

```bash
k apply -f ako-wld-cluster-1.yaml
```

Verify if the AKODeploymentConfig has been applied:

```bash
amarqvardsen@amarqvards1MD6T:~/Kubernetes-library/tkgm/stc-tkgm/stc-tkgm-wld-cluster-1$ k get akodeploymentconfigs.networking.tkg.tanzu.vmware.com
NAME                                 AGE
ako-stc-tkgm-wld-cluster-1           7d21h
ako-stc-tkgm-wld-cluster-2           7d6h
install-ako-for-all                  8d
install-ako-for-management-cluster   8d
```

Now head back your workload cluster and check the AKO pod whether it has been restarted, if you dont want to wait you can always delete the pod to speed up the changes. To verify the changes have a look at the ako configmap like this:

```bash
amarqvardsen@amarqvards1MD6T:~/Kubernetes-library/tkgm/stc-tkgm/stc-tkgm-wld-cluster-1$ k get configmaps -n avi-system avi-k8s-config -oyaml
apiVersion: v1
data:
  apiServerPort: "8080"
  autoFQDN: default
  cloudName: stc-nsx-cloud
  clusterName: stc-tkgm-ns-1-stc-tkgm-wld-cluster-1
  cniPlugin: antrea
  controllerIP: 172.24.3.50
  controllerVersion: 22.1.2
  defaultIngController: "true"
  deleteConfig: "false"
  disableStaticRouteSync: "false"
  fullSyncFrequency: "1800"
  logLevel: INFO
  nodeNetworkList: '[{"networkName":"ls-tkg-wld-1","cidrs":["10.13.21.0/24"]}]'
  nsxtT1LR: /infra/tier-1s/Tier-1
  serviceEngineGroupName: tkgm-se-group
  serviceType: NodePortLocal
  shardVSSize: SMALL
  vipNetworkList: '[{"networkName":"vip-tkg-wld-l7","cidr":"10.13.103.0/24"}]'
kind: ConfigMap
metadata:
  annotations:
    kapp.k14s.io/identity: v1;avi-system//ConfigMap/avi-k8s-config;v1
    kapp.k14s.io/original: '{"apiVersion":"v1","data":{"apiServerPort":"8080","autoFQDN":"default","cloudName":"stc-nsx-cloud","clusterName":"stc-tkgm-ns-1-stc-tkgm-wld-cluster-1","cniPlugin":"antrea","controllerIP":"172.24.3.50","controllerVersion":"22.1.2","defaultIngController":"true","deleteConfig":"false","disableStaticRouteSync":"false","fullSyncFrequency":"1800","logLevel":"INFO","nodeNetworkList":"[{\"networkName\":\"ls-tkg-wld-1\",\"cidrs\":[\"10.13.21.0/24\"]}]","nsxtT1LR":"/infra/tier-1s/Tier-1","serviceEngineGroupName":"tkgm-se-group","serviceType":"NodePortLocal","shardVSSize":"SMALL","vipNetworkList":"[{\"networkName\":\"vip-tkg-wld-l7\",\"cidr\":\"10.13.103.0/24\"}]"},"kind":"ConfigMap","metadata":{"labels":{"kapp.k14s.io/app":"1678977773033139694","kapp.k14s.io/association":"v1.ae838cced3b6caccc5a03bfb3ae65cd7"},"name":"avi-k8s-config","namespace":"avi-system"}}'
    kapp.k14s.io/original-diff-md5: c6e94dc94aed3401b5d0f26ed6c0bff3
  creationTimestamp: "2023-03-16T14:43:11Z"
  labels:
    kapp.k14s.io/app: "1678977773033139694"
    kapp.k14s.io/association: v1.ae838cced3b6caccc5a03bfb3ae65cd7
  name: avi-k8s-config
  namespace: avi-system
  resourceVersion: "19561"
  uid: 1baa90b2-e5d7-4177-ae34-6c558b5cfe29
```

 It should reflect the changes we applied...

## Antrea RBAC

Antrea comes with a list of Tiers where we can place our Antrea Native Policies. These can also be used to restrict who is allowed to apply policies and not. See this [page](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-reqs-network-antrea-tiering.html) for more information for now. I will update this section later with my own details - including the integration with NSX.

## Upgrade TKG (from 2.1 to 2.1.1)

When a new TKG relase is available we can upgrade to use this new release. The steps I have followed are explained in detail [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-upgrade-index.html).
I recommend to always follow the updated information there. 

To upgrade TKG these are the typical steps:

1. Download the latest Tanzu CLI - from my.vmware.com
2. Download the latest Tanzu kubectl  - from my.vmware.com
3. Download the latest Photon or Ubuntu OVA VM template - from my.vmware.com
4. Upgrade the TKG Management cluster
5. Upgrade the TKG Workload clusters

So lets get into it.

### Upgrade CLI tools and dependencies

I have already downloaded the Ubuntu VM image for version 2.1.1 into my vCenter and converted it to a template. I have also downloaded the Tanzu CLI tools and Tanzu kubectl for version 2.1.1. Now I need to install the Tanzu CLI and Tanzu kubectl. So I will getting back into my bootstrap machine used previously where I already have Tanzu CLI 2.1 installed. 

The first thing I need to is to delete the following file:

```bash
~/.config/tanzu/tkg/compatibility/tkg-compatibility.yaml
```

Extract the downloaded Tanzu CLI 2.1.1 packages (this will create a cli folder where you are placed. So if you want to use another folder create this first and extract the file in there) :

```bash
tar -xvf tanzu-cli-bundle-linux-amd64.tar.gz
```

```bash
andreasm@tkg-bootstrap:~/tanzu$ tar -xvf tanzu-cli-bundle-linux-amd64.2.1.1.tar.gz
cli/
cli/core/
cli/core/v0.28.1/
cli/core/v0.28.1/tanzu-core-linux_amd64
cli/tanzu-framework-plugins-standalone-linux-amd64.tar.gz
cli/tanzu-framework-plugins-context-linux-amd64.tar.gz
cli/ytt-linux-amd64-v0.43.1+vmware.1.gz
cli/kapp-linux-amd64-v0.53.2+vmware.1.gz
cli/imgpkg-linux-amd64-v0.31.1+vmware.1.gz
cli/kbld-linux-amd64-v0.35.1+vmware.1.gz
cli/vendir-linux-amd64-v0.30.1+vmware.1.gz
```

Navigate to the cli folder and install the different packages.

Install Tanzu CLI:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ sudo install core/v0.28.1/tanzu-core-linux_amd64 /usr/local/bin/tanzu
```

Initialize the Tanzu CLI:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ tanzu init
ℹ  Checking for required plugins...
ℹ  Installing plugin 'secret:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'isolated-cluster:v0.28.1'
ℹ  Installing plugin 'login:v0.28.1'
ℹ  Installing plugin 'management-cluster:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'package:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'pinniped-auth:v0.28.1'
ℹ  Installing plugin 'telemetry:v0.28.1' with target 'kubernetes'
ℹ  Successfully installed all required plugins
✔  successfully initialized CLI
```

 Verify version:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ tanzu version
version: v0.28.1
buildDate: 2023-03-07
sha: 0e6704777-dirty
```

Now the Tanzu plugins:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ tanzu plugin clean
✔  successfully cleaned up all plugins
```

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ tanzu plugin sync
ℹ  Checking for required plugins...
ℹ  Installing plugin 'management-cluster:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'secret:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'telemetry:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'cluster:v0.28.0' with target 'kubernetes'
ℹ  Installing plugin 'kubernetes-release:v0.28.0' with target 'kubernetes'
ℹ  Installing plugin 'login:v0.28.1'
ℹ  Installing plugin 'package:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'pinniped-auth:v0.28.1'
ℹ  Installing plugin 'feature:v0.28.0' with target 'kubernetes'
ℹ  Installing plugin 'isolated-cluster:v0.28.1'
✖  [unable to fetch the plugin metadata for plugin "login": could not find the artifact for version:v0.28.1, os:linux, arch:amd64, unable to fetch the plugin metadata for plugin "package": could not find the artifact for version:v0.28.1, os:linux, arch:amd64, unable to fetch the plugin metadata for plugin "pinniped-auth": could not find the artifact for version:v0.28.1, os:linux, arch:amd64, unable to fetch the plugin metadata for plugin "isolated-cluster": could not find the artifact for version:v0.28.1, os:linux, arch:amd64]
andreasm@tkg-bootstrap:~/tanzu/cli$ tanzu plugin sync
ℹ  Checking for required plugins...
ℹ  Installing plugin 'pinniped-auth:v0.28.1'
ℹ  Installing plugin 'isolated-cluster:v0.28.1'
ℹ  Installing plugin 'login:v0.28.1'
ℹ  Installing plugin 'package:v0.28.1' with target 'kubernetes'
ℹ  Successfully installed all required plugins
✔  Done
```

Note! I had to run the comand twice as I ecountered an issue on first try. 
Now list the plugins:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ tanzu plugin list
Standalone Plugins
  NAME                DESCRIPTION                                                        TARGET      DISCOVERY  VERSION  STATUS
  isolated-cluster    isolated-cluster operations                                                    default    v0.28.1  installed
  login               Login to the platform                                                          default    v0.28.1  installed
  pinniped-auth       Pinniped authentication operations (usually not directly invoked)              default    v0.28.1  installed
  management-cluster  Kubernetes management-cluster operations                           kubernetes  default    v0.28.1  installed
  package             Tanzu package management                                           kubernetes  default    v0.28.1  installed
  secret              Tanzu secret management                                            kubernetes  default    v0.28.1  installed
  telemetry           Configure cluster-wide telemetry settings                          kubernetes  default    v0.28.1  installed

Plugins from Context:  tkg-stc-mgmt-cluster
  NAME                DESCRIPTION                           TARGET      VERSION  STATUS
  cluster             Kubernetes cluster operations         kubernetes  v0.28.0  installed
  feature             Operate on features and featuregates  kubernetes  v0.28.0  installed
  kubernetes-release  Kubernetes release operations         kubernetes  v0.28.0  installed
```

Install the Tanzu kubectl:

```bash
andreasm@tkg-bootstrap:~/tanzu$ gunzip kubectl-linux-v1.24.10+vmware.1.gz
andreasm@tkg-bootstrap:~/tanzu$ chmod ugo+x kubectl-linux-v1.24.10+vmware.1
andreasm@tkg-bootstrap:~/tanzu$ sudo install kubectl-linux-v1.24.10+vmware.1 /usr/local/bin/kubectl
```

Check version:

```bash
andreasm@tkg-bootstrap:~/tanzu$ kubectl version
WARNING: This version information is deprecated and will be replaced with the output from kubectl version --short.  Use --output=yaml|json to get the full version.
Client Version: version.Info{Major:"1", Minor:"24", GitVersion:"v1.24.10+vmware.1", GitCommit:"b980a736cbd2ac0c5f7ca793122fd4231f705889", GitTreeState:"clean", BuildDate:"2023-01-24T15:36:34Z", GoVersion:"go1.19.5", Compiler:"gc", Platform:"linux/amd64"}
Kustomize Version: v4.5.4
Server Version: version.Info{Major:"1", Minor:"24", GitVersion:"v1.24.9+vmware.1", GitCommit:"d1d7c19c9b6265a8dcd1b2ab2620ec0fc7cee784", GitTreeState:"clean", BuildDate:"2022-12-14T06:23:39Z", GoVersion:"go1.18.9", Compiler:"gc", Platform:"linux/amd64"}
```

Install the Carvel tools.
From the cli folder first out is *ytt*.
Install *ytt*:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ gunzip ytt-linux-amd64-v0.43.1+vmware.1.gz
andreasm@tkg-bootstrap:~/tanzu/cli$ chmod ugo+x ytt-linux-amd64-v0.43.1+vmware.1
andreasm@tkg-bootstrap:~/tanzu/cli$ sudo mv ./ytt-linux-amd64-v0.43.1+vmware.1 /usr/local/bin/ytt
andreasm@tkg-bootstrap:~/tanzu/cli$ ytt --version
ytt version 0.43.1
```

Instal *kapp*:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ gunzip kapp-linux-amd64-v0.53.2+vmware.1.gz
andreasm@tkg-bootstrap:~/tanzu/cli$ chmod ugo+x kapp-linux-amd64-v0.53.2+vmware.1
andreasm@tkg-bootstrap:~/tanzu/cli$ sudo mv ./kapp-linux-amd64-v0.53.2+vmware.1 /usr/local/bin/kapp
andreasm@tkg-bootstrap:~/tanzu/cli$ kapp --version
kapp version 0.53.2

Succeeded
```

Install *kbld*:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ gunzip kbld-linux-amd64-v0.35.1+vmware.1.gz
andreasm@tkg-bootstrap:~/tanzu/cli$ chmod ugo+x kbld-linux-amd64-v0.35.1+vmware.1
andreasm@tkg-bootstrap:~/tanzu/cli$ sudo mv ./kbld-linux-amd64-v0.35.1+vmware.1 /usr/local/bin/kbld
andreasm@tkg-bootstrap:~/tanzu/cli$ kbld --version
kbld version 0.35.1

Succeeded
```

Install *imgpkg*:

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ gunzip imgpkg-linux-amd64-v0.31.1+vmware.1.gz
andreasm@tkg-bootstrap:~/tanzu/cli$ chmod ugo+x imgpkg-linux-amd64-v0.31.1+vmware.1
andreasm@tkg-bootstrap:~/tanzu/cli$ sudo mv ./imgpkg-linux-amd64-v0.31.1+vmware.1 /usr/local/bin/imgpkg
andreasm@tkg-bootstrap:~/tanzu/cli$ imgpkg --version
imgpkg version 0.31.1

Succeeded
```

We have done the verification of the different versions, but we should have Tanzu cli version v0.28.1

### Upgrade the TKG Management cluster

Now we can proceed with the upgrade process. One important document to check is [this](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.1/tkg-deploy-mc-21/mgmt-release-notes.html#known-issues-upgrade)! Known Issues... 
Check whether you are using environments, if you happen to use them we need to unset them.

```bash
andreasm@tkg-bootstrap:~/tanzu/cli$ printenv
```

I am clear here and will now start the upgrading of my standalone TKG Management cluster
Make sure you are in the context of the TKG management cluster and that you have converted the new Ubuntu VM image as template.

```bash
andreasm@tkg-bootstrap:~$ kubectl config current-context
tkg-stc-mgmt-cluster-admin@tkg-stc-mgmt-cluster
```

If not, use the following command:

```bash
andreasm@tkg-bootstrap:~$ tanzu login
? Select a server  [Use arrows to move, type to filter]
> tkg-stc-mgmt-cluster()
  + new server
```

```bash
andreasm@tkg-bootstrap:~$ tanzu login
? Select a server tkg-stc-mgmt-cluster()
✔  successfully logged in to management cluster using the kubeconfig tkg-stc-mgmt-cluster
ℹ  Checking for required plugins...
ℹ  All required plugins are already installed and up-to-date
```

Here goes:
(To start the upgrade of the management cluster)

```bash
andreasm@tkg-bootstrap:~$ tanzu mc upgrade
Upgrading management cluster 'tkg-stc-mgmt-cluster' to TKG version 'v2.1.1' with Kubernetes version 'v1.24.10+vmware.1'. Are you sure? [y/N]:
```

Eh.... yes... 

Progress:

```bash
andreasm@tkg-bootstrap:~$ tanzu mc upgrade
Upgrading management cluster 'tkg-stc-mgmt-cluster' to TKG version 'v2.1.1' with Kubernetes version 'v1.24.10+vmware.1'. Are you sure? [y/N]: y
Validating the compatibility before management cluster upgrade
Validating for the required environment variables to be set
Validating for the user configuration secret to be existed in the cluster
Warning: unable to find component 'kube_rbac_proxy' under BoM
Upgrading management cluster providers...
 infrastructure-ipam-in-cluster provider's version is missing in BOM file, so it would not be upgraded
Checking cert-manager version...
Cert-manager is already up to date
Performing upgrade...
Scaling down Provider="cluster-api" Version="" Namespace="capi-system"
Scaling down Provider="bootstrap-kubeadm" Version="" Namespace="capi-kubeadm-bootstrap-system"
Scaling down Provider="control-plane-kubeadm" Version="" Namespace="capi-kubeadm-control-plane-system"
Scaling down Provider="infrastructure-vsphere" Version="" Namespace="capv-system"
Deleting Provider="cluster-api" Version="" Namespace="capi-system"
Installing Provider="cluster-api" Version="v1.2.8" TargetNamespace="capi-system"
Deleting Provider="bootstrap-kubeadm" Version="" Namespace="capi-kubeadm-bootstrap-system"
Installing Provider="bootstrap-kubeadm" Version="v1.2.8" TargetNamespace="capi-kubeadm-bootstrap-system"
Deleting Provider="control-plane-kubeadm" Version="" Namespace="capi-kubeadm-control-plane-system"
Installing Provider="control-plane-kubeadm" Version="v1.2.8" TargetNamespace="capi-kubeadm-control-plane-system"
Deleting Provider="infrastructure-vsphere" Version="" Namespace="capv-system"
Installing Provider="infrastructure-vsphere" Version="v1.5.3" TargetNamespace="capv-system"
Management cluster providers upgraded successfully...
Preparing addons manager for upgrade
Upgrading kapp-controller...
Adding last-applied annotation on kapp-controller...
Removing old management components...
Upgrading management components...
ℹ   Updating package repository 'tanzu-management'
ℹ   Getting package repository 'tanzu-management'
ℹ   Validating provided settings for the package repository
ℹ   Updating package repository resource
ℹ   Waiting for 'PackageRepository' reconciliation for 'tanzu-management'
ℹ   'PackageRepository' resource install status: Reconciling
ℹ   'PackageRepository' resource install status: ReconcileSucceeded
ℹ  Updated package repository 'tanzu-management' in namespace 'tkg-system'
ℹ   Installing package 'tkg.tanzu.vmware.com'
ℹ   Updating package 'tkg-pkg'
ℹ   Getting package install for 'tkg-pkg'
ℹ   Getting package metadata for 'tkg.tanzu.vmware.com'
ℹ   Updating secret 'tkg-pkg-tkg-system-values'
ℹ   Updating package install for 'tkg-pkg'
ℹ   Waiting for 'PackageInstall' reconciliation for 'tkg-pkg'
ℹ   'PackageInstall' resource install status: ReconcileSucceeded
ℹ  Updated installed package 'tkg-pkg'
Cleanup core packages repository...
Core package repository not found, no need to cleanup
Upgrading management cluster kubernetes version...
Upgrading kubernetes cluster to `v1.24.10+vmware.1` version, tkr version: `v1.24.10+vmware.1-tkg.2`
Waiting for kubernetes version to be updated for control plane nodes...
Waiting for kubernetes version to be updated for worker nodes...
```



In vCenter we should start see some action also:

<img src=images/image-20230324163628024.png style="width:600px" />

Two control plane nodes:

<img src=images/image-20230324163811606.png style="width:600px" />



No longer:

<img src=images/image-20230324164706516.png style="width:600px" />



```bash
management cluster is opted out of telemetry - skipping telemetry image upgrade
Creating tkg-bom versioned ConfigMaps...
Management cluster 'tkg-stc-mgmt-cluster' successfully upgraded to TKG version 'v2.1.1' with kubernetes version 'v1.24.10+vmware.1'
ℹ  Checking for required plugins...
ℹ  Installing plugin 'kubernetes-release:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'cluster:v0.28.1' with target 'kubernetes'
ℹ  Installing plugin 'feature:v0.28.1' with target 'kubernetes'
ℹ  Successfully installed all required plugins
```

Well, it finished successfully.

Lets verify with Tanzu CLI:

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster list --include-management-cluster -A
  NAME                    NAMESPACE      STATUS   CONTROLPLANE  WORKERS  KUBERNETES         ROLES       PLAN  TKR
  stc-tkgm-wld-cluster-1  stc-tkgm-ns-1  running  1/1           2/2      v1.24.9+vmware.1   <none>      dev   v1.24.9---vmware.1-tkg.1
  stc-tkgm-wld-cluster-2  stc-tkgm-ns-2  running  1/1           2/2      v1.24.9+vmware.1   <none>      dev   v1.24.9---vmware.1-tkg.1
  tkg-stc-mgmt-cluster    tkg-system     running  1/1           2/2      v1.24.10+vmware.1  management  dev   v1.24.10---vmware.1-tkg.2
```

Looks good, notice the different versions. Management cluster is upgraded to latest version, workload clusters are still on its older version. They are up next. 

Lets do a last check before we head to Workload cluster upgrade. 

```bash
andreasm@tkg-bootstrap:~$ tanzu mc get
  NAME                  NAMESPACE   STATUS   CONTROLPLANE  WORKERS  KUBERNETES         ROLES       PLAN  TKR
  tkg-stc-mgmt-cluster  tkg-system  running  1/1           2/2      v1.24.10+vmware.1  management  dev   v1.24.10---vmware.1-tkg.2


Details:

NAME                                                                 READY  SEVERITY  REASON  SINCE  MESSAGE
/tkg-stc-mgmt-cluster                                                True                     17m
├─ClusterInfrastructure - VSphereCluster/tkg-stc-mgmt-cluster-xw6xs  True                     8d
├─ControlPlane - KubeadmControlPlane/tkg-stc-mgmt-cluster-wrxtl      True                     17m
│ └─Machine/tkg-stc-mgmt-cluster-wrxtl-csrnt                         True                     24m
└─Workers
  └─MachineDeployment/tkg-stc-mgmt-cluster-md-0-vs9dc                True                     10m
    ├─Machine/tkg-stc-mgmt-cluster-md-0-vs9dc-54554f9575-7hdfc       True                     14m
    └─Machine/tkg-stc-mgmt-cluster-md-0-vs9dc-54554f9575-ng9lx       True                     7m4s


Providers:

  NAMESPACE                          NAME                            TYPE                    PROVIDERNAME     VERSION  WATCHNAMESPACE
  caip-in-cluster-system             infrastructure-ipam-in-cluster  InfrastructureProvider  ipam-in-cluster  v0.1.0
  capi-kubeadm-bootstrap-system      bootstrap-kubeadm               BootstrapProvider       kubeadm          v1.2.8
  capi-kubeadm-control-plane-system  control-plane-kubeadm           ControlPlaneProvider    kubeadm          v1.2.8
  capi-system                        cluster-api                     CoreProvider            cluster-api      v1.2.8
  capv-system                        infrastructure-vsphere          InfrastructureProvider  vsphere          v1.5.3
```

Congrats, head over to next level :smile:

### Upgrade workload cluster

This procedure is much simpler, almost as simple as starting a game in MS-DOS 6.2 requiring a bit over 600kb convential memory.
Make sure your are still in the TKG Management cluster context.

As done above list out the cluster you have and notice the versions they are on now.:

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster list --include-management-cluster -A
  NAME                    NAMESPACE      STATUS   CONTROLPLANE  WORKERS  KUBERNETES         ROLES       PLAN  TKR
  stc-tkgm-wld-cluster-1  stc-tkgm-ns-1  running  1/1           2/2      v1.24.9+vmware.1   <none>      dev   v1.24.9---vmware.1-tkg.1
  stc-tkgm-wld-cluster-2  stc-tkgm-ns-2  running  1/1           2/2      v1.24.9+vmware.1   <none>      dev   v1.24.9---vmware.1-tkg.1
  tkg-stc-mgmt-cluster    tkg-system     running  1/1           2/2      v1.24.10+vmware.1  management  dev   v1.24.10---vmware.1-tkg.2
```

Check if there are any new releases available from the management cluster:

```bash
andreasm@tkg-bootstrap:~$ tanzu kubernetes-release get
  NAME                       VERSION                  COMPATIBLE  ACTIVE  UPDATES AVAILABLE
  v1.22.17---vmware.1-tkg.2  v1.22.17+vmware.1-tkg.2  True        True
  v1.23.16---vmware.1-tkg.2  v1.23.16+vmware.1-tkg.2  True        True
  v1.24.10---vmware.1-tkg.2  v1.24.10+vmware.1-tkg.2  True        True
```

There is one there.. v1.24.10 and its compatible.

Lets check whether there are any updates ready for our workload cluster:

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster available-upgrades get -n stc-tkgm-ns-1 stc-tkgm-wld-cluster-1
  NAME                       VERSION                  COMPATIBLE
  v1.24.10---vmware.1-tkg.2  v1.24.10+vmware.1-tkg.2  True
```

It is... 

Lets upgrade it:

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster upgrade -n stc-tkgm-ns-1 stc-tkgm-wld-cluster-1
Upgrading workload cluster 'stc-tkgm-wld-cluster-1' to kubernetes version 'v1.24.10+vmware.1', tkr version 'v1.24.10+vmware.1-tkg.2'. Are you sure? [y/N]: y
Upgrading kubernetes cluster to `v1.24.10+vmware.1` version, tkr version: `v1.24.10+vmware.1-tkg.2`
Waiting for kubernetes version to be updated for control plane nodes...
```

y for YES

Sit back and wait for the upgrade process is to do its thing. 
You can monitor the output from the current terminal, and if something is happening in vCenter. Clone operations, power on, power off and delete.

<img src=images/image-20230324172148449.png style="width:600px" />

And the result is in:

```bash
Waiting for kubernetes version to be updated for worker nodes...
Cluster 'stc-tkgm-wld-cluster-1' successfully upgraded to kubernetes version 'v1.24.10+vmware.1'
```

We have a winner. 

Lets quickly check with Tanzu CLI:

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster get stc-tkgm-wld-cluster-1 -n stc-tkgm-ns-1
  NAME                    NAMESPACE      STATUS   CONTROLPLANE  WORKERS  KUBERNETES         ROLES   TKR
  stc-tkgm-wld-cluster-1  stc-tkgm-ns-1  running  1/1           2/2      v1.24.10+vmware.1  <none>  v1.24.10---vmware.1-tkg.2


Details:

NAME                                                                   READY  SEVERITY  REASON  SINCE  MESSAGE
/stc-tkgm-wld-cluster-1                                                True                     11m
├─ClusterInfrastructure - VSphereCluster/stc-tkgm-wld-cluster-1-lzjxq  True                     8d
├─ControlPlane - KubeadmControlPlane/stc-tkgm-wld-cluster-1-22z8x      True                     11m
│ └─Machine/stc-tkgm-wld-cluster-1-22z8x-mtpgs                         True                     15m
└─Workers
  └─MachineDeployment/stc-tkgm-wld-cluster-1-md-0-2qmkw                True                     39m
    ├─Machine/stc-tkgm-wld-cluster-1-md-0-2qmkw-58c5764865-7xvfn       True                     8m31s
    └─Machine/stc-tkgm-wld-cluster-1-md-0-2qmkw-58c5764865-c7rqj       True                     3m29s
```

Couldn't be better. 
Thats it then. Its Friday so have a great weekend and thanks for reading.



