---
author: "Andreas M"
title: "NeuVector by SUSE"
date: 2024-05-13T12:42:04+02:00 
description: "A deep dive in NeuVector"
draft: false 
toc: true
#featureimage: ""
thumbnail: "/images/NeuVector_logo.svg" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Kubernetes
  - Security
  - Compliance
  - SUSE
  - NeuVector
tags:
  - kubernetes
  - security
  - compliance
  - neuvector
  - suse

summary: In this post I will explore and deep dive into NeuVector by SUSE
comment: false # Disable comment if false.
---



# NeuVector

After doing my post on Rancher [here](https://blog.andreasm.io/2024/05/05/taking-rancher-by-suse-for-a-spin/) I wrote that I would do a dedicated post on NeuVector, among other topics. So this post will be a more deep dive post covering some of the features in NeuVector and how to configure and use them. 

I have been working a lot with Kubernetes Network policies by utilizing the CNIs built-in network security features, especially Antrea Native Policies. I have also covered most of that in earlier posts in my blog. This time it will be a bit different angle and approach.

Using Antrea Native Policies or Kubernetes Network policies is more on the network layer than on the application layer of a pod in a Kubernetes infrastructure. In this post I will focus more on the application layer by using the NeuVector. In this post both Antrea Native Policies and NeuVector policies/rules will be used as combining the two will contribute to a more secure platform. It is again not meant to be a comprehensive post covering best practices but may open up for some ideas and thinking around Kubernetes security. 

## NeuVector Architecture

From the official NeuVector documentation [page](https://open-docs.neuvector.com/basics/overview) they already provide a diagram of the NeuVector Architecture:

![neuvector-architecture](images/architecture-1222ec809413f923d46203c6b0c5f770.png)

Short explanations of the components:

> **Controller**
>
> The Controller manages the NeuVector Enforcer container cluster. It also provides REST APIs for the management console. Although typical test deployments have one Controller, multiple Controllers in a high-availability configuration is recommended. 3 controllers is the default in the Kubernetes Production deployment sample yaml.
>
> **Enforcer**
>
> The Enforcer is a lightweight container that enforces the security policies. One enforcer should be deployed on each node (host), e.g. as a Daemon set.
>
> **Manager**
>
> The Manager is a stateless container that provides a web-UI (HTTPS only) console for users to manage the NeuVector security solution. More than one Manager container can be deployed as necessary.
>
> **All-in-One**
>
> The All-in-One container includes a Controller, an Enforcer and a Manager in one package. It's useful for easy installation in single-node or small-scale deployments.
>
> **Scanner**
>
> The Scanner is a container which performs the vulnerability and compliance scanning for images, containers and nodes. It is typically deployed as a replicaset and can be scaled up to as many parallel scanners as desired in order to increase the scanning performance. The Controller assigns scanning jobs to each available scanner in a round-robin fashion until all scans are completed. The scanner also contains the latest CVE database and is updated regularly by NeuVector.
>
> **Updater**
>
> The Updater is a container which when run, updates the CVE database for NeuVector. NeuVector regularly publishes new scanner images to include the latest CVE for vulnerability scans. The updater re-deploys all scanner pods by taking the deployment to zero and scaling it back up, forcing a pull of an updated scanner image.



## NeuVector installation

NeuVector can be deployed many ways and on many different platforms, for an extensive list of supported methods and platforms see [here](https://open-docs.neuvector.com/deploying). 

If you happen to use Rancher, installing NeuVector is just a click in the Rancher UI. Ofcourse there are some options that should be configured to ensure access (Ingress) and data-persistence. 

I will quickly go through the installation of NeuVector using Rancher. 

From the Cluster Dashboard for the cluster you want to deploy NeuVector in head to Apps - Charts and find NeuVector and click on it:

![neuvector](images/image-20240520154059631.png)

Then from the next window find the **Install** button in the top right corner:

![install-neuvector](images/image-20240520154323982.png)

Then in the next step select the Project and click Next:

![project](images/image-20240520154605059.png)

In the next step I will leave everything at default except the Ingress. Here I will select Ingress for the Manager and enter my hostname then when I am done click Install:

![neuvector-ingress](images/image-20240520154940481.png)

![installing](images/image-20240520155057078.png)

Done. 

Neuvector is now installed and I should be able to reach the ui by grabbing the IP from the Ingress object or from within the Rancher UI:

```bash
NAMESPACE                 NAME                      CLASS    HOSTS                         ADDRESS          PORTS   AGE
cattle-neuvector-system   neuvector-webui-ingress   avi-lb   neuvector-1.my-domain.net   192.168.121.12   80      68s
```

![neuvetor-rancher-ui](images/image-20240521072802141.png)

![login](images/image-20240521073015571.png)



When logged in it will show the Dashboard providing a quick glance at the current state:

![dashboard](images/image-20240521074732304.png)



Now lets try out some of the features in NeuVector

## Security Policies

I wrote a post a while back using [Antrea Native Policies](https://blog.andreasm.io/2023/06/21/securing-kubernetes-clusters-with-antrea-network-policies/) to create a "zero trust" approach where all namespaces are per default not allowed to communicate with each other (zero-trust) and then I micro-segmented, using Antrea policies, a demo application called Yelb. I will follow the same approach here using Antrea policies to apply the foundation policies in my cluster then I will use NeuVector to further add security postures and explore what more I can do with NeuVector. 

NeuVector comes with a rich set of security features such as L7 network rules, WAF, process rules, Network Threat signatures, Config Drift rules just to name a few. In additon to the vast visibility NeuVector provides one can imagine this post will be a very fun and interesting post to do. I will try to cover most of these features in the sub-sections below.

This post will start out using some Antrea Native polices to create a "minimum" foundation of security policies, then I will continue with the features of NeuVector.



### NeuVector Modes: Discover, Monitor and Protect

From the official NeuVector documentation:

> **[Discover](https://open-docs.neuvector.com/policy/modes#discover)**
>
> By default, NeuVector starts in Discover mode. In this mode, NeuVector:
>
> - Discovers your container infrastructure, including containers, nodes, and hosts.
> - Learns your applications and behaviors by observing conversations (network connections) between containers.
> - Identifies separate services and applications running.
> - Automatically builds a whitelist of Network Rules to protect normal application network behavior.
> - Baselines the processes running in containers for each service and creates whitelist Process Profile Rules.
>
> NOTE
>
> *To determine how long to run a service in Discover mode, run test traffic through the application and review all rules for completeness. Several hours should be sufficient, but some applications may require a few days to be fully exercised. When in doubt, switch to Monitor mode and check for violations, which can then be converted to whitelist rules before moving to Protect mode.*
>
> **[Monitor](https://open-docs.neuvector.com/policy/modes#monitor)**
>
> In Monitor mode NeuVector monitors conversations and detects run-time violations of your Security Policy. In this mode, no new rules are created by NeuVector, but rules can manually be added at any time.
>
> When violations are detected, they are visible in the Network Activity map visually by a red line. Violations are also logged and displayed in the Notifications tab. Process profile rule and file access violations are logged into Notifications -> Security Events.
>
> In the Network map you can click on any conversation (green, yellow, red line) to display more details about the type of connection and protocol last monitored. You can also use the Search and Filter by Group buttons in the lower right to narrow the display of your containers.
>
> **[Protect](https://open-docs.neuvector.com/policy/modes#protect)**
>
> In Protect mode, NeuVector enforcers will block (deny) any network violations and attacks detected. Violations are shown in the Network map with a red ‘x’ in them, meaning they have been blocked. Unauthorized processes and file access will also be blocked in Protect mode. DLP sensors which match will block network connections.

As I proceed with this post I will use a mix of all three modes, discover, monitor and protect, until I am satisfied and can enable protect on a global level.

<div style="border-left: 4px solid #2196F3; background-color: #E3F2FD; padding: 10px; margin: 10px 0; color: #0000FF;"> <strong>Info:</strong> 

Changing the three modes above can be done on a global level, for both services modes and network security policy modes. The three modes can also be adjusted on a per group level, this will not affect the any services and network policies, but Process Profile rules.  More on that later 

</div>

### Network Rules

Before getting into NeuVector network rules I will start out applying my Antrea Native "base-policies" or foundation as the minimum set of security policies controlling what is allowed and not allowed inside my Kubernetes cluster. 

The initial plan is to achieve this, without impacting the Kubernetes cluster operation:

![phase-1](images/image-20240522135525977.png)

In the diagram above and with the two Antrea policies applied I will allow communication between all namespace I have defined as "system-namespaces" and will drop any communication between any created user namespaces, including from any user created namespaces to system namespaces, except CoreDNS. 

Below is the Antrea Policy I will apply to create the "zero-trust" between all user namespaces:

```yaml
apiVersion: crd.antrea.io/v1alpha1
kind: ClusterNetworkPolicy
metadata:
  name: strict-ns-isolation-except-system-ns
spec:
  priority: 9
  tier: securityops
  appliedTo:
    - namespaceSelector:          # Selects all non-system Namespaces in the cluster
        matchExpressions:
          - {key:  kubernetes.io/metadata.name, operator: NotIn, values: [default,avi-system,kube-node-lease,kube-public,kube-system,cattle-system,cattle-neuvector-system,cattle-monitoring-system,cattle-impersonation-system,cattle-fleet-system,cattle-dashboards]}
  ingress:
    - action: Pass
      from:
        - namespaces:
            match: Self           # Skip ACNP evaluation for traffic from Pods in the same Namespace
      name: PassFromSameNS
    - action: Drop
      from:
        - namespaceSelector: {}   # Drop from Pods from all other Namespaces
      name: DropFromAllOtherNS
  egress:
    - action: Pass
      to:
        - namespaces:
            match: Self           # Skip ACNP evaluation for traffic to Pods in the same Namespace
      name: PassToSameNS
    - action: Drop
      to:
        - namespaceSelector: {}   # Drop to Pods from all other Namespaces
      name: DropToAllOtherNS

```



Certain essential services such as CoreDNS is also needed and I will apply a policy to allow for that, below is the policy:

```yaml
apiVersion: crd.antrea.io/v1alpha1
kind: ClusterNetworkPolicy
metadata:
  name: allow-all-dns-service
spec:
  priority: 8
  tier: securityops
  appliedTo:
    - namespaceSelector: {}
  egress:
    - action: Allow
      toServices:
        - name: rke2-coredns-rke2-coredns
          namespace: kube-system
      ports:
        - protocol: TCP
          port: 53
        - protocol: UDP
          port: 53
      name: "allow-dns-service-from-any"

```



Applied:

```bash
andreasm@linuxmgmt01:~/rancher$ k get acnp
NAME                                   TIER          PRIORITY   DESIRED NODES   CURRENT NODES   AGE
allow-all-dns-service                  securityops   8          7               7               15m
strict-ns-isolation-except-system-ns   securityops   9          2               2               17m
```







Now its time to continue with NeuVector. 

One brilliant part of NeuVector is the Discover/Learned part. It will already provide me with a list of policies in Allow mode, based on findings it has done. These policies may be used as is or as an initial suggestion to how the the application interacts. Some of the rules it has created:
![learned-rules](images/image-20240521114908130.png)

I already have a demo application called Yelb running in the cluster. Lets filter on the app Yelb and see what NeuVector has found:

![yelb-rules-discovered](images/image-20240522151845160.png)

This looks to be a good starting point, what I do miss though is the specific ports the different pods/parts applications are using. I happen to know them as I know the application, but I suspect even NeuVector knows them, lets check Network Activity and filter on anything Yelb related:

![network-activity-yelb](images/image-20240522152128325.png)

Lets click on the flows between the pods *yelb-ui*, *yelb-db*, *yelb-appserver* and *redis-server*. 

**yelb-ui to yelb-appserver**

![yelb-ui-to-yelb-appserver](images/image-20240522152254304.png)

Yelb UI to Yelb Appserver is discovered using application HTTP on TCP/4567 - as the Appserver is running Ruby Sinatra lightweight web application.

**yelb-appserver to yelb-db**

![yelb-app-to-yelb-db](images/image-20240522152845032.png)

Yelb Appserver to Yelb DB is  discovered using application PostgreSQL on port TCP/5432

**yelb-appserver to redis-server**

![yelb-appserver-to-redis-server](images/image-20240522152934558.png)

Yelb Appserver to Redis Server is discovered using application Redis on port TCP/6379

**The external to yelb-ui**

![external-to-yelb-ui](images/image-20240522153020531.png)

Then from *external* Neuvector has discovered the source IP addresses 192.168.120.100 and 192.168.120.101 is using application HTTP on port TCP/80 to my Yelb UI pod. These source addresses happens to be my Avi Service Engines providing the ServiceType Loadbalancer service for my Yelb ui which is the only ip addresses that should have access to the Yelb-ui pods in the first place. 

NeuVector discovers the correct applications and ports inside my Yelb demo application including the external access via the loadbalancer service. 

Now that I have all the ports also, I can go ahead and create a more specific rule. And, all the applications/ports discovered were correct as the application is using these ports:

![yelb-diagram](images/image-20240522153405813.png)



Lets start by creating the new rules before enforcing anything (changing mode to *protect*):

![add-to-top](images/image-20240523085120632.png)

![ui-to-app](images/image-20240523085236160.png)

After the first rule has been created I will continue add the rest below the first by clicking on the + sign like this:

![below](images/image-20240523085515490.png)



After adding all rules:

![save](images/image-20240523085907088.png)

I have only created the rules necessary for the application itself. I have not defined any external to ui policy, so if I enforce this I will loose access to the application from outside. And then it is the DNS service. I already have a Antrea Native policy that gives me access to DNS, but if I enforce it in NeuVector, will NeuVector drop DNS? Lets see

I will delete the rules created as part of the discovery process:

![remove](images/image-20240523084203901.png)

![ok](images/image-20240523084339342.png)

![save](images/image-20240523084439094.png)



With only my three manually created rules in place, will NeuVector re-discover and create the other needed rules?

![look-whos-back](images/image-20240523090825596.png)

Yes, it re-discovers and re-creates the other rules as well.

What about the DNS rule? I have an Antrea Policy allowing DNS requests to my CoreDNS service, but that is not something NeuVector is aware of so I will have to create such a rule also in NeuVector in addition to the external rule.

For the external part I will create a specific group where only the IP addresses from my Avi Service Engines comes from. 

![avi-se-grp](images/image-20240523091253315.png)

Now I can also be very specific what the external source is. 

This is how my Yelb ruleset is looking right now:

![yelb-ruleset](images/image-20240523091651865.png)

It is now time to change mode to protect to enable the default deny policy at the bottom of all my rules. This policy will drop anything that has not been defined earlier.

All the previous rules NeuVector has provided by Discovery not related to the Yelb application will be left as is as it will just ensure all the other systems will continue to work. 

Changing the global mode from Discover to Protect:

![settings](images/image-20240523154007992.png)

Select protect

![protect](images/image-20240523154134117.png)

Then *Submit*

I can verify that my Yelb application still works:

```bash
andreasm@linuxmgmt01:~/$ curl http://192.168.121.11
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>Yelb</title>
    <base href="/">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/x-icon" href="favicon.ico?v=2">
</head>
<body>
<yelb>Loading...</yelb>
<script type="text/javascript" src="inline.bundle.js"></script><script type="text/javascript" src="styles.bundle.js"></script><script type="text/javascript" src="scripts.bundle.js"></script><script type="text/javascript" src="vendor.bundle.js"></script><script type="text/javascript" src="main.bundle.js"></script></body>
</html>
```

Using NeuVector Network Activity dashboard is also very useful to see whats going on:

![network-activity](images/image-20240524081346658.png)

<div style="border-left: 4px solid #2196F3; background-color: #E3F2FD; padding: 10px; margin: 10px 0; color: #0000FF;"> <strong>Info:</strong> 

Using NeuVector's Network Activity dashboard is really powerful, its very instant, new flows are detected immediately and it provides vast information on whats going on. Lets dig into this dashboard later 

</div>





Some last verifcations that NeuVector actually enforces these rules, I will change the avi-se-vms to yelb-ui policy to drop:

![drop](images/image-20240524081834562.png)

Trying to connect to my Yelb app now:

```bash
andreasm@linuxmgmt01:~/$ curl http://192.168.121.11
curl: (56) Recv failure: Connection reset by peer
```

From the network activity dashboard now I see this:

![http-dropped](images/image-20240524082326941.png)



![red-flow](images/image-20240524082242149.png)



What about between the pods in the Yelb namespace?

From yelb-ui





To verify that I will now exec into the *yelb-appserver* pod do a curl to the *yelb-ui* pod on different ports:

```bash
andreasm@linuxmgmt01:~/$ k exec -it -n yelb yelb-appserver-6dc7cd98-pvdln bash
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl exec [POD] -- [COMMAND] instead.
root@yelb-appserver-6dc7cd98-pvdln:/app# curl 10.42.1.10
^C
root@yelb-appserver-6dc7cd98-pvdln:/app# curl 10.42.1.10:4567
^C
root@yelb-appserver-6dc7cd98-pvdln:/app# curl 10.42.1.10:5432
^C
```



And in network activity dashboard I will see this:

![yelb-app-to-ui](images/image-20240524102946223.png)



From *yelb-appserver* to *yelb-db* using other ports than the allowed tcp/5432:

```bash
andreasm@linuxmgmt01:~/$ k exec -it -n yelb yelb-appserver-6dc7cd98-pvdln bash
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl exec [POD] -- [COMMAND] instead.
root@yelb-appserver-6dc7cd98-pvdln:/app# curl 10.42.1.8:4567
^C
```



![app-to-db](images/image-20240524114834670.png)



This is looks pretty locked down for now. I have made sure there is no possibility for any of the pods in the Yelb namespace to have a conversation without using the application AND port they are allowed to use. 

If I scale the application, e.g the UI pod, to several pods after I have put NeuVector to Protect?

Lets test that. 

Will scale the yelb-ui to 4 pods in total:

```bash
andreasm@linuxmgmt01:~/$ k scale deployment -n yelb yelb-ui --replicas 4
deployment.apps/yelb-ui scaled
amarqvardsen@amarqvards1MD6T:~/github_repos/blog.local (main)$ k get pods -n yelb
NAME                            READY   STATUS              RESTARTS   AGE
redis-server-84f4bf49b5-t7pdc   1/1     Running             0          3d22h
yelb-appserver-6dc7cd98-pvdln   1/1     Running             0          3d22h
yelb-db-84d6f6fc6c-wq2bf        1/1     Running             0          3d22h
yelb-ui-f544fc74f-2zzlq         0/1     ContainerCreating   0          5s
yelb-ui-f544fc74f-85x4v         1/1     Running             0          3d22h
yelb-ui-f544fc74f-bj6n7         0/1     ContainerCreating   0          5s
yelb-ui-f544fc74f-ddwpd         0/1     ContainerCreating   0          5s
```

















Services discover vs protect.. 

Next I will look at processes going on inside the containers themselves... 





































One can also change the mode on individial groups instead of global. But if you have custom groups involved, they dont have that option. I have one custom group, the avi_se_vms group, so this will not be able to set to protect. 

Lets quickly test setting mode on individual groups.

I two Ubuntu pods running in the same namespace, I want to drop SSH tcp/22 specifically between them without setting the mode globally to protect. 

```bash
andreasm@linuxmgmt01:~/rancher$ k get pods -n ubuntu -owide
NAME                            READY   STATUS    RESTARTS   AGE     IP           NODE                                          NOMINATED NODE   READINESS GATES
ubuntu-20-04-789cbd8c75-5s557   1/1     Running   0          2d17h   10.42.6.14   rke2-cluster-1-vsphere-pool2-fe74bc56-rs8jc   <none>           <none>
ubuntu-20-04-789cbd8c75-kwj7l   1/1     Running   0          2m34s   10.42.4.22   rke2-cluster-1-vsphere-pool2-fe74bc56-59srx   <none>           <none>
```

 

Before any NeuVector policies, and NeuVector in Discover mode:

```bash
root@ubuntu-20-04-789cbd8c75-5s557:~# ssh testuser@10.42.4.22
testuser@10.42.4.22's password:
Welcome to Ubuntu 20.04.5 LTS (GNU/Linux 5.15.0-105-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

This system has been minimized by removing packages and content that are
not required on a system that users do not log into.

To restore this content, you can run the 'unminimize' command.

The programs included with the Ubuntu system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.

testuser@ubuntu-20-04-789cbd8c75-kwj7l:~$
```

I can SSH from one pod to the other in the same namespace. 

In NeuVector I can see this rules being created:

![ubuntu-rule](images/image-20240523155408422.png)

Let me delete that rule, create a similar rule and set it to Deny.

![drop-rule](images/image-20240523155754770.png)

It will not have any effect yet as the global mode is Discover only. Now if I go into groups and set the nv.ubuntu-20-04.ubuntu group to Protect lets see what happens. 

![change-mode](images/image-20240523155943525.png)

![protect](images/image-20240523160004626.png)







Try to drop one by one rule to see impact. 





Delete existing rules. Create new groups, or reuse existing.. check that.

 



If I take a look at the rules created by NeuVector using its Discovery phase many of them do involve a lot of internal Kubernetes services, including NeuVector components itself. 



But I would like to tidy it a bit up. And in order to do that I will go ahead and create a group, where the membership criteria is based on the namespaces *cattle-*, *kube-system*, *avi-system*, *kube-public* and *kube-node-lease*.

![system-ns-group](images/image-20240521122843031.png)



![group-with-members](images/image-20240521122928209.png)



Now that I have this big group of system-namespaces I can go ahead and monitor it. 





There is a couple of approaches I could use to reach my "phase 1" goal illustrated above. I can use NeuVector's discovered flows and learned rules  



Drop SSH process, curl etc.. 



But as mentioned above, default NeuVector is in Discover mode and will not enforce any of my created policies. So I will have to make sure to set in in protect before my policy will be enforced. Until I do that I will ofcourse get alerts that my pods are violating the policy, but its not blocking it. 

Tightening down a Kubernetes cluster can be a tough task, especially when working in "blind". But NeuVector do provide a lot of information from its Discover phase. So that is a good start. 

Allow ping for troubleshooting purpose. 

Export and import configurations, template...



NeuVector does not enforce policies on the nodes themselves, so here one may have to look at Antrea Node Policies or NSX as a VM/node firewall solution. 



Automatic provision rules - using labels? GitOps? 



### Groups

Lets use the Discover process and see if I dont have to re-invent the wheel and use NeuVector's suggested policies. 

 

## Multiple Clusters
