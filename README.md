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

## Package changes
- Added semantic-release as a dev dependency.
  - Dependabot (on GitHub) raised alerts on its dependencies, which don't have unaffected versions that can be upgraded to. However, these dependencies are Dev and not included in the image (npm ci --omit=dev), so I decided to allow it to stay.

## Container
- multi-stage process to prepare everything in a full OS environment and then cut down everything that is not needed for the application.
- Build image: debian:trixie-slim, industry standard for building Node.js containers. Uses slim version to remove any additional bloat.
- Production image: gcr.io/distroless/cc-debian13:nonroot - Google's Distroless base image (trixie=13) which contains the bare minimum needed to execute the binary. This keeps it super small and secure. 

## CI
- activated on either a push or pull request to the following files: app.js, package.json, package-lock.json, Dockerfile and the build-image.yml workflow. The other files should not influence a build.

## 


## Commit messages

The image version comes from commit messages on `main`. That version is the container tag.

- `feat: add a health endpoint` is a minor bump (`1.0.0` to `1.1.0`).
- A breaking change is a major bump (`1.0.0` to `2.0.0`). Add a `BREAKING CHANGE:` footer, or put `!` after the type: `feat!: remove /classified`.
- Every other message is a patch bump (`1.0.0` to `1.0.1`). That includes `fix:`, `chore:`, `docs:`, and a plain sentence such as `update a comment`.

When several commits are released together, the highest bump wins. A `feat` together with a comment change is a minor release.

The build runs when `app.js`, `package.json`, `package-lock.json`, `Dockerfile`, or `.github/workflows/build-image.yml` changes. A comment edit in one of those files still publishes a new patch.

Dependabot alerts on this repo come from semantic-release, which is a devDependency. Two chains have no patched release. `micromatch` pulls `braces` 3.0.3 (`GHSA-vfj7-8cjw-p6xm`); every published version is affected, and the maintainer is not shipping a fix. `@semantic-release/npm` bundles the `npm` package, whose nested copies of `sigstore`, `pacote`, `undici`, `ip-address`, `http-cache-semantics`, `brace-expansion`, and `postcss-selector-parser` are `bundleDependencies`, so an override cannot replace them. `semantic-release` 25 still pulls both chains.

The image build runs `npm ci --omit=dev`, so those packages are not in the container. They do run in the release job, on this repo's branch name, asset list, and commit messages. The Express app does not load them.

The workflow fails the image job when production dependencies have a high or critical advisory (`npm audit --omit=dev --audit-level=high`). Those devDependency advisories are not a release gate. CodeQL and a full-history secret scan have to pass before the image is built. Trivy still scans the built image for high and critical vulnerabilities.

## GitOps

App of apps: `gitops/master-app.yaml` is the master Application. It watches `gitops/apps` and syncs every child Application in that directory. `sample-infra` downloads that file from GitHub `main` and applies it once Argo CD is installed. Every Application, including external Helm charts, deploys into the `default` namespace.

### Node.js app

Child app: `gitops/apps/nodejs_app.yaml` points at the in-repo Helm chart `gitops/workloads/nodejs`. The workload is a **Deployment** (stateless Express: no PVC, no sticky identity). Readiness and liveness probes hit `/ready` and `/live`. Config (`PORT`, `NODE_ENV`) is a ConfigMap; there is no Secret because the app does not take credentials.

The process listens on `PORT` and falls back to `8080` when that variable is unset. The chart uses `config.PORT` (default `8080`) for the container port, Service, and Ingress, and the probes follow that container port. Changing `PORT` on the running pods, then restarting them, leaves those objects on the rendered port. Probes fail, the pods restart, and the Service stops sending traffic. Change the port through `config.PORT` in `gitops/workloads/nodejs/values.yaml` and sync the chart so the Deployment, Service, and Ingress move with it.

The container image is `ghcr.io/simzacks/sample-nodejs`. The tag is `image.tag` in `gitops/workloads/nodejs/values.yaml`.

Ingress uses Traefik’s `web` entrypoint (port 80, TLS off), same as Argo CD. The rule has no Host so it matches any name on the load balancer; Argo CD keeps the more specific `argocd.<lb-ip>.sslip.io` Host. After apply, open `http://app.<load-balancer-ip>.sslip.io` from the `app_access` Terraform output. Set `ingress.hostname` in values only if you need to pin a specific name.

### MongoDB

Child app: `gitops/apps/mongodb_app.yaml` (chart source, destination, sync only). ReplicaSet, NodePort, image `8.0.13`, and resources are in `gitops/workloads/mongodb/values.yaml`. The chart reads the `mongodb-credentials` Secret and does not create it. `sample-infra` generates that Secret on apply. `terraform output mongodb_access` prints the `kubectl` commands that read the app password, root password, and replica set key.

