---
author: "Andreas M"
title: "Monitoring With Prometheus, Loki, Promtail and Grafana"
date: 2022-10-19T10:54:37+02:00 
description: "Article description."
draft: false 
toc: true
featureimage: "/images/loki.png"
thumbnail: "/images/loki.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - Kubernetes
  - Monitoring
  - Logging
tags:
  - loki
  - grafana
  - promtail
  - prometheus

comment: false # Disable comment if false.
---



# Logging and metrics monitoring 

I wanted to visualize performance metrics in Grafana, and getting the logs from my Kubernetes clusters available centrally. So i chose to go with Grafana as my "dashboard" for visualizing, Prometheus for metrics and Loki for logs.
I did fiddle some to get this up and running. But after I while I managed to get it sorted the way I wanted. 

Sources used in this article:
Bitnami, Grafana and Kube-Prometheus-Stack

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm repo add grafana https://grafana.github.io/helm-charts

helm repo add bitnami https://charts.bitnami.com/bitnami

