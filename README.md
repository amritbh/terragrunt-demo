# terragrunt-demo

A workspace demonstrating real-world **Terragrunt + Terraform** patterns for managing AWS infrastructure across multiple environments. The repository contains two independent projects, each demonstrating a progressively more complex use-case.

## Projects

| Project | Description |
|---|---|
| [`infrastructure-live/` + `infrastructure-modules/`](#project-1-basic-multi-environment-vpc) | **Project 1** — Basic multi-environment VPC provisioning (dev / uat / prod) |
| [`End-To-End-Project/`](#project-2-end-to-end-eks-infrastructure) | **Project 2** — Full EKS cluster stack with IAM, VPC, Subnets, and inter-module dependencies |

---

## Project 1: Basic Multi-Environment VPC

See [infrastructure-modules/vpc/](infrastructure-modules/vpc/) and [infrastructure-live/](infrastructure-live/) for source files.

Demonstrates how a **single reusable Terraform VPC module** can be deployed to `dev`, `uat`, and `prod` environments using separate Terragrunt configurations, each with different CIDR ranges and tags — but **zero code duplication**.

## Project 2: End-To-End EKS Infrastructure

See [End-To-End-Project/](End-To-End-Project/) for full documentation and source files.

Demonstrates a complete, production-style **EKS cluster** deployment with proper inter-module dependencies (VPC → Subnets → IAM → EKS), remote state management, and mock outputs for safe planning before resources exist.

---

## Common Concepts

### Why Terragrunt?
Terraform alone requires you to copy-paste the backend `config` block and `provider` block into every module directory. Terragrunt solves this with a shared `root.hcl` that is inherited by all child configurations, keeping everything DRY.

### Shared Remote State Backend
Both projects use the same AWS backend for storing Terraform state:

| Setting | Value |
|---|---|
| S3 Bucket | `s3-terraform-terragrunt-state` |
| DynamoDB Lock Table | `s3-terraform-terragrunt-state-locks` |
| Region | `us-east-1` |
| Encryption | Enabled |

State files are isolated per module using an auto-generated path key:
```
s3://s3-terraform-terragrunt-state/<relative-path-to-module>/terraform.tfstate
```
