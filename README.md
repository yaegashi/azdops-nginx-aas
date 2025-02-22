# azdops-nginx-aas

## Introduction

A cloud-native DevOps solution for [NGINX] with Azure Container Apps.

This repository provides AZD Ops for the following Azure resources.

- Azure Container App that runs the [NGINX container].
- Azure Storage Account that holds web site contents and NGINX configuration.

[NGINX]: https://nginx.org/en/
[NGINX container]: https://hub.docker.com/_/nginx

## AZD Ops Instruction

This repository utilizes GitHub Actions and Azure Developer CLI (AZD) for the GitOps tooling (AZD Ops).
You can bootstrap an AZD Ops repository by following these steps:

1. Create a new **private** GitHub repository by importing from this repository. Forking is not recommended.
2. Copy the AZD Ops settings from `.github/azdops/main/inputs.example.yml` to `.github/azdops/main/inputs.yml` and edit it. You can do this using the GitHub Web UI.
3. Manually run the "AZD Ops Provision" workflow in the GitHub Actions Web UI. It will perform the following tasks:
    - Provision Azure resources using AZD with the `inputs.yml` settings. By default, a resource group named `{repo_name}-{branch_name}` will be created.
    - Make an AZD remote environment in the Azure Storage Account and save the AZD env variables in it.
    - Update `.github/README.md` and `.github/azdops/main/remote.yml`, then commit and push the changes to the repository.