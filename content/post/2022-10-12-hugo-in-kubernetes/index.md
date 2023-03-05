---
author: "Andreas M"
title: "Hugo in Kubernetes"
date: 2022-10-12T08:28:23+02:00 # Date of post creation.
description: "How I run Hugo in Kubernetes" # Description used for search engine.
draft: false # Sets whether to render this page. Draft of true will not be rendered.
featureImage: "/images/hugo_scaled.png"
thumbnail: "/images/hugo1.png"
toc: true
categories:
  - Kubernetes
  - Blog
  - hugo
tags:
  - hugo
  - static-content-generator
  - docker
  - kubernetes


comment: false # Disable comment if false.
---

This blog post will cover how *I* wanted to deploy Hugo to host my blog-page. 

## Preparations 

To achieve what I wanted, deploy an highly available Hugo hosted blog page, I decided to run Hugo in Kubernetes. 
For that I needed 

* Kubernetes cluster, obviously, consisting of several workers for the the "hugo" pods to run on (already covered [here](https://yikes.guzware.net/2020/10/08/nsx-advanced-loadbalancer-with-antrea-on-native-k8s/#prepare-the-worker-and-master-nodes).
*  Persistent storage (NFS in my case, already covered [here](https://yikes.guzware.net/2021/07/12/kubernetes-persistent-volumes-with-nfs/)) 
* An Ingress controller (already covered [here](https://yikes.guzware.net/2021/07/11/k8s-ingress-with-nsx-advanced-load-balancer/)) 
* A docker image with Hugo, nginx and go (will be covered here)
* Docker installed so you can build the image
* A place to host the docker image (Docker hub or Harbor registry will be covered [here](https://yikes.guzware.net/2022/10/13/vmware-harbor-registry/))



## Create the Docker image

Before I can deploy Hugo I need to create an Docker image that contains the necessary bits. I have already created the `Dockerfile` here:

```bash
#Install the container's OS.
FROM ubuntu:latest as HUGOINSTALL

# Install Hugo.
RUN apt-get update -y
RUN apt-get install wget git ca-certificates golang -y
RUN wget https://github.com/gohugoio/hugo/releases/download/v0.104.3/hugo_extended_0.104.3_Linux-64bit.tar.gz && \
    tar -xvzf hugo_extended_0.104.3_Linux-64bit.tar.gz  && \
    chmod +x hugo && \
    mv hugo /usr/local/bin/hugo && \
    rm -rf hugo_extended_0.104.3_Linux-64bit.tar.gz
# Copy the contents of the current working directory to the hugo-site
# directory. The directory will be created if it doesn't exist.
COPY . /hugo-site

# Use Hugo to build the static site files.
RUN hugo -v --source=/hugo-site --destination=/hugo-site/public

# Install NGINX and deactivate NGINX's default index.html file.
# Move the static site files to NGINX's html directory.
# This directory is where the static site files will be served from by NGINX.
FROM nginx:stable-alpine
RUN mv /usr/share/nginx/html/index.html /usr/share/nginx/html/old-index.html
COPY --from=HUGOINSTALL /hugo-site/public/ /usr/share/nginx/html/

# The container will listen on port 80 using the TCP protocol.
EXPOSE 80

```

*Credits for the Dockerfile as it was initially taken from [here](https://www.linode.com/docs/guides/deploy-container-image-to-kubernetes/#create-the-dockerfile)*. 
I have updated it, and done some modifications to it. 

Before building the image with docker, install docker by following this [guide](https://docs.docker.com/engine/install/ubuntu/).

### Build the docker image

I need to place myself in the same directory as my Dockerfile and execute the following command (Replace `"name-you-want-to-give-the-image:<tag>"` with something like *`"hugo-image:v1"`*):

```bash
docker build -t name-you-want-to-give-the-image:<tag> .  #Note the "."  important
```

Now the image will be built and hosted locally on my "build machine".

If anything goes well it should be listed here:

```bash
$ docker images
REPOSITORY                            TAG             IMAGE ID       CREATED        SIZE
hugo-image                            v1              d43ee98c766a   10 secs ago    70MB
nginx                                 stable-alpine   5685937b6bc1   7 days ago     23.5MB
ubuntu                                latest          216c552ea5ba   9 days ago     77.8MB

```

#### Place the image somewhere easily accessible 

Now that I have my image I need to make sure it is easily accessible for my Kubernetes workers so they can download the image and deploy it. For that I can use the local docker registry pr control node and worker node. Meaning I need to load the image into all workers and control plane nodes. Not so smooth way to to do it. This is the approach for such a method:

```bash
docker save -o <path for generated tar file> <image name> #needs to be done on the machine you built the image. Example: docker save -o /home/username/hugo-image.v1.tar hugo-image:v1
```

This will "download" the image from the local docker repository and create tar file. This tar file needs to be copied to all my workers and additional control plane nodes with scp or other methods I find suitable. 
When that is done I need to upload the tar to each of their local docker repository with the following command:

```bash
docker -i load /home/username/hugo-image.v1.tar
```

It is ok to know about this process if you are in non-internet environments etc, but even in non-internet environment we can do this with a private registry. And thats where Harbor can come to the rescue [link](https://yikes.guzware.net/2022/10/13/vmware-harbor-registry/).

With Harbor I can have all my images hosted centrally but dont need access to the internet as it is hosted in my own environment.  
I could also use Docker [hub](https://hub.docker.com/). Create an account there, and use it as my repository. I prefer the Harbor registry, as it provides many [features](https://yikes.guzware.net/2022/10/13/vmware-harbor-registry/). The continuation of this post will use Harbor, the procedure to upload/download images is the same process as with Docker hub but you log in to your own Harbor registry instead of Docker hub.  

Uploading my newly created image is done like this:

```bash
docker login registry.example.com #FQDN to my selfhosted Harbor registry, and the credentials for an account I have created there. 
docker tag hugo-image:v1 https://registry.example.com/hugo/hugo-image:v1 #"/hugo/" name of project in Harbor
docker push registry.example.com/hugo/hugo-image:v1 #upload it
```

Thats it. Now I can go ahead and create my deployment.yaml definition file in my Kubernetes cluster, point it to my image hosted at my local Harbor registry (e.g registry.example.com/hugo/hugo-image:v1). But let me go through how I created my Hugo deployment in Kubernetes, as I am so close to see my newly image in action :smile: (Will it even work). 

## Deploy Hugo in Kubernetes

To run my Hugo image in Kubernetes the way I wanted I need to define a [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) (remember I wanted a highly available Hugo deployment, meaning more than one pod and the ability to scale up/down). The first section of my hugo-deployment.yaml definition file looks like this:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hugo-site
  namespace: hugo-site
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hugo-site
      tier: web
  template:
    metadata:
      labels:
        app: hugo-site
        tier: web
    spec:
      containers:
      - image: registry.example.com/hugo/hugo-image:v1
        name: hugo-site
        imagePullPolicy: Always
        ports:
        - containerPort: 80
        name: hugo-site
        volumeMounts:
        - name: persistent-storage
          mountPath: /usr/share/nginx/html/
      volumes:
      - name: persistent-storage
        persistentVolumeClaim:
          claimName: hugo-pv-claim
```

In the above I define name of deployment, specify number of pods with the replica specification, labels, point to my image hosted in Harbor and then what the container mountPath and the peristent volume claim. mountPath is inside the container, and the files/folders mounted is read from the content it sees in the persistent volume claim "hugo-pv-claim". Thats where Hugo will find the content of the Public folder (after the content has been generated).

I also needed to define a Service so I can reach/expose the containers contents (webpage) on port 80. This is done with this specification:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hugo-service
  namespace: hugo-site
  labels:
    svc: hugo-service
spec:
  selector:
    app: hugo-site
    tier: web
  ports:
    - port: 80
```

Can be saved as a separate "service.yaml" file or pasted into one yaml file. 
But instead of pointing to my workers IP addresses to read the content each time I wanted to expose it with an Ingress by using AKO and Avi LoadBalancer. This is how I done that:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hugo-ingress
  namespace: hugo-site
  labels:
    app: hugo-ingress
  annotations:
    ako.vmware.com/enable-tls: "true"
spec:
  ingressClassName: avi-lb
  rules:
    - host: yikes.guzware.net
      http:
        paths:
        - pathType: Prefix
          path: /
          backend:
            service:
              name: hugo-service
              port:
                number: 80

```

 I define my ingressClassName, the hostname for my Ingress controller to listen for requests on and the Service the Ingress should route all the request to yikes.guzware.net to, which is my hugo-service defined earlier. Could also be saved as a separe yaml file. I have chosen to put all three "kinds" in one yaml file. Which then looks like this:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hugo-site
  namespace: hugo-site
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hugo-site
      tier: web
  template:
    metadata:
      labels:
        app: hugo-site
        tier: web
    spec:
      containers:
      - image: registry.example.com/hugo/hugo-image:v1
        name: hugo-site
        imagePullPolicy: Always
        ports:
        - containerPort: 80
        name: hugo-site
        volumeMounts:
        - name: persistent-storage
          mountPath: /usr/share/nginx/html/
      volumes:
      - name: persistent-storage
        persistentVolumeClaim:
          claimName: hugo-pv-claim
---
apiVersion: v1
kind: Service
metadata:
  name: hugo-service
  namespace: hugo-site
  labels:
    svc: hugo-service
spec:
  selector:
    app: hugo-site
    tier: web
  ports:
    - port: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hugo-ingress
  namespace: hugo-site
  labels:
    app: hugo-ingress
  annotations:
    ako.vmware.com/enable-tls: "true"
spec:
  ingressClassName: avi-lb
  rules:
    - host: yikes.guzware.net
      http:
        paths:
        - pathType: Prefix
          path: /
          backend:
            service:
              name: hugo-service
              port:
                number: 80


```

Now before my Deployment is ready to be applied I need to create the namespace I have defined in the yaml file above:
`kubectl create ns hugo-site`.

Now when that is done its time to apply my hugo deployment.
`kubectl apply -f hugo-deployment.yaml`

I want to check the state of the pods:

```bash
$ kubectl get pod -n hugo-site 
NAME                         READY   STATUS    RESTARTS   AGE
hugo-site-7f95b4644c-5gtld   1/1     Running   0          10s
hugo-site-7f95b4644c-fnrh5   1/1     Running   0          10s
hugo-site-7f95b4644c-hc4gw   1/1     Running   0          10s

```

Ok, so far so good. What about my deployment:

```bash
$ kubectl get deployments.apps -n hugo-site 
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
hugo-site   3/3     3            3           35s

```

Great news. Lets check the Service,  Ingress and persistent volume claim.

Service:

```bash
$ kubectl get service -n hugo-site 
NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
hugo-service   ClusterIP   10.99.25.113   <none>        80/TCP    46s
```

Ingress:

```bash
$ kubectl get ingress -n hugo-site 
NAME           CLASS    HOSTS               ADDRESS         PORTS   AGE
hugo-ingress   avi-lb   yikes.guzware.net   x.x.x.x         80      54s

```

PVC:

```bash
NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
hugo-pv-claim   Bound    pvc-b2395264-4500-4d74-8a5c-8d79f9df8d63   10Gi       RWO            nfs-client     59s
```

Well that looks promising.
Will I be able to access my hugo page on yikes.guzware.net ... well yes, otherwise you wouldnt read this.. :rofl:

## Creating and updating content

A blog page without content is not so interesting. So just some quick comments on how I create content, and update them.

I use [Typora](https://typora.io/) creating and editing my *.md files. While working with the post (such as now) I run hugo in "server-mode" whith this command: `hugo server`. If I run this command on of my linux virtual machines through SSH I want to reach the server from my laptop so I add the parameter `--bind=ip-of-linux-vm` and I can access the page from my laptop on the ip of the linux VM and port 1313. When I am done with the article/post for the day I generated the web-page with the command `hugo -D -v`.
The updated content of my public folder after I have generated the page is mirrored to the NFS path that is used in my PVC shown above and my containers picks up the updated content instantly. 
Thats how I do, it works and I find it easy to maintain and operate. And, if one of my workers fails, I have more pods still available on the remaining workers. If a pod fails Kubernetes will just take care of that for me as I have declared a set of pods(replicas) that should run. If I run my Kubernetes environment in Tanzu and one of my workers fails, that will also be automatically taken care of. 

