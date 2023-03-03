---
title: "Microsegmentation with VMware NSX"
date: "2021-07-10"
thumbnail: "/images/icon-prod-nsx-service-defined-firewall-rgb-400px.svg"
categories: 
  - "nsx-t"
  - "vmware nsx"
tags: 
  - "informational"
 
---

This post will go through one way of securing your workloads with VMware NSX. It will cover the different tools and features built into NSX to achieve a robust and automated way of securing your workload. It will go through the use of Security Groups, how they can be utilized, and how to create security policies in the distributed firewall section of NSX-T with the use of the security groups.

## Introduction to NSX Distributed Firewall

If we take a look inside a modern datacenter we will discover very soon that there is not so much bare metal anymore (physical server with one operating system and often many services to utilize the resources), most workload today is virtualized. From a network perspective the traffic pattern has shifted from being very much north/south to very much east/west. A typical traffic distribution today between north/south and east/west is a 10% (+/-) north/south and 90%(+/-) east/west. When the traffic pattern consisted of a high amount north/south it made sense to have our perimeter firewall regulate and enforce firewall rules in and out of the DC and between server workload. Due to server virtualization a major part of the DC the workload consist of many virtual machine instances with very specific services and "intra" communication (east/west) is a large part. It is operationally a tough task to manage a perimeter firewall to be the "policy enforcer" between workload in the east/west "zone". It is also very hard for a discrete appliance to be part of the context (it is outside of the dataplane/context of the workload it is trying to protect).. Will delve into this in more detail later in the article. Will also illustrate east/west and north/south traffic pattern.
