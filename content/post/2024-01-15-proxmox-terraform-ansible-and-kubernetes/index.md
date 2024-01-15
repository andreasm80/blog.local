---
author: "Andreas M"
title: "Proxmox with OpenTofu Ansible and Kubernetes"
date: 2024-01-15T14:15:19+01:00 
description: "Automating with Terraform, Ansible on Proxmox"
draft: false 
toc: true
#featureimage: ""
thumbnail: "/images/proxmox.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Kubernetes
  - Automation
tags:
  - kubernetes
  - proxmox
  - ansible
  - terraform
  - opentofu
  - kubespray
summary: In this post I will quickly go through how I made use of OpenTofu to provision VMs on my Proxmox cluster and Ansible using Kubespray to deploy my Kubernetes clusters on demand.
comment: false # Disable comment if false.
---



# I need a Kubernetes cluster, again

I am using a lot of my spare time playing around with my lab exploring different topics. Very much of that time again is spent with Kubernetes. So many times have I deployed a new Kubernetes cluster, then after some time decommissioned it again. They way I have typically done it is using a Ubuntu template I have created, cloned it, manually adjusted all clones as needed, then manually installed Kubernetes. This takes a lot of times overall and it also stops me doing certain tasks as sometimes I just think nah.. not again. Maybe another day and I do something else instead. Now has the time come to automate these tasks so I can look forward to everytime I need a new Kubernetes cluster.

I have been running Home Assistant for many years, there I have a bunch of automations automating all kinds of things in my home which just makes my everyday life a bit happier. Most of these automations just work in the background doing their stuff as a good automation should. Automating my lab deployments is something I have been thinking of getting into several times, and now I decided to get this show started. So, as usual, a lot of tinkering, trial and error until I managed to get something working the way I wanted. Probably room for improvement in several areas, that is something I will most likely use my time on post this blog post also. Speaking of blog post, after using some time on this I had to create a blog post on it. My goal later on is a fully automated lab from VM creation, Kubernetes runtime, and applications. And when they are decommisioned I can easily spin up everything with preserving persistent data etc. Lets see. 

For now, this post will cover what I have done and configured so far to be able to automatically deploy the VMs for my Kubernetes clusters then the provisioning of Kubernetes itself. 

## My lab

My lab consists of two fairly spec'ed servers with a bunch of CPU cores, a lot of RAM, and a decent amount of SSDs. Networkingwise they are using 10GB ethernet. When it comes to power usage they are kind of friendly to my electricity bill with my "required" vms running on them, but can potentially ruin that if I throw a lot of stuff at them to chew on. 

<img src=images/image-20240115152236095.png style="width:400px" />



*The total power usage above includes my switch, UPS and some other small devices. So its not that bad considering how much I can get out of it.* 

But with automation I can easily spin up some resources to be consumed for a certain period and delete again if not needed. My required VMs, that are always on, are things like Bind dns servers, PfSense, Frigate, DCS server, a couple of linux "mgmt" vms,  Home Assistant, a couple of Kubernetes clusters hosting my Unifi controller, Traefik Proxy etc.

For the virtualization layer on my two servers I am using Proxmox, one of the reason is that it did support PCI passthrough of my Coral TPU. I have been running Proxmox for many years and I find it to be a very decent alternative. It does what I want it to do and Proxmox has a great community!

Proxmox has been configured with these two servers as a cluster. I have not configured any VMs in HA, but with a Proxmox cluster I can easily migrate VMs between the hosts, even without shared storage, and single web-ui to manage both servers. To be "quorate" I have a little cute RPi3 with its beefy 32 GB SD card, 2GB RAM and 1GB ethernet as a [Qdevice](https://pve.proxmox.com/wiki/Cluster_Manager#_corosync_external_vote_support)

On that note, one does not necessarily have them in a cluster to do vm migration. I recently moved a bunch of VMs over two these two new servers and it was easy peasy using this command:

```bash
qm remote-migrate <src vm_id> <dst vm_id> 'apitoken=PVEAPIToken=root@pam!migrate=<token>,host=<dst-host-ip>,fingerprint=<thumprint>' --target-bridge vmbr0 --target-storage 'raid10-node01' --online
```

I found this with the great help of the Proxmox community [here](https://forum.proxmox.com/threads/framework-for-remote-migration-to-cluster-external-proxmox-ve-hosts.118444/page-2) 

Both Proxmox servers have their own local ZFS storage. In both of them I have created a dedicated zfs pool with identical name which I use for zfs replication for some of the more "critical" VMs, and  as a bonus it also reduces the migration time drastically for these VMs when I move them between my servers. The "cluster" network (vmbr1) is directly connected 2x 10GB ethernet (not through my physical switch). The other 2x 10GB interfaces are connected to my switch for all my other network needs like VM network (vmbr0) and Proxmox management. 

Throughout this post I will be using a dedicated linux vm for all my commands, interactions. So every time I install something, it is on this linux vm. 

Enough of the intro, get on with the automation part you were supposed to write about. Got it. 

## Provision VMs in Proxmox using OpenTofu

Terraform is something I have been involved in many times in my professional work, but never had the chance to actually use it myself other than know about it, and how the solutions I work with can work together with Terraform. I did notice even the Proxmox community had several post around using Terraform, so I decided to just go with Terraform. I already knew that HashiCorp had [announced](https://www.hashicorp.com/license-faq) their change of Terraform license from MPL to BSL and that [OpenTofu](https://opentofu.org/) is an OpenSource fork of Terraform. So instead of basing my automations using Terraform, I will be using OpenTofu. Read more about OpenTofu [here](https://opentofu.org/). For now OpenTofu is Terraform "compatible" and uses Terraform registries, so providers etc for Terraform works with OpenTofu. 

To be able to use OpenTofu with Proxmox I need a provider that can use the Proxmox API. I did some quick research on the different options out there and landed on this provider: [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox). Seems very active and are recently updated (according to the git repo [here](https://github.com/bpg/terraform-provider-proxmox))

To get started with OpenTofu there are some preparations do be done. Lets start with these

### Install OpenTofu

To get started with OpenTofu I deployed it on my linux machine using Snap, but several other alternatives is available se more here on the official OpenTofu [docs](https://opentofu.org/docs/intro/install/snap) page.

```bash
sudo snap install --classic opentofu
```

Now OpenTofu is installed and I can start using it. I also installed the bash autocompletion like this:

```bash
tofu -install-autocomplete # restart shell session...
```

 I decided to create a dedicated folder for mu "projects" to live in so have created a folder in my  home folder called *proxmox" where I have different subfolders depending on certain tasks or resources I will use OpenTofu for.

### OpenTofu Proxmox provider



