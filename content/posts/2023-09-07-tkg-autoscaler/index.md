---
author: "Andreas M"
title: "TKG Autoscaler"
date: 2023-09-07T07:46:13+02:00 
description: "How the TKG autoscaler works"
draft: false 
toc: true
#featureimage: ""
#thumbnail: "/images/logo-vmware-tanzu.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Kubernetes
  - Autoscaling
tags:
  - autoscaling
  - kubernetes
  - tanzu

summary: In this post I will go through the TKG Autoscaler, how to configure it and how it works. 
comment: false # Disable comment if false.
---



# TKG autoscaler

From the official TKG documentation [page](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.3/using-tkg/workload-clusters-scale.html):

> Cluster Autoscaler is a Kubernetes program that automatically scales Kubernetes clusters depending on the demands on the workload clusters. Use Cluster Autoscaler only for workload clusters deployed by a standalone management cluster.

Ok, lets try out this then.



## Enable Cluster Autoscaler

So one of the pre-requisites is a TKG standalone management cluster. I have that already deployed and running. Then for a workload cluster to be able to use the cluster autoscaler I need to enable this by adding some parameters in the cluster deployment manifest. 
The following is the autoscaler relevant variables, some variables are required some are optional and only valid for use on a workload cluster deployment manifest. According to the official documentation the only supported way to enable autoscaler is when provisioning a new workload cluster. 

- ENABLE_AUTOSCALER: "true" #Required if you want to enable the autoscaler
- AUTOSCALER_MAX_NODES_TOTAL: "0" #Optional
- AUTOSCALER_SCALE_DOWN_DELAY_AFTER_ADD: "10m" #Optional
- AUTOSCALER_SCALE_DOWN_DELAY_AFTER_DELETE: "10s" #Optional
- AUTOSCALER_SCALE_DOWN_DELAY_AFTER_FAILURE: "3m" #Optional
- AUTOSCALER_SCALE_DOWN_UNNEEDED_TIME: "10m" #Optional
- AUTOSCALER_MAX_NODE_PROVISION_TIME: "15m" #Optional

- AUTOSCALER_MIN_SIZE_0: "1" #Required (if Autoscaler is enabled as above)
- AUTOSCALER_MAX_SIZE_0: "2" #Required (if Autoscaler is enabled as above)
- AUTOSCALER_MIN_SIZE_1: "1" #Required (if Autoscaler is enabled as above, and using prod template and tkg in multi-az )
- AUTOSCALER_MAX_SIZE_1: "3" #Required (if Autoscaler is enabled as above, and using prod template and tkg in multi-az )
- AUTOSCALER_MIN_SIZE_2: "1" #Required (if Autoscaler is enabled as above, and using prod template and tkg in multi-az )
- AUTOSCALER_MAX_SIZE_2: "4" #Required (if Autoscaler is enabled as above, and using prod template and tkg in multi-az )

### Enable Autoscaler upon provisioning of a new workload cluster

Start by preparing a class-based yaml for the workload cluster. This procedure involves adding the AUTOSCALER variables (above) to the tkg bootstrap yaml (the one used to deploy the TKG management cluster). Then generate a cluster-class yaml manifest for the new workload cluster.
I will make a copy of my existing TKG bootstrap yaml file, name it something relevant to autoscaling. Then in this file I will add these variables:

```yaml
#! ---------------
#! Workload Cluster Specific
#! -------------
ENABLE_AUTOSCALER: "true"
AUTOSCALER_MAX_NODES_TOTAL: "0"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_ADD: "10m"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_DELETE: "10s"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_FAILURE: "3m"
AUTOSCALER_SCALE_DOWN_UNNEEDED_TIME: "10m"
AUTOSCALER_MAX_NODE_PROVISION_TIME: "15m"
AUTOSCALER_MIN_SIZE_0: "1"  #This will be used if not using availability zones. If using az this will count as zone 1 - required
AUTOSCALER_MAX_SIZE_0: "2"  ##This will be used if not using availability zones. If using az this will count as zone 1 - required
AUTOSCALER_MIN_SIZE_1: "1"  #This will be used for availability zone 2
AUTOSCALER_MAX_SIZE_1: "3"  #This will be used for availability zone 2
AUTOSCALER_MIN_SIZE_2: "1"  #This will be used for availability zone 3
AUTOSCALER_MAX_SIZE_2: "4"  #This will be used for availability zone 3
```

{{% notice info "Tip!" %}}

If not using TKG in a multi availability zone deployment, there is no need to add the lines AUTOSCALER_MIN_SIZE_1, AUTOSCALER_MAX_SIZE_1, AUTOSCALER_MIN_SIZE_2, and AUTOSCALER_MAX_SIZE_2 as these are only used for the additional zones you have configured. For a "no AZ" deployment AUTOSCALER_MIN/MAX_SIZE_1 is sufficient. 

{{% /notice %}}

After the above has been added I will do a "--dry-run" to create my workload cluster class-based yaml file:

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster create tkg-cluster-3-auto --namespace tkg-ns-3 --file tkg-mgmt-bootstrap-tkg-2.3-autoscaler.yaml --dry-run > tkg-cluster-3-auto.yaml
```

 The above command gives the workload cluster the name tkg-cluster-3-auto in the namespace tkg-ns-3 and using the modified tkg bootstrap file containing the autocluster variables. The output is the class-based yaml I will use to create the cluster, like this (if no error during the dry-run command).
In my mgmt bootstrap I have defined the autoscaler min_max settings just to reflect the capabilities in differentiating settings pr availability zone. According to the manual this should only be used in AWS, but in 2.3 multi-az is fully supported and the docs has probably not been updated yet. If I take a look at the class-based yaml:

```yaml
    workers:
      machineDeployments:
      - class: tkg-worker
        failureDomain: wdc-zone-2
        metadata:
          annotations:
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-max-size: "2"
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-min-size: "1"
            run.tanzu.vmware.com/resolve-os-image: image-type=ova,os-name=ubuntu
        name: md-0
        strategy:
          type: RollingUpdate
      - class: tkg-worker
        failureDomain: wdc-zone-3
        metadata:
          annotations:
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-max-size: "3"
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-min-size: "1"
            run.tanzu.vmware.com/resolve-os-image: image-type=ova,os-name=ubuntu
        name: md-1
        strategy:
          type: RollingUpdate
      - class: tkg-worker
        failureDomain: wdc-zone-3
        metadata:
          annotations:
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-max-size: "4"
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-min-size: "1"
            run.tanzu.vmware.com/resolve-os-image: image-type=ova,os-name=ubuntu
        name: md-2
        strategy:
          type: RollingUpdate
---
```

I notice that it does take into consideration my different availability zones. Perfect.

Before I deploy my workload cluster, I will edit the manifest to only deploy worker nodes in my AZ zone 2 due to resource constraints in my lab and to make the demo a bit better (scaling up from one worker and back again) then I will deploy the workload cluster. 

```bash
andreasm@tkg-bootstrap:~$ tanzu cluster create --file tkg-cluster-3-auto.yaml
Validating configuration...
cluster class based input file detected, getting tkr version from input yaml
input TKR Version: v1.26.5+vmware.2-tkg.1
TKR Version v1.26.5+vmware.2-tkg.1, Kubernetes Version v1.26.5+vmware.2-tkg.1 configured
```

Now it is all about wating... 
After the wating period is done it is time for some testing... 

### Enable Autoscaler on existing/running workload cluster

I have already a TKG workload cluster up and running and I want to "post-enable" autoscaler in this cluster. This cluster has been deployed with the AUTOSCALER_ENABLE=false and below is the class based yaml manifest (no autoscaler variables):

```yaml
    workers:
      machineDeployments:
      - class: tkg-worker
        failureDomain: wdc-zone-2
        metadata:
          annotations:
            run.tanzu.vmware.com/resolve-os-image: image-type=ova,os-name=ubuntu
        name: md-0
        replicas: 1
        strategy:
          type: RollingUpdate
```

The above class based yaml has been generated from my my mgmt bootstrap yaml with the AUTOSCALER settings like this:

```yaml
#! ---------------
#! Workload Cluster Specific
#! -------------
ENABLE_AUTOSCALER: "false"
AUTOSCALER_MAX_NODES_TOTAL: "0"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_ADD: "10m"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_DELETE: "10s"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_FAILURE: "3m"
AUTOSCALER_SCALE_DOWN_UNNEEDED_TIME: "10m"
AUTOSCALER_MAX_NODE_PROVISION_TIME: "15m"
AUTOSCALER_MIN_SIZE_0: "1"
AUTOSCALER_MAX_SIZE_0: "4"
AUTOSCALER_MIN_SIZE_1: "1"
AUTOSCALER_MAX_SIZE_1: "4"
AUTOSCALER_MIN_SIZE_2: "1"
AUTOSCALER_MAX_SIZE_2: "4"
```

If I check the autoscaler status: 

```bash
andreasm@linuxvm01:~$ k describe cm -n kube-system cluster-autoscaler-status
Error from server (NotFound): configmaps "cluster-autoscaler-status" not found
```

Now, this cluster is in "serious" need to have autoscaler enabled. So how do I do that? **This step is most likely not officially supported.**
I will now go back to the tkg mgmt bootstrap yaml, enable the autoscaler. Do a dry run of the config and apply the new class-based yaml manifest. This is all done in the TKG mgmt cluster context. 

```bash
andreasm@linuxvm01:~$ tanzu cluster create tkg-cluster-3-auto --namespace tkg-ns-3 --file tkg-mgmt-bootstrap-tkg-2.3-autoscaler-wld-1-zone.yaml --dry-run > tkg-cluster-3-auto-az.yaml
```

Before applying the yaml new class based manifest I will edit out the uneccessary crds, and just keep the updated settings relevant to the autoscaler, it may even be reduced further. Se my yaml below:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  annotations:
    osInfo: ubuntu,20.04,amd64
    tkg/plan: dev
  labels:
    tkg.tanzu.vmware.com/cluster-name: tkg-cluster-3-auto
  name: tkg-cluster-3-auto
  namespace: tkg-ns-3
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 100.96.0.0/11
    services:
      cidrBlocks:
      - 100.64.0.0/13
  topology:
    class: tkg-vsphere-default-v1.1.0
    controlPlane:
      metadata:
        annotations:
          run.tanzu.vmware.com/resolve-os-image: image-type=ova,os-name=ubuntu
      replicas: 1
    variables:
    - name: cni
      value: antrea
    - name: controlPlaneCertificateRotation
      value:
        activate: true
        daysBefore: 90
    - name: auditLogging
      value:
        enabled: false
    - name: podSecurityStandard
      value:
        audit: restricted
        deactivated: false
        warn: restricted
    - name: apiServerEndpoint
      value: ""
    - name: aviAPIServerHAProvider
      value: true
    - name: vcenter
      value:
        cloneMode: fullClone
        datacenter: /cPod-NSXAM-WDC
        datastore: /cPod-NSXAM-WDC/datastore/vsanDatastore-wdc-01
        folder: /cPod-NSXAM-WDC/vm/TKGm
        network: /cPod-NSXAM-WDC/network/ls-tkg-mgmt
        resourcePool: /cPod-NSXAM-WDC/host/Cluster-1/Resources
        server: vcsa.FQDN
        storagePolicyID: ""
        tlsThumbprint: F8:----:7D
    - name: user
      value:
        sshAuthorizedKeys:
        - ssh-rsa BBAAB3NzaC1yc2EAAAADAQABA------QgPcxDoOhL6kdBHQY3ZRPE5LIh7RWM33SvsoIgic1OxK8LPaiGEPaOfUvP2ki7TNHLxP78bPxAfbkK7llDSmOIWrm7ukwG4DLHnyriBQahLqv1Wpx4kIRj5LM2UEBx235bVDSve==
    - name: controlPlane
      value:
        machine:
          diskGiB: 20
          memoryMiB: 4096
          numCPUs: 2
    - name: worker
      value:
        machine:
          diskGiB: 20
          memoryMiB: 4096
          numCPUs: 2
    - name: controlPlaneZoneMatchingLabels
      value:
        region: k8s-region
        tkg-cp: allowed
    - name: security
      value:
        fileIntegrityMonitoring:
          enabled: false
        imagePolicy:
          pullAlways: false
          webhook:
            enabled: false
            spec:
              allowTTL: 50
              defaultAllow: true
              denyTTL: 60
              retryBackoff: 500
        kubeletOptions:
          eventQPS: 50
          streamConnectionIdleTimeout: 4h0m0s
        systemCryptoPolicy: default
    version: v1.26.5+vmware.2-tkg.1
    workers:
      machineDeployments:
      - class: tkg-worker
        failureDomain: wdc-zone-2
        metadata:
          annotations:
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-max-size: "4"
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-min-size: "1"
            run.tanzu.vmware.com/resolve-os-image: image-type=ova,os-name=ubuntu
        name: md-0
        strategy:
          type: RollingUpdate
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: tkg-cluster-3-auto-cluster-autoscaler
  name: tkg-cluster-3-auto-cluster-autoscaler
  namespace: tkg-ns-3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tkg-cluster-3-auto-cluster-autoscaler
  template:
    metadata:
      labels:
        app: tkg-cluster-3-auto-cluster-autoscaler
    spec:
      containers:
      - args:
        - --cloud-provider=clusterapi
        - --v=4
        - --clusterapi-cloud-config-authoritative
        - --kubeconfig=/mnt/tkg-cluster-3-auto-kubeconfig/value
        - --node-group-auto-discovery=clusterapi:clusterName=tkg-cluster-3-auto,namespace=tkg-ns-3
        - --scale-down-delay-after-add=10m
        - --scale-down-delay-after-delete=10s
        - --scale-down-delay-after-failure=3m
        - --scale-down-unneeded-time=10m
        - --max-node-provision-time=15m
        - --max-nodes-total=0
        command:
        - /cluster-autoscaler
        image: projects.registry.vmware.com/tkg/cluster-autoscaler:v1.26.2_vmware.1
        name: tkg-cluster-3-auto-cluster-autoscaler
        volumeMounts:
        - mountPath: /mnt/tkg-cluster-3-auto-kubeconfig
          name: tkg-cluster-3-auto-cluster-autoscaler-volume
          readOnly: true
      serviceAccountName: tkg-cluster-3-auto-autoscaler
      terminationGracePeriodSeconds: 10
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
      volumes:
      - name: tkg-cluster-3-auto-cluster-autoscaler-volume
        secret:
          secretName: tkg-cluster-3-auto-kubeconfig
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  creationTimestamp: null
  name: tkg-cluster-3-auto-autoscaler-workload
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler-workload
subjects:
- kind: ServiceAccount
  name: tkg-cluster-3-auto-autoscaler
  namespace: tkg-ns-3
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  creationTimestamp: null
  name: tkg-cluster-3-auto-autoscaler-management
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler-management
subjects:
- kind: ServiceAccount
  name: tkg-cluster-3-auto-autoscaler
  namespace: tkg-ns-3
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tkg-cluster-3-auto-autoscaler
  namespace: tkg-ns-3
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler-workload
rules:
- apiGroups:
  - ""
  resources:
  - persistentvolumeclaims
  - persistentvolumes
  - pods
  - replicationcontrollers
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - pods/eviction
  verbs:
  - create
- apiGroups:
  - policy
  resources:
  - poddisruptionbudgets
  verbs:
  - list
  - watch
- apiGroups:
  - storage.k8s.io
  resources:
  - csinodes
  - storageclasses
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - jobs
  verbs:
  - list
  - watch
- apiGroups:
  - apps
  resources:
  - daemonsets
  - replicasets
  - statefulsets
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
  - patch
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - create
  - delete
  - get
  - update
- apiGroups:
  - coordination.k8s.io
  resources:
  - leases
  verbs:
  - create
  - get
  - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler-management
rules:
- apiGroups:
  - cluster.x-k8s.io
  resources:
  - machinedeployments
  - machines
  - machinesets
  verbs:
  - get
  - list
  - update
  - watch
  - patch
- apiGroups:
  - cluster.x-k8s.io
  resources:
  - machinedeployments/scale
  - machinesets/scale
  verbs:
  - get
  - update
- apiGroups:
  - infrastructure.cluster.x-k8s.io
  resources:
  - '*'
  verbs:
  - get
  - list
```

 

And now I will apply the above yaml on my running TKG workload cluster using *kubectl* (done from the mgmt context):

```bash
andreasm@linuxvm01:~$ kubectl apply -f tkg-cluster-3-enable-only-auto-az.yaml
cluster.cluster.x-k8s.io/tkg-cluster-3-auto configured
Warning: would violate PodSecurity "restricted:v1.24": allowPrivilegeEscalation != false (container "tkg-cluster-3-auto-cluster-autoscaler" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "tkg-cluster-3-auto-cluster-autoscaler" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "tkg-cluster-3-auto-cluster-autoscaler" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "tkg-cluster-3-auto-cluster-autoscaler" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/tkg-cluster-3-auto-cluster-autoscaler created
clusterrolebinding.rbac.authorization.k8s.io/tkg-cluster-3-auto-autoscaler-workload created
clusterrolebinding.rbac.authorization.k8s.io/tkg-cluster-3-auto-autoscaler-management created
serviceaccount/tkg-cluster-3-auto-autoscaler created
clusterrole.rbac.authorization.k8s.io/cluster-autoscaler-workload unchanged
clusterrole.rbac.authorization.k8s.io/cluster-autoscaler-management unchanged
```

Checking for autoscaler status now shows this:

```bash
andreasm@linuxvm01:~$ k describe cm -n kube-system cluster-autoscaler-status
Name:         cluster-autoscaler-status
Namespace:    kube-system
Labels:       <none>
Annotations:  cluster-autoscaler.kubernetes.io/last-updated: 2023-09-11 10:40:02.369535271 +0000 UTC

Data
====
status:
----
Cluster-autoscaler status at 2023-09-11 10:40:02.369535271 +0000 UTC:
Cluster-wide:
  Health:      Healthy (ready=2 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=2 longUnregistered=0)
               LastProbeTime:      2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
               LastTransitionTime: 2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
  ScaleUp:     NoActivity (ready=2 registered=2)
               LastProbeTime:      2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
               LastTransitionTime: 2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
  ScaleDown:   NoCandidates (candidates=0)
               LastProbeTime:      2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
               LastTransitionTime: 2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068

NodeGroups:
  Name:        MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-s7d7t
  Health:      Healthy (ready=1 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=1 longUnregistered=0 cloudProviderTarget=1 (minSize=1, maxSize=4))
               LastProbeTime:      2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
               LastTransitionTime: 2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
  ScaleUp:     NoActivity (ready=1 cloudProviderTarget=1)
               LastProbeTime:      2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
               LastTransitionTime: 2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
  ScaleDown:   NoCandidates (candidates=0)
               LastProbeTime:      2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068
               LastTransitionTime: 2023-09-11 10:40:01.146686706 +0000 UTC m=+26.613355068



BinaryData
====

Events:  <none>
```

Thats great.

Another way to do it is to edit the cluster directly following this [KB](https://kb.vmware.com/s/article/86377) article. This [KB](https://kb.vmware.com/s/article/86377) article can also be used to change/modify existing autoscaler settings. 

 

## Test the autoscaler

In the following chapters I will test the scale up and down of my worker nodes, based on load in the cluster. My initial cluster is up and running:

```bash
NAME                                                   STATUS   ROLES           AGE     VERSION
tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   Ready    <none>          4m17s   v1.26.5+vmware.2
tkg-cluster-3-auto-ns4jx-szp69                         Ready    control-plane   8m31s   v1.26.5+vmware.2
```

One control-plane node and one worker node. 
Now I want to check the status of the cluster-scaler:

```bash
andreasm@linuxvm01:~$ k describe cm -n kube-system cluster-autoscaler-status
Name:         cluster-autoscaler-status
Namespace:    kube-system
Labels:       <none>
Annotations:  cluster-autoscaler.kubernetes.io/last-updated: 2023-09-08 13:30:12.611110965 +0000 UTC

Data
====
status:
----
Cluster-autoscaler status at 2023-09-08 13:30:12.611110965 +0000 UTC:
Cluster-wide:
  Health:      Healthy (ready=2 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=2 longUnregistered=0)
               LastProbeTime:      2023-09-08 13:30:11.394021754 +0000 UTC m=+1356.335230920
               LastTransitionTime: 2023-09-08 13:07:46.176049718 +0000 UTC m=+11.117258901
  ScaleUp:     NoActivity (ready=2 registered=2)
               LastProbeTime:      2023-09-08 13:30:11.394021754 +0000 UTC m=+1356.335230920
               LastTransitionTime: 2023-09-08 13:07:46.176049718 +0000 UTC m=+11.117258901
  ScaleDown:   NoCandidates (candidates=0)
               LastProbeTime:      2023-09-08 13:30:11.394021754 +0000 UTC m=+1356.335230920
               LastTransitionTime: 0001-01-01 00:00:00 +0000 UTC

NodeGroups:
  Name:        MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws
  Health:      Healthy (ready=1 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=1 longUnregistered=0 cloudProviderTarget=1 (minSize=1, maxSize=4))
               LastProbeTime:      2023-09-08 13:30:11.394021754 +0000 UTC m=+1356.335230920
               LastTransitionTime: 2023-09-08 13:12:44.585589045 +0000 UTC m=+309.526798282
  ScaleUp:     NoActivity (ready=1 cloudProviderTarget=1)
               LastProbeTime:      2023-09-08 13:30:11.394021754 +0000 UTC m=+1356.335230920
               LastTransitionTime: 2023-09-08 13:12:44.585589045 +0000 UTC m=+309.526798282
  ScaleDown:   NoCandidates (candidates=0)
               LastProbeTime:      2023-09-08 13:30:11.394021754 +0000 UTC m=+1356.335230920
               LastTransitionTime: 0001-01-01 00:00:00 +0000 UTC



BinaryData
====

Events:  <none>
```

### Scale-up - amount of worker nodes (horizontally)

Now I need to generate some load and see if it will do some magic scaling in the background. 

I have deployed my Yelb app again, the only missing pod is the UI pod:

```bash
NAME                              READY   STATUS    RESTARTS   AGE
redis-server-56d97cc8c-4h54n      1/1     Running   0          6m56s
yelb-appserver-65855b7ffd-j2bjt   1/1     Running   0          6m55s
yelb-db-6f78dc6f8f-rg68q          1/1     Running   0          6m56s
```

I still have my one cp node and one worker node. I will now deploy the UI pod and scale an insane amount of UI pods for the Yelb application. 

```bash
yelb-ui-5c5b8d8887-9598s          1/1     Running   0          2m35s
```

```bash
andreasm@linuxvm01:~$ k scale deployment -n yelb yelb-ui --replicas 200
deployment.apps/yelb-ui scaled
```

Lets check some status after this... A bunch of pods in pending states, waiting for a node to be scheduled on.

```bash
NAME                              READY   STATUS    RESTARTS   AGE     IP             NODE                                                   NOMINATED NODE   READINESS GATES
redis-server-56d97cc8c-4h54n      1/1     Running   0          21m     100.96.1.9     tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-appserver-65855b7ffd-j2bjt   1/1     Running   0          21m     100.96.1.11    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-db-6f78dc6f8f-rg68q          1/1     Running   0          21m     100.96.1.10    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-22v8p          1/1     Running   0          6m18s   100.96.1.53    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-2587j          0/1     Pending   0          3m49s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-2bzcg          0/1     Pending   0          3m51s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-2gncl          0/1     Pending   0          3m51s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-2gwp8          1/1     Running   0          3m53s   100.96.1.86    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-2gz7r          0/1     Pending   0          3m50s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-2jlvv          0/1     Pending   0          3m49s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-2pfgp          1/1     Running   0          6m18s   100.96.1.36    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-2prwf          0/1     Pending   0          3m50s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-2vr4f          0/1     Pending   0          3m53s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-2w2t8          0/1     Pending   0          3m49s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-2x6b7          1/1     Running   0          6m18s   100.96.1.34    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-2x726          1/1     Running   0          9m40s   100.96.1.23    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-452bx          0/1     Pending   0          3m49s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-452dd          1/1     Running   0          6m17s   100.96.1.69    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-45nmz          0/1     Pending   0          3m48s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-4kj69          1/1     Running   0          3m53s   100.96.1.109   tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-4svbf          0/1     Pending   0          3m50s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-4t6dm          0/1     Pending   0          3m50s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-4zlhw          0/1     Pending   0          3m51s   <none>         <none>                                                 <none>           <none>
yelb-ui-5c5b8d8887-55qzm          1/1     Running   0          9m40s   100.96.1.15    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-5fts4          1/1     Running   0          6m18s   100.96.1.55    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
```



The autoscaler status:

```bash
andreasm@linuxvm01:~$ k describe cm -n kube-system cluster-autoscaler-status
Name:         cluster-autoscaler-status
Namespace:    kube-system
Labels:       <none>
Annotations:  cluster-autoscaler.kubernetes.io/last-updated: 2023-09-08 14:01:43.794315378 +0000 UTC

Data
====
status:
----
Cluster-autoscaler status at 2023-09-08 14:01:43.794315378 +0000 UTC:
Cluster-wide:
  Health:      Healthy (ready=2 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=2 longUnregistered=0)
               LastProbeTime:      2023-09-08 14:01:41.380962042 +0000 UTC m=+3246.322171235
               LastTransitionTime: 2023-09-08 13:07:46.176049718 +0000 UTC m=+11.117258901
  ScaleUp:     InProgress (ready=2 registered=2)
               LastProbeTime:      2023-09-08 14:01:41.380962042 +0000 UTC m=+3246.322171235
               LastTransitionTime: 2023-09-08 14:01:41.380962042 +0000 UTC m=+3246.322171235
  ScaleDown:   NoCandidates (candidates=0)
               LastProbeTime:      2023-09-08 14:01:30.091765978 +0000 UTC m=+3235.032975159
               LastTransitionTime: 0001-01-01 00:00:00 +0000 UTC

NodeGroups:
  Name:        MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws
  Health:      Healthy (ready=1 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=1 longUnregistered=0 cloudProviderTarget=2 (minSize=1, maxSize=4))
               LastProbeTime:      2023-09-08 14:01:41.380962042 +0000 UTC m=+3246.322171235
               LastTransitionTime: 2023-09-08 13:12:44.585589045 +0000 UTC m=+309.526798282
  ScaleUp:     InProgress (ready=1 cloudProviderTarget=2)
               LastProbeTime:      2023-09-08 14:01:41.380962042 +0000 UTC m=+3246.322171235
               LastTransitionTime: 2023-09-08 14:01:41.380962042 +0000 UTC m=+3246.322171235
  ScaleDown:   NoCandidates (candidates=0)
               LastProbeTime:      2023-09-08 14:01:30.091765978 +0000 UTC m=+3235.032975159
               LastTransitionTime: 0001-01-01 00:00:00 +0000 UTC



BinaryData
====

Events:
  Type    Reason         Age   From                Message
  ----    ------         ----  ----                -------
  Normal  ScaledUpGroup  12s   cluster-autoscaler  Scale-up: setting group MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws size to 2 instead of 1 (max: 4)
  Normal  ScaledUpGroup  11s   cluster-autoscaler  Scale-up: group MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws size set to 2 instead of 1 (max: 4)
```

O yes, it has triggered a scale up. And in vCenter a new worker node is in the process:

<img src=images/image-20230908160418288.png style="width:500px" />

```bash
NAME                                                   STATUS     ROLES           AGE   VERSION
tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   Ready      <none>          55m   v1.26.5+vmware.2
tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   NotReady   <none>          10s   v1.26.5+vmware.2
tkg-cluster-3-auto-ns4jx-szp69                         Ready      control-plane   59m   v1.26.5+vmware.2
```



Lets check the pods status when the new node has been provisioned and ready.. 

The node is now ready:

```bash
NAME                                                   STATUS   ROLES           AGE    VERSION
tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   Ready    <none>          56m    v1.26.5+vmware.2
tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   Ready    <none>          101s   v1.26.5+vmware.2
tkg-cluster-3-auto-ns4jx-szp69                         Ready    control-plane   60m    v1.26.5+vmware.2
```

All my 200 UI pods are now scheduled and running across two worker nodes:

```bash
NAME                              READY   STATUS    RESTARTS   AGE   IP             NODE                                                   NOMINATED NODE   READINESS GATES
redis-server-56d97cc8c-4h54n      1/1     Running   0          30m   100.96.1.9     tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-appserver-65855b7ffd-j2bjt   1/1     Running   0          30m   100.96.1.11    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-db-6f78dc6f8f-rg68q          1/1     Running   0          30m   100.96.1.10    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-22v8p          1/1     Running   0          15m   100.96.1.53    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-2587j          1/1     Running   0          12m   100.96.2.82    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-2bzcg          1/1     Running   0          12m   100.96.2.9     tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-2gncl          1/1     Running   0          12m   100.96.2.28    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-2gwp8          1/1     Running   0          12m   100.96.1.86    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-2gz7r          1/1     Running   0          12m   100.96.2.38    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-2jlvv          1/1     Running   0          12m   100.96.2.58    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-2pfgp          1/1     Running   0          15m   100.96.1.36    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-2prwf          1/1     Running   0          12m   100.96.2.48    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-2vr4f          1/1     Running   0          12m   100.96.2.77    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-2w2t8          1/1     Running   0          12m   100.96.2.63    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-2x6b7          1/1     Running   0          15m   100.96.1.34    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-2x726          1/1     Running   0          18m   100.96.1.23    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-452bx          1/1     Running   0          12m   100.96.2.67    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
yelb-ui-5c5b8d8887-452dd          1/1     Running   0          15m   100.96.1.69    tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   <none>           <none>
yelb-ui-5c5b8d8887-45nmz          1/1     Running   0          12m   100.96.2.100   tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc   <none>           <none>
```



### Scale-down - remove un-needed worker nodes

Now that I have seen that the autoscaler is indeed scaling the amount worker nodes automatically, I will like to test whether it is also being capable of scaling down, removing unneccessary worker nodes as the load is not there any more. 
To test this I will just scale down the amount of UI pods in the Yelb application:

```bash
andreasm@linuxvm01:~$ k scale deployment -n yelb yelb-ui --replicas 2
deployment.apps/yelb-ui scaled
andreasm@linuxvm01:~$ k get pods -n yelb
NAME                              READY   STATUS        RESTARTS   AGE
redis-server-56d97cc8c-4h54n      1/1     Running       0          32m
yelb-appserver-65855b7ffd-j2bjt   1/1     Running       0          32m
yelb-db-6f78dc6f8f-rg68q          1/1     Running       0          32m
yelb-ui-5c5b8d8887-22v8p          1/1     Terminating   0          17m
yelb-ui-5c5b8d8887-2587j          1/1     Terminating   0          14m
yelb-ui-5c5b8d8887-2bzcg          1/1     Terminating   0          14m
yelb-ui-5c5b8d8887-2gncl          1/1     Terminating   0          14m
yelb-ui-5c5b8d8887-2gwp8          1/1     Terminating   0          14m
yelb-ui-5c5b8d8887-2gz7r          1/1     Terminating   0          14m
yelb-ui-5c5b8d8887-2jlvv          1/1     Terminating   0          14m
yelb-ui-5c5b8d8887-2pfgp          1/1     Terminating   0          17m
yelb-ui-5c5b8d8887-2prwf          1/1     Terminating   0          14m
yelb-ui-5c5b8d8887-2vr4f          1/1     Terminating   0          14m
yelb-ui-5c5b8d8887-2w2t8          1/1     Terminating   0          14m
```

When all the unnecessary pods are gone, I need to monitor the removal of the worker nodes. It may take some minutes

The Yelb application is back to "normal"

```bash
NAME                              READY   STATUS    RESTARTS   AGE
redis-server-56d97cc8c-4h54n      1/1     Running   0          33m
yelb-appserver-65855b7ffd-j2bjt   1/1     Running   0          33m
yelb-db-6f78dc6f8f-rg68q          1/1     Running   0          33m
yelb-ui-5c5b8d8887-dxlth          1/1     Running   0          21m
yelb-ui-5c5b8d8887-gv829          1/1     Running   0          21m
```

Checking the autoscaler status now, it has identified a candidate to scale down. But as I have sat this AUTOSCALER_SCALE_DOWN_DELAY_AFTER_ADD: "10m" I will need to wait 10 minutes after LastTransitionTime ...

```bash
Name:         cluster-autoscaler-status
Namespace:    kube-system
Labels:       <none>
Annotations:  cluster-autoscaler.kubernetes.io/last-updated: 2023-09-08 14:19:46.985695728 +0000 UTC

Data
====
status:
----
Cluster-autoscaler status at 2023-09-08 14:19:46.985695728 +0000 UTC:
Cluster-wide:
  Health:      Healthy (ready=3 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=3 longUnregistered=0)
               LastProbeTime:      2023-09-08 14:19:45.772876369 +0000 UTC m=+4330.714085660
               LastTransitionTime: 2023-09-08 13:07:46.176049718 +0000 UTC m=+11.117258901
  ScaleUp:     NoActivity (ready=3 registered=3)
               LastProbeTime:      2023-09-08 14:19:45.772876369 +0000 UTC m=+4330.714085660
               LastTransitionTime: 2023-09-08 14:08:21.539629262 +0000 UTC m=+3646.480838810
  ScaleDown:   CandidatesPresent (candidates=1)
               LastProbeTime:      2023-09-08 14:19:45.772876369 +0000 UTC m=+4330.714085660
               LastTransitionTime: 2023-09-08 14:18:26.989571984 +0000 UTC m=+4251.930781291

NodeGroups:
  Name:        MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws
  Health:      Healthy (ready=2 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=2 longUnregistered=0 cloudProviderTarget=2 (minSize=1, maxSize=4))
               LastProbeTime:      2023-09-08 14:19:45.772876369 +0000 UTC m=+4330.714085660
               LastTransitionTime: 2023-09-08 13:12:44.585589045 +0000 UTC m=+309.526798282
  ScaleUp:     NoActivity (ready=2 cloudProviderTarget=2)
               LastProbeTime:      2023-09-08 14:19:45.772876369 +0000 UTC m=+4330.714085660
               LastTransitionTime: 2023-09-08 14:08:21.539629262 +0000 UTC m=+3646.480838810
  ScaleDown:   CandidatesPresent (candidates=1)
               LastProbeTime:      2023-09-08 14:19:45.772876369 +0000 UTC m=+4330.714085660
               LastTransitionTime: 2023-09-08 14:18:26.989571984 +0000 UTC m=+4251.930781291



BinaryData
====

Events:
  Type    Reason         Age   From                Message
  ----    ------         ----  ----                -------
  Normal  ScaledUpGroup  18m   cluster-autoscaler  Scale-up: setting group MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws size to 2 instead of 1 (max: 4)
  Normal  ScaledUpGroup  18m   cluster-autoscaler  Scale-up: group MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws size set to 2 instead of 1 (max: 4)
```



After the 10 minutes:

```bash
NAME                                                   STATUS   ROLES           AGE   VERSION
tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-dcp2q   Ready    <none>          77m   v1.26.5+vmware.2
tkg-cluster-3-auto-ns4jx-szp69                         Ready    control-plane   81m   v1.26.5+vmware.2
```

Back to two nodes again, and the VM has been deleted from vCenter.

The autoscaler status:

```bash
Name:         cluster-autoscaler-status
Namespace:    kube-system
Labels:       <none>
Annotations:  cluster-autoscaler.kubernetes.io/last-updated: 2023-09-08 14:29:32.692769073 +0000 UTC

Data
====
status:
----
Cluster-autoscaler status at 2023-09-08 14:29:32.692769073 +0000 UTC:
Cluster-wide:
  Health:      Healthy (ready=2 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=2 longUnregistered=0)
               LastProbeTime:      2023-09-08 14:29:31.482497258 +0000 UTC m=+4916.423706440
               LastTransitionTime: 2023-09-08 13:07:46.176049718 +0000 UTC m=+11.117258901
  ScaleUp:     NoActivity (ready=2 registered=2)
               LastProbeTime:      2023-09-08 14:29:31.482497258 +0000 UTC m=+4916.423706440
               LastTransitionTime: 2023-09-08 14:08:21.539629262 +0000 UTC m=+3646.480838810
  ScaleDown:   NoCandidates (candidates=0)
               LastProbeTime:      2023-09-08 14:29:31.482497258 +0000 UTC m=+4916.423706440
               LastTransitionTime: 2023-09-08 14:28:46.471388976 +0000 UTC m=+4871.412598145

NodeGroups:
  Name:        MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws
  Health:      Healthy (ready=1 unready=0 (resourceUnready=0) notStarted=0 longNotStarted=0 registered=1 longUnregistered=0 cloudProviderTarget=1 (minSize=1, maxSize=4))
               LastProbeTime:      2023-09-08 14:29:31.482497258 +0000 UTC m=+4916.423706440
               LastTransitionTime: 2023-09-08 13:12:44.585589045 +0000 UTC m=+309.526798282
  ScaleUp:     NoActivity (ready=1 cloudProviderTarget=1)
               LastProbeTime:      2023-09-08 14:29:31.482497258 +0000 UTC m=+4916.423706440
               LastTransitionTime: 2023-09-08 14:08:21.539629262 +0000 UTC m=+3646.480838810
  ScaleDown:   NoCandidates (candidates=0)
               LastProbeTime:      2023-09-08 14:29:31.482497258 +0000 UTC m=+4916.423706440
               LastTransitionTime: 2023-09-08 14:28:46.471388976 +0000 UTC m=+4871.412598145



BinaryData
====

Events:
  Type    Reason          Age   From                Message
  ----    ------          ----  ----                -------
  Normal  ScaledUpGroup   27m   cluster-autoscaler  Scale-up: setting group MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws size to 2 instead of 1 (max: 4)
  Normal  ScaledUpGroup   27m   cluster-autoscaler  Scale-up: group MachineDeployment/tkg-ns-3/tkg-cluster-3-auto-md-0-fhrws size set to 2 instead of 1 (max: 4)
  Normal  ScaleDownEmpty  61s   cluster-autoscaler  Scale-down: removing empty node "tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc"
  Normal  ScaleDownEmpty  55s   cluster-autoscaler  Scale-down: empty node tkg-cluster-3-auto-md-0-fhrws-757648f59cxq4hlz-q6fqc removed
```

This works really well. 
Quite straight forward to enable and a really nice feature to have. 
And this also concludes this post. 



