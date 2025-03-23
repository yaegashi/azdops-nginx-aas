# azdops-nginx-aas

## Introduction

A cloud-native DevOps solution for [NGINX](https://nginx.org) with Azure App Service.

This repository provides AZD Ops for the following Azure resources:

- Azure App Service running a [customized NGINX container](https://github.com/yaegashi/azure-easy-auth-njs).
- Azure Storage Account that stores website contents and NGINX configuration.

## AZD Ops Instructions

This repository leverages GitHub Actions and Azure Developer CLI (AZD) for GitOps tooling (AZD Ops).
Follow these steps to set up your own AZD Ops repository:

1. Create a new **private** GitHub repository by importing from this repository. Forking is not recommended.
2. Copy the AZD Ops settings from `.github/azdops/inputs.example.yml` to `.github/azdops/inputs.yml` and customize as needed. You can do this using the GitHub Web UI.
3. Manually trigger the "AZD Ops Provision" workflow in the GitHub Actions Web UI. This workflow will:
    - Provision Azure resources using AZD with your `inputs.yml` settings. By default, it creates a resource group named `{repo_name}_{branch_name}`.
    - Create an AZD remote environment in the Azure Storage Account and store the AZD environment variables.
    - Update `.github/README.md` and `.github/azdops/remote.yml`, then commit and push the changes to your repository.