---
author: "Andreas M"
title: "VMware Harbor Registry"
date: 2022-10-13T21:56:15+02:00 
description: "Deploy VMware Harbor registry in Kubernetes"
draft: false 
toc: true
#featureimage: ""
#thumbnail: "/images/harbor-icon-color.png" 
toc: true
categories:
  - Harbor
  - Kubernetes
  - Helm
  - Docker
tags:
  - harbor
  - registry

comment: false # Disable comment if false.
---

This post will briefly go through how to deploy (using Helm), configure and use VMware Harbor registry in Kubernetes. 

## Quick introduction to Harbor

> Harbor is an open source registry that secures artifacts with policies and role-based access control, ensures images are scanned and free from vulnerabilities, and signs images as trusted. Harbor, a CNCF Graduated project, delivers compliance, performance, and interoperability to help you consistently and securely manage artifacts across cloud native compute platforms like Kubernetes and Docker. [link](https://goharbor.io/)

I use myself Harbor in many of my own projects, including the images I make for my Hugo blogsite (this).

## Deploy Harbor with Helm

Add helm chart: 

```bash
helm repo add harbor https://helm.goharbor.io
helm fetch harbor/harbor --untar
```

Before you perform the default helm install of Harbor you want to grab the helm values for the Harbor charts so you can edit some settings to match your environment:

```bash
helm show values harbor/harbor > harbor.values.yaml
```

The default values you get from the above command includes all available parameter which can be a bit daunting to go through. In the values file I use I have only picked the parameters I needed to set, here:

```yaml
expose:
  type: ingress
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: "harbor-tls-prod" # certificates you have created with Cert-Manager
      notarySecretName: "notary-tls-prod" # certificates you have created with Cert-Manager
  ingress:
    hosts:
      core: registry.example.com
      notary: notary.example.com
    annotations:
      kubernetes.io/ingress.class: "avi-lb"
      ako.vmware.com/enable-tls: "true"
externalURL: https://registry.example.com
harborAdminPassword: "PASSWORD"
persistence:
  enabled: true
  # Setting it to "keep" to avoid removing PVCs during a helm delete
  # operation. Leaving it empty will delete PVCs after the chart deleted
  # (this does not apply for PVCs that are created for internal database
  # and redis components, i.e. they are never deleted automatically)
  resourcePolicy: "keep"
  persistentVolumeClaim:
    registry:
      # Use the existing PVC which must be created manually before bound,
      # and specify the "subPath" if the PVC is shared with other components
      existingClaim: ""
      # Specify the "storageClass" used to provision the volume. Or the default
      # StorageClass will be used (the default).
      # Set it to "-" to disable dynamic provisioning
      storageClass: "nfs-client"
      subPath: ""
      accessMode: ReadWriteOnce
      size: 50Gi
      annotations: {}
    database:
      existingClaim: ""
      storageClass: "nfs-client"
      subPath: "postgres-storage"
      accessMode: ReadWriteOnce
      size: 1Gi
      annotations: {}

portal:
  tls:
    existingSecret: harbor-tls-prod
```

When you have edited the values file its time to install:

```bash
helm install -f harbor.values.yaml harbor-deployment harbor/harbor -n harbor
```

Explanation:  "-f"  is telling helm to read the values from the specified file after, then the name of your helm installation (here harbor-deployment) then the helm repo and finally the namespace you want it deployed in. 
A couple of seconds later you should be able to log in to the GUI of Harbor through your webbrowser if everything has been set up right, Ingress, pvc, secrets. 

### Certificate

You can either use Cert-manager as explained [here](https://blog.andreasm.io/2022/10/11/cert-manager-and-letsencrypt/) or bring your own ca signed certificates. 

## Harbor GUI

To log in to the GUI for the first time open your browser and point it to the *externalURL* you gave it in your values file and the corresponding  *harborAdminPassword* you defined. From there on you create users and projects and start exploring Harbor.

<img src=images/image-20221016215923365.png style="width:500px" />

Users:
<img src=images/image-20221016220240872.png style="width:1000px" />

Projects:
<img src=images/image-20221013220752264.png style="width:900px" />



## Docker images

To push your images to Harbor execute the following commands:

```bash
docker login registry.example.com #log in with the user/password you have created in the GUI
docker tag image-name:tag registry.example.com/project/image-name:tag
docker push registry.example.com/project/image-name:tag
```

