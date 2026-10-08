# DevOps Sample Node.js App

## Overview

A lightweight Node.js application. It features basic web endpoints, Prometheus metrics integration, and is designed for Kubernetes deployment and CI/CD pipeline demonstrations.

## Features

- Express.js web server
- Prometheus metrics integration
- Readiness and liveness probe endpoints
- Customizable port via environment variable

## Prerequisites

- Node.js (v22.1.0)

## Commit messages

The image version comes from commit messages on `main`. That version is the container tag.

- `feat: add a health endpoint` is a minor bump (`1.0.0` to `1.1.0`).
- A breaking change is a major bump (`1.0.0` to `2.0.0`). Add a `BREAKING CHANGE:` footer, or put `!` after the type: `feat!: remove /classified`.
- Every other message is a patch bump (`1.0.0` to `1.0.1`). That includes `fix:`, `chore:`, `docs:`, and a plain sentence such as `update a comment`.

When several commits are released together, the highest bump wins. A `feat` together with a comment change is a minor release.

The build runs when `app.js`, `package.json`, `package-lock.json`, `Dockerfile`, or `.github/workflows/build-image.yml` changes. A comment edit in one of those files still publishes a new patch.

## GitOps

App of apps: `gitops/master-app.yaml` is the master Application. It watches `gitops/apps` and syncs every child Application in that directory. `sample-infra` downloads that file from GitHub `main` and applies it once Argo CD is installed. Every Application, including external Helm charts, deploys into the `default` namespace.

### Node.js app

Child app: `gitops/apps/nodejs_app.yaml` points at the in-repo Helm chart `gitops/workloads/nodejs`. The workload is a **Deployment** (stateless Express: no PVC, no sticky identity). Readiness and liveness probes hit `/ready` and `/live`. Config (`PORT`, `NODE_ENV`) is a ConfigMap; there is no Secret because the app does not take credentials.

The process listens on `PORT` and falls back to `8080` when that variable is unset. The chart uses `config.PORT` (default `8080`) for the container port, Service, and Ingress, and the probes follow that container port. Changing `PORT` on the running pods, then restarting them, leaves those objects on the rendered port. Probes fail, the pods restart, and the Service stops sending traffic. Change the port through `config.PORT` in `gitops/workloads/nodejs/values.yaml` and sync the chart so the Deployment, Service, and Ingress move with it.

The container image is `ghcr.io/simzacks/sample-nodejs`. The tag is `image.tag` in `gitops/workloads/nodejs/values.yaml`.

Ingress uses Traefik’s `web` entrypoint (port 80, TLS off), same as Argo CD. The rule has no Host so it matches any name on the load balancer; Argo CD keeps the more specific `argocd.<lb-ip>.sslip.io` Host. After apply, open `http://app.<load-balancer-ip>.sslip.io` from the `app_access` Terraform output. Set `ingress.hostname` in values only if you need to pin a specific name.

### MongoDB

Child app: `gitops/apps/mongodb_app.yaml` (chart source, destination, sync only). ReplicaSet, NodePort, image `8.0.13`, and resources are in `gitops/workloads/mongodb/values.yaml`. The chart reads the `mongodb-credentials` Secret and does not create it. `sample-infra` generates that Secret on apply. `terraform output mongodb_access` prints the `kubectl` commands that read the app password, root password, and replica set key.

