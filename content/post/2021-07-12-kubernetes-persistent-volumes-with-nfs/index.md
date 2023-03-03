---
title: "Kubernetes Persistent Volumes with NFS"
date: "2021-07-12"
thumbnail: "/images/k8sfavicon.png"
toc: true
categories: 
  - "kubernetes"
tags: 
  - "configurations"
---

## Use NFS for your PVC needs

If you are running vShere with Tanzu, TKG on vSphere or are using vSphere as your hypervisor for your worker-nodes you have the option to use the vSphere CSI plugin [here](https://docs.vmware.com/en/VMware-vSphere-Container-Storage-Plug-in/index.html). In Tanzu this is automatically configured and enabled. But if you are not so privileged to have vSphere as your foundation for your environment one have to look at other options. Thats where NFS comes in. To use NFS for your persistent volumes is quite easy to enable in your environment, but there are some pre-reqs that needs to be placed on your workers (including control plane nodes). I will go through the installation steps below.

### Pre-reqs

A NFS server available, already configured with shares exported. This could be running on any Linux machine in your environment that has sufficient storage to cover your storage needs for your PVCs. Or any other platform that can export NFS shares.

### Install and configure

*This post is based on Ubuntu 20.04 as operating system for all the workers.* 

The first package that needs to be in place is the *nfs-common* package in Ubuntu. This is installed with the below command, and on all your workers (control-plane and workers):

```bash
sudo apt install nfs-common -y
```

Now that *nfs-common* is installed on all workers we are ready deploy the *NFS subdir external provisioner* [link](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner). *The below commands is done from your controlplane nodes, if not stated otherwise.* 
I prefer to use Helm. If you dont have Helm installed head over [here](https://helm.sh/docs/intro/install/) for how to install Helm.
With Helm in place execute the following command to add the NFS Subdir External Provisioner chart:

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
```

Then we need to install the NFS provisioner like this:

```bash
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=x.x.x.x \
    --set nfs.path=/exported/path
```

Its quite self-explanatory but I will quickly to through it. `--set nfs.server=x.x.x.x \` needs to be updated with the IP address to your NFS server.
`--set nfs.path=/exported/path` needs to be updated to reflect the path your NFS server exports. 

Thats it actually, you know have a storageclass available in your cluster using NFS. The default values for the storageclass deployed without editing the NFS subdir external provisioner helm values looks like this:

```bash
$kubectl get storageclasses.storage.k8s.io
NAME                   PROVISIONER                                                         RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
nfs-client             cluster.local/nfs-subdir-external-provisioner                       Delete          Immediate              true                   51d

```

### Values, additional storageclasses

If you want to change the default values get the values file, edit it before you deploy the NFS provisioner or get the file, edit it and update your deployment with `helm upgrade`
To grab the values file run this command:

```bash
helm show values nfs-subdir-external-provisioner/nfs-subdir-external-provisioner > nfs-prov-values.yaml
```

If you want to add additional storageclasses, say with accessmode to RWX, you deploy NFS provisioner with a value file that has the settings you want. Remember to change the class name.

```bash
  name: XXXXX

  # Allow volume to be expanded dynamically
  allowVolumeExpansion: true

  # Method used to reclaim an obsoleted volume
  reclaimPolicy: Delete

  # When set to false your PVs will not be archived by the provisioner upon deletion of the PVC.
  archiveOnDelete: true

  # If it exists and has 'delete' value, delete the directory. If it exists and has 'retain' value, save the directory.
  # Overrides archiveOnDelete.
  # Ignored if value not set.
  onDelete:

  # Specifies a template for creating a directory path via PVC metadata's such as labels, annotations, name or namespace.
  # Ignored if value not set.
  pathPattern:

  # Set access mode - ReadWriteOnce, ReadOnlyMany or ReadWriteMany
  accessModes: XXXXXXX

```

Above is a snippet from the values file.



#### Deploying pods with special privileges

If you need to deploy pods with special privileges, often mysql containers, you need to prepare your NFS server and filesystem permission for that. Otherwise they will not be able to write correctly to their PV when they are deployed.  The example below is a mysql container that needs to create its own permission on the filesystem it writes to:

```yaml
            spec:
      securityContext:
        runAsUser: 999
        fsGroup: 999
```

So what I did to solve this is the following:
I changed my NFS export to look like this on my NFS server: `/path/to/share -alldirs -maproot="root":"wheel"`
Then I need to update the permissions on the NFS server filesystem with these commands and permissions: 

```bash
$chown nobody:nogroup /shared/folder
$chmod 777 /shared/folder
```

