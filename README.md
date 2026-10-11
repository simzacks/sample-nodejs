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

## Semantic Versioning
- Added semantic-release as a dev dependency.
  - Dependabot (on GitHub) raised alerts on its dependencies, which don't have unaffected versions that can be upgraded to. However, these dependencies are Dev and not included in the image (npm ci --omit=dev), so I decided to allow it to stay.
  - versioning is based on the commit messages.
    - A breaking change is a major bump (`1.0.0` to `2.0.0`). Add a `BREAKING CHANGE:` footer, or put `!` after the type: `feat!: remove /classified`.
    - A new feature is a minor bump (i.e. `feat: awesome new feature` is a minor bump (`1.0.0` to `1.1.0`))
    - All other commits are a patch bump ((`1.1.0` to `1.1.1`)
    - When several commits are pushed at the same time, the highest bump wins.

## Container
- multi-stage process to prepare everything in a full OS environment and then cut down everything that is not needed for the application.
- Build image: debian:trixie-slim, industry standard for building Node.js containers. Uses slim version to remove any additional bloat.
- Production image: gcr.io/distroless/cc-debian13:nonroot - Google's Distroless base image (trixie=13) which contains the bare minimum needed to execute the binary. This keeps it super small and secure. 

## CI
- activated on either a push or pull request to the following files: app.js, package.json, package-lock.json, Dockerfile and the build-image.yml workflow. The other files should not influence a build.
- CodeQL check - security vulnerabilities, logic bugs, and code quality issues
  - This can be configured to be executed directly by GitHub without requiring it in the workflow file
- Dependency Audit - executes npm audit with the omit=dev flag so that it only checks dependency vulnerabilities for packages that will be deployed in the production environment
- Secret scan - uses the gitleaks action to review the source code if there are any credentials, tokens, ... in the code.
- Job order: CodeQL, audit and secret scan (parallel) -> Image (build, scan, push) -> Release -> Promote -> GitOps. Each stage needs the previous one to succeed, so nothing is tagged, released or deployed if a scan fails.
- Image - Only executes if CodeQL, audit and the secret scan passed.
  - Builds the docker container
  - Scans the built container (using trivy) for CVEs
  - Uploads the file to be included in the Github Security tab
  - Fails if there is a high/critical failure
  - On `main` only, pushes the scanned image to the GitHub registry with an immutable `sha-<commit>` tag (with provenance and SBOM attestations)
- Release - Only on `main`, after the image passed its scan. Uses the semantic-release package to determine a new version number, and creates a git tag and GitHub release with that version.
- Promote - Adds the version tag to the already-scanned image with `docker buildx imagetools create`. There is no rebuild, so the version tag points at the same digest that Trivy scanned.
- GitOps - After the version tag exists, uses `yq` to set `image.tag` in `gitops/workloads/nodejs/values.yaml` and pushes that commit to `main` so Argo CD redeploys

## GitOps
- The argo deployment pattern used in this repo is an App of Apps pattern, in which the master-app `gitops/bootstrap/master-app.yaml` is basically a pointer telling argocd which directory the argo application can be found. 
- The apps themselves are found in the `gitops/apps`, and are argocd `Applications` that point to the actual kubernetes definition files in the repo.
- This project has 2 applications, nodejs_app and mongodb
- nodejs_app
  - Helm chart defines the k8s resources that will be used to deploy the app, as well as any environment variables defined in the app. The templates use the values in the `values.yaml` to generate the needed k8s resources. In this case the resources used are:
    - ConfigMap, Ingress, Deployment, Service, ServiceAccount, PodDisruptionBudget
    - Hardening: pods run as the numeric non-root user 65532 with the `RuntimeDefault` seccomp profile, a read-only root filesystem, no privilege escalation and all capabilities dropped. The dedicated ServiceAccount and the pods do not mount an API token, because the app never talks to the Kubernetes API.
    - Availability: a topology spread constraint places the replicas on different nodes, a PodDisruptionBudget (`minAvailable: 1`) keeps one pod up during node drains, and the RollingUpdate strategy (`maxSurge: 1`, `maxUnavailable: 0`) replaces pods one at a time without reducing capacity.
    - A `checksum/config` annotation on the pod template restarts the pods when the ConfigMap changes.
    - The `app.kubernetes.io/version` label and the chart `appVersion` follow the deployed image tag. The CI GitOps job updates `image.tag` and `appVersion` in the same commit.
    - It deploys the given image as 2 replicas with a ClusterIP using the traefik igress without TLS on port 8080, with readiness and liveness probes pointed to enpoints in the application.
- mongodb
  - MongoDB is installed as a 3 node cluster, following a requirement of using a bitnami chart for version 8.0.13
    - The open source charts for this version have been moved to a bitnami-legacy repo, so the image section in the helm values file specifies where to get it from.
  - The credentials and external domain name were applied during infrastructure deployment
    - This enables all future syncs/deployments to use the same credentials
    - The infra deployment is the only place where we know the load balancer address, which is needed for the external connection string.
  - Ports for connecting are defined as NodePorts - 30017, 30018 and 30019
    - The bitnami chart assigns each one of these ports to one of the specific pods in the replica-set, so each time a connection hits one of those ports it will always go to the same pod.
  - Uses the command section of the chart to override the default Advertised Hostname to the load balancer ip address that was saved as a config map by the Terraform infra.
  - Enables the metrics, which can be accessed via the metrics-server in kube-system
