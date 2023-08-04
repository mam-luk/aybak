
[![](https://img.shields.io/github/license/mam-luk/aybak.svg)](https://github.com/mam-luk/aybak/blob/master/LICENSE)

<p align="center">
<img src=".mamluk/logo-horizontal.svg" alt="Kipchak by Mamluk" title="Kipchak by Mamluk - an API Toolkit" width="377"/>
</p>

# Aybak by Mamluk
Aybak is a toolkit that comprises:

* A single file utility connects to a Kubernetes cluster periodically and extracts the IP addresses of the worker nodes.
* It then writes these IP addresses to a git repo (configurable).
* A set of GitHub Actions templates to help you configure the pipelines to update your load balancer (HA Proxy, in this case) with the new IPs. These pipelines templates are available at https://github.com/mam-luk/aybak-pipelines-template.

## Why Aybak?
It is useful in those cases where you cannot use a Service ```type: LoadBalancer``` as 
the cloud provider's load balancers may have limitations (AWS, Azure, GCP OCI, Digital Ocean, Linode, Vultr all come to mind),
especially if you are familiar with load balancing, layer 4 and 7 protocols and have an interest in tuning tcp configuration(s).

Once the IPs are written to a git repo, you can use a pipeline orchestration (we provide a sample in the pipeline-sample folder) to update your own custom Load Balancer with the IPs.

This then gives you a fully configurable load balancer to run in front of your Kubernetes cluster without owning the Kube Cloud Controller Manager (CCM).

This utility is meant to be run as a Deployment (a cronjob will not work as 60 seconds is simply too long to monitor for IP changes in a busy cluster).

The utility is fully dockerised (and written in PHP 8) and has a low resource footprint, so you can 
deploy it locally using docker compose or plain PHP if you don't want to run it on a cluster.

## Contents
1. [Requirements](#requirements)
2. [Docker Image](#published-docker-image)
3. [Environment Variables & Configuration](#environment-variables--configuration)
4. [Usage](#usage)
5. [Deploying on Kubernetes for Production Use](deploying-on-kubernetes-for-production-use)
6. [Generate a Read only user on your Kubernetes Cluster](#generate-a-read-only-user-on-your-kubernetes-cluster)
7. [Credits](#credits)
8. [Disclaimer](#disclaimer)

### Requirements
* A Kubernetes Cluster and a token with read access to the cluster
* A Git Repository to write the IPs of the worker nodes to
* An SSH key to access the Git repository
* Docker (recommended) or PHP 8.2+ (you'll need to setup env vars on your machine / server before using PHP without Docker)

### Published Docker Image
The image for this utility is published @ Docker Hub as:
* ghcr.io/mam-luk/aybak:latest

The latest tag always has the latest code. Also, Docker tags are tied to the tags in this git repository as releases and latest always, believe it or not, contains the latest code.

### Environment Variables / Configuration
The docker container takes all its configuration via environment variables. Here's a list of what each one does:

| Environment Variable Name | Description                                                                                                                                                                                    | 
|---------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| 
| GIT_REPO                  | The git repository to update with the Node IPs                                                                                                                                                 |                                                                                                                                                                                        | 
| GIT_HOSTNAME              | Hostname of the git server. This will allow us to write the known_hosts file.                                                                                                                  |
| GIT_SSH_KEY               | The SSH key with write access to the git repository.                                                                                                                                           |
| QUERY_PERIOD              | How often to query the cluster to get the IPs, in seconds.                                                                                                                                     | 
| GIT_REPO_FILE_NAME        | The path in the repo to which you would like to write the file with the IPs. 
| K8S_CA                    | Kubernetes Control Plane CA. 
| K8S_TOKEN                 | Kubernetes Control Plane Token. 
| K8S_CONTROL_PLANE         | Kubernetes Control Plane URL. 


### Usage

You'll need to configure the Docker image with env variables.

Create a .env file and add the relevant environment variables in it.

Add a config.yaml file to the root of this repo. 

On Kubernetes, you can mount this file as a volume.

Or you can write your own Dockerfile and copy the config file into the image.

Then run:
```
docker compose build and docker compose up
```

Or, if you're not using Docker and just PHP, you can run:
```
php bin/aybak
```

### Deploying on Kubernetes for Production Use

Here's a manifest to get you started:
```
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k8s-autoscaler
  namespace: name-of-namespace ####### Change this to the actual namespace
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: aybak
  template:
    metadata:
      labels:
        app: aybak
    spec:
      containers:
        - name: aybak
          image: ghcr.io/mam-luk/aybak:latest ####### CHANGE THIS TO YOUR ACTUAL DOCKER IMAGE
          env:
            - name: GIT_SSH_KEY
              valueFrom:
                secretKeyRef:
                  name: aybak-secrets
                  key: git-ssh-key
            - name: K8S_CA
              valueFrom:
                secretKeyRef:
                  name: aybak-secrets
                  key: k8s-ca
            - name: K8S_TOKEN
              valueFrom:
                secretKeyRef:
                  name: aybak-secrets
                  key: k8s-token
            - name: K8S_CONTROL_PLANE
              valueFrom:
                secretKeyRef:
                  name: aybak-secrets
                  key: k8s-control-plane
            - name:  GIT_REPO
              value: "git@github.com:username/reponame.git"
            - name:  GIT_HOSTNAME
              value: "github.com"
             - name:  GIT_REPO_FILENAME
              value: "nodes/cluster-name.json"
             - name:  QUERY_PERIOD
              value: "15"
          resources:
            requests:
              memory: 32Mi
            limits:
              memory: 64Mi

```

The above manifest uses secrets to assign values to some of the 'secret' environment variables.

You will need to create these.

### Generate a Read only user on your Kubernetes Cluster
The last thing you want to do is to give this utility a token with full access to your cluster.

Use the following to create a read only service account on your cluster called 'aybak' that can retrieve node details:

```
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aybak
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: aybak
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "watch", "list"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: aybak
subjects:
  - kind: ServiceAccount
    name: aybak
    namespace: default
roleRef:
  kind: ClusterRole
  name: aybak
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
metadata:
  name: aybak
  namespace: default
  annotations:
    kubernetes.io/service-account.name: aybak
type: kubernetes.io/service-account-token
```

Then, you can retrieve this user's token with the following:

```
kubectl get secret/aybak -o jsonpath='{.data.token}' -n default | base64 --decode
```

### Credits
* renoki-co/php-k8s
* czproject/git-php
* https://github.com/Seldaek/monolog
* This utility has been built for Mamluk (https://mamluk.net), 7x (https://7x.ax) and Islamic Network (https://islamic.network)

