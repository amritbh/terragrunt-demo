# Project 1: Basic Multi-Environment VPC

This project is the **starting point** of the `terragrunt-demo` workspace. It demonstrates how to use Terragrunt to deploy the **same Terraform module** across three separate AWS environments (`dev`, `uat`, `prod`) with different network configurations — all without duplicating any infrastructure code.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [How It Works](#how-it-works)
4. [Remote State & Backend](#remote-state--backend)
5. [VPC Terraform Module](#vpc-terraform-module)
6. [Environment Configurations](#environment-configurations)
   - [dev](#dev-environment)
   - [uat](#uat-environment)
   - [prod](#prod-environment)
7. [Network Addressing Plan](#network-addressing-plan)
8. [Deployment Workflow](#deployment-workflow)
9. [Useful Commands](#useful-commands)

---

## Project Structure

```
terragrunt-demo/
├── infrastructure-modules/          # Reusable Terraform modules (environment-agnostic)
│   ├── vpc/
│   │   ├── main.tf                  # VPC + public subnet resource definitions
│   │   ├── variables.tf             # Input variable declarations with defaults
│   │   └── outputs.tf               # VPC ID and subnet ID outputs
│   ├── s3/                          # (Placeholder - not yet implemented)
│   ├── ec2/                         # (Placeholder - not yet implemented)
│   └── rds/                         # (Placeholder - not yet implemented)
│
└── infrastructure-live/             # Environment-specific Terragrunt configurations
    ├── root.hcl                     # Shared backend + AWS provider configuration
    ├── dev/
    │   └── vpc/
    │       └── terragrunt.hcl       # dev VPC: CIDR 10.0.0.0/16
    ├── uat/
    │   └── vpc/
    │       └── terragrunt.hcl       # uat VPC: CIDR 10.1.0.0/16
    └── prod/
        └── vpc/
            └── terragrunt.hcl       # prod VPC: CIDR 10.2.0.0/16
```

> **Design principle**: Infrastructure module code lives in `infrastructure-modules/` and is written once. Environment-specific values (CIDRs, tags, owners) live in `infrastructure-live/` and are never duplicated.

---

## Architecture Overview

Each environment gets its own isolated VPC with one public subnet:

```
┌──────────────────────────────────────────────────────────────────────┐
│                            AWS Account                               │
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │  dev VPC         │  │  uat VPC         │  │  prod VPC         │  │
│  │  10.0.0.0/16     │  │  10.1.0.0/16     │  │  10.2.0.0/16      │  │
│  │                  │  │                  │  │                   │  │
│  │  ┌────────────┐  │  │  ┌────────────┐  │  │  ┌─────────────┐ │  │
│  │  │ dev-subnet │  │  │  │ uat-subnet │  │  │  │ prod-subnet │ │  │
│  │  │ 10.0.0.0/24│  │  │  │ 10.1.0.0/24│  │  │  │ 10.2.1.0/24 │ │  │
│  │  │ (public)   │  │  │  │ (public)   │  │  │  │ (public)    │ │  │
│  │  └────────────┘  │  │  └────────────┘  │  │  └─────────────┘ │  │
│  └──────────────────┘  └──────────────────┘  └───────────────────┘  │
│                                                                      │
│  S3 + DynamoDB: shared remote state backend (all environments)       │
└──────────────────────────────────────────────────────────────────────┘
```

### Resources per environment

| Resource | dev | uat | prod |
|---|---|---|---|
| `aws_vpc` | `dev-vpc` | `uat-vpc` | `prod-vpc` |
| `aws_subnet` | `dev-subnet` | `uat-subnet` | `prod-subnet` |
| DNS hostnames | ✅ enabled | ✅ enabled | ✅ enabled |
| Public IPs on launch | ✅ enabled | ✅ enabled | ✅ enabled |

---

## How It Works

Terragrunt solves two problems this project demonstrates clearly:

### 1. Single Module, Multiple Deployments
The `infrastructure-modules/vpc/` directory contains the Terraform code for creating a VPC. Instead of having three copies of this code (one per environment), all three environments point to this single module:

```hcl
# In each environment's terragrunt.hcl:
terraform {
    source = "../../../infrastructure-modules/vpc"
}
```

Terragrunt downloads a copy of the module into a local `.terragrunt-cache` directory and runs Terraform against it with environment-specific inputs.

### 2. DRY Backend & Provider Configuration
Without Terragrunt, you would need to paste this block into every single module directory:

```hcl
# ❌ Without Terragrunt — repeated in every module
terraform {
  backend "s3" {
    bucket = "s3-terraform-terragrunt-state"
    key    = "dev/vpc/terraform.tfstate"
    ...
  }
}
```

With Terragrunt, this lives once in `root.hcl` and is auto-generated for every module via:

```hcl
# ✅ With Terragrunt — written once in root.hcl, inherited by all
include "root" {
    path = find_in_parent_folders("root.hcl")
}
```

---

## Remote State & Backend

Configured in [infrastructure-live/root.hcl](infrastructure-live/root.hcl):

```hcl
# AWS Provider (auto-generated as providers.tf in each module cache)
generate "provider" {
    path      = "providers.tf"
    if_exists = "overwrite_terragrunt"
    contents  = <<EOF
    provider "aws" {
        region = "us-east-1"
    }
    EOF
}

# Remote State (auto-generated as remote-state.tf in each module cache)
remote_state {
    backend = "s3"
    generate = {
        path      = "remote-state.tf"
        if_exists = "overwrite_terragrunt"
    }
    config = {
        bucket         = "s3-terraform-terragrunt-state"
        key            = "${path_relative_to_include()}/terraform.tfstate"
        region         = "us-east-1"
        encrypt        = true
        dynamodb_table = "s3-terraform-terragrunt-state-locks"
    }
}
```

The `path_relative_to_include()` function automatically generates a unique state key per module, for example:
- `dev/vpc/terraform.tfstate`
- `uat/vpc/terraform.tfstate`
- `prod/vpc/terraform.tfstate`

This ensures each environment's state is completely isolated.

---

## VPC Terraform Module

**Location**: [infrastructure-modules/vpc/](infrastructure-modules/vpc/)

A generic, reusable Terraform module that creates **one VPC and one public subnet**.

### `main.tf` — Resources

```hcl
# VPC
resource "aws_vpc" "main" {
    cidr_block           = var.vpc_cidr         # e.g. "10.0.0.0/16"
    enable_dns_hostnames = true                  # EC2 instances get DNS names
    enable_dns_support   = true                  # Enables DNS resolution in VPC
    tags                 = var.vpc_tags          # Fully customizable via input
}

# Single public subnet inside the VPC
resource "aws_subnet" "public" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = var.public_subnet_cidr  # e.g. "10.0.0.0/24"
    map_public_ip_on_launch = true                    # Auto-assign public IPs
    tags                    = var.subnet_tags
}
```

### `variables.tf` — Inputs

| Variable | Type | Default | Description |
|---|---|---|---|
| `vpc_cidr` | `string` | `10.0.0.0/16` | IPv4 CIDR block for the VPC |
| `public_subnet_cidr` | `string` | `10.0.0.0/24` | IPv4 CIDR block for the public subnet (must be within `vpc_cidr`) |
| `vpc_tags` | `map(string)` | `{Name, Environment, Owner}` | Tags applied to the VPC resource |
| `subnet_tags` | `map(string)` | `{Name, Environment, Tier}` | Tags applied to the subnet resource |

### `outputs.tf` — Outputs

| Output | Value | Description |
|---|---|---|
| `vpc_id` | `aws_vpc.main.id` | The ID of the created VPC |
| `public_subnet_id` | `aws_subnet.public.id` | The ID of the created public subnet |

---

## Environment Configurations

### dev Environment

**File**: [infrastructure-live/dev/vpc/terragrunt.hcl](infrastructure-live/dev/vpc/terragrunt.hcl)

The development environment uses the `10.0.0.0/16` CIDR range, suitable for developer workloads. Owner is tagged as `terragrunt`.

```hcl
inputs = {
    vpc_cidr           = "10.0.0.0/16"
    public_subnet_cidr = "10.0.0.0/24"
    vpc_tags = {
        Name        = "dev-vpc"
        Environment = "dev"
        Owner       = "terragrunt"
    }
    subnet_tags = {
        Name        = "dev-subnet"
        Environment = "dev"
        Tier        = "public"
    }
}
```

---

### uat Environment

**File**: [infrastructure-live/uat/vpc/terragrunt.hcl](infrastructure-live/uat/vpc/terragrunt.hcl)

User acceptance testing environment uses `10.1.0.0/16` — a completely separate non-overlapping range, so it can be peered with dev if needed. Owner is tagged as `platform-team`.

```hcl
inputs = {
    vpc_cidr           = "10.1.0.0/16"
    public_subnet_cidr = "10.1.0.0/24"
    vpc_tags = {
        Name        = "uat-vpc"
        Environment = "uat"
        Owner       = "platform-team"
    }
    subnet_tags = {
        Name        = "uat-subnet"
        Environment = "uat"
        Tier        = "public"
    }
}
```

---

### prod Environment

**File**: [infrastructure-live/prod/vpc/terragrunt.hcl](infrastructure-live/prod/vpc/terragrunt.hcl)

Production uses `10.2.0.0/16`. Note the subnet is `10.2.1.0/24` (not `10.2.0.0/24`), demonstrating flexibility in subnet placement within the VPC range.

```hcl
inputs = {
    vpc_cidr           = "10.2.0.0/16"
    public_subnet_cidr = "10.2.1.0/24"
    vpc_tags = {
        Name        = "prod-vpc"
        Environment = "prod"
        Owner       = "platform-team"
    }
    subnet_tags = {
        Name        = "prod-subnet"
        Environment = "prod"
        Tier        = "public"
    }
}
```

---

## Network Addressing Plan

| Environment | VPC CIDR | Subnet CIDR | Usable IPs |
|---|---|---|---|
| `dev` | `10.0.0.0/16` | `10.0.0.0/24` | 251 |
| `uat` | `10.1.0.0/16` | `10.1.0.0/24` | 251 |
| `prod` | `10.2.0.0/16` | `10.2.1.0/24` | 251 |

> All three VPC ranges are non-overlapping, which means they can be connected via **VPC Peering** or **AWS Transit Gateway** in the future without IP conflicts.

---

## Deployment Workflow

```bash
# Deploy a single environment (e.g. dev)
cd infrastructure-live/dev/vpc
terragrunt init
terragrunt plan
terragrunt apply

# Deploy all environments at once from the live root
cd infrastructure-live
terragrunt apply --all

# Tear down a specific environment
cd infrastructure-live/uat/vpc
terragrunt destroy
```

---

## Useful Commands

| Command | Run From | Description |
|---|---|---|
| `terragrunt init` | Any module dir | Initialize providers and backend |
| `terragrunt validate` | Any module dir | Check HCL syntax validity |
| `terragrunt plan` | Any module dir | Preview resource changes |
| `terragrunt apply` | Any module dir | Apply changes to AWS |
| `terragrunt destroy` | Any module dir | Destroy resources |
| `terragrunt apply --all` | `infrastructure-live/` | Deploy all modules in all environments |
| `terragrunt output` | Applied module dir | Show output values (vpc_id, subnet_id) |
