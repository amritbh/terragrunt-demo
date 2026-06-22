# Project 2: End-To-End EKS Infrastructure

A production-style **Terragrunt + Terraform** monorepo that provisions a complete **Amazon EKS** (Kubernetes) cluster on AWS, including all required networking (VPC), IAM roles, and subnets — with proper inter-module dependency wiring.

This project demonstrates advanced Terragrunt features including **cross-module output references** (`dependency` blocks), **mock outputs** for safe pre-deployment planning, and **ordered stack deployments** with `--all` commands.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [How Terragrunt Works in This Project](#how-terragrunt-works-in-this-project)
4. [Remote State & Backend](#remote-state--backend)
5. [Infrastructure Modules (Reusable)](#infrastructure-modules-reusable)
   - [VPC Module](#vpc-module)
   - [IAM Module](#iam-module)
   - [Subnet Module](#subnet-module)
   - [EKS Module](#eks-module)
6. [Infrastructure Live — dev Environment](#infrastructure-live--dev-environment)
   - [root.hcl](#roothcl)
   - [dev/vpc](#devvpc)
   - [dev/iam](#deviam)
   - [dev/subnet](#devsubnet)
   - [dev/eks](#deveks)
7. [Dependency Graph](#dependency-graph)
8. [Mock Outputs Explained](#mock-outputs-explained)
9. [Deployment Workflow](#deployment-workflow)
10. [Useful Commands](#useful-commands)
11. [Troubleshooting](#troubleshooting)

---

## Project Structure

```
End-To-End-Project/
│
├── infra-structure-modules/         # Reusable Terraform module definitions
│   ├── vpc/
│   │   ├── main.tf                  # aws_vpc resource
│   │   ├── variable.tf              # Input: vpc_cidr_block, environment
│   │   └── output.tf                # Output: vpc_id
│   │
│   ├── iam/
│   │   ├── main.tf                  # aws_iam_role + 2x aws_iam_role_policy_attachment
│   │   ├── variable.tf              # Input: environment
│   │   └── output.tf                # Output: eks_role_arn, eks_role_id
│   │
│   ├── subnet/
│   │   ├── main.tf                  # aws_subnet (×2 across AZs), data source for AZs
│   │   ├── variable.tf              # Input: vpc_id, vpc_cidr, environment
│   │   └── output.tf                # Output: subnet_ids (list)
│   │
│   └── eks/
│       ├── main.tf                  # aws_eks_cluster
│       ├── variable.tf              # Input: environment, iam_role_arn, subnet_ids
│       └── output.tf                # (empty — no downstream consumers yet)
│
└── infrastructure-live/             # Environment-specific Terragrunt wiring
    ├── root.hcl                     # Shared backend + AWS provider (inherited by all)
    └── dev/                         # "dev" environment stack
        ├── vpc/
        │   └── terragrunt.hcl       # VPC inputs + no dependencies
        ├── iam/
        │   └── terragrunt.hcl       # IAM inputs + no dependencies
        ├── subnet/
        │   └── terragrunt.hcl       # Subnet inputs + depends on vpc
        └── eks/
            └── terragrunt.hcl       # EKS inputs + depends on iam + subnet
```

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                           AWS Account (us-east-1)                  │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    dev VPC  (10.0.0.0/16)                   │   │
│  │                                                             │   │
│  │  ┌──────────────────────┐  ┌──────────────────────────────┐ │   │
│  │  │  dev-subnet-1        │  │  dev-subnet-2                │ │   │
│  │  │  10.0.0.0/24         │  │  10.0.1.0/24                 │ │   │
│  │  │  us-east-1a (public) │  │  us-east-1b (public)         │ │   │
│  │  └──────────┬───────────┘  └───────────┬──────────────────┘ │   │
│  │             │                          │                     │   │
│  │             └────────────┬─────────────┘                    │   │
│  │                          ▼                                   │   │
│  │           ┌──────────────────────────┐                      │   │
│  │           │   EKS Cluster            │◄──── IAM Role        │   │
│  │           │   dev-eks-cluster        │      dev-eks-        │   │
│  │           │   (managed control plane)│      cluster-role    │   │
│  │           └──────────────────────────┘                      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  S3: s3-terraform-terragrunt-state  (Terraform state files)        │
│  DynamoDB: s3-terraform-terragrunt-state-locks  (State locking)    │
└────────────────────────────────────────────────────────────────────┘
```

### Resources Provisioned

| Resource | Name | Purpose |
|---|---|---|
| `aws_vpc` | `dev-vpc` | Isolated network for all resources |
| `aws_subnet` (×2) | `dev-subnet-1`, `dev-subnet-2` | Public subnets across 2 AZs |
| `aws_iam_role` | `dev-eks-cluster-role` | EKS control plane identity |
| `aws_iam_role_policy_attachment` (×2) | — | Grants EKS required AWS permissions |
| `aws_eks_cluster` | `dev-eks-cluster` | Managed Kubernetes control plane |

---

## How Terragrunt Works in This Project

### The `include` block — inheriting root configuration

Every `terragrunt.hcl` file starts with:

```hcl
include {
    path = find_in_parent_folders("root.hcl")
}
```

`find_in_parent_folders()` walks up the directory tree until it finds `root.hcl`. This is how backend configuration and the AWS provider are shared across all modules without any copy-pasting.

### The `terraform` block — pointing to a module

```hcl
terraform {
    source = "../../../infra-structure-modules/vpc"
}
```

Terragrunt copies the source module into a local `.terragrunt-cache` directory and runs standard Terraform commands against it. The source path uses relative references (`../`) to navigate from the environment directory to the shared module.

### The `dependency` block — reading another module's outputs

```hcl
dependency "vpc" {
    config_path = "../vpc"   # Path to the sibling vpc module
}

inputs = {
    vpc_id = dependency.vpc.outputs.vpc_id   # Read the vpc_id output from the vpc module
}
```

This is how the subnet module gets the `vpc_id` without hardcoding it — Terragrunt reads the real output value stored in the remote S3 state file of the `vpc` module.

### The `inputs` block — passing variable values

```hcl
inputs = {
    environment    = "dev"
    vpc_cidr_block = "10.0.0.0/16"
}
```

These values are passed as Terraform input variables to the module. No `terraform.tfvars` files are needed.

---

## Remote State & Backend

Configured in [infrastructure-live/root.hcl](infrastructure-live/root.hcl):

```hcl
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

| Setting | Value | Purpose |
|---|---|---|
| `bucket` | `s3-terraform-terragrunt-state` | S3 bucket storing all `.tfstate` files |
| `key` | Auto-generated from module path | Unique state file per module (e.g., `End-To-End-Project/infrastructure-live/dev/vpc/terraform.tfstate`) |
| `encrypt` | `true` | AES-256 server-side encryption at rest |
| `dynamodb_table` | `s3-terraform-terragrunt-state-locks` | Prevents two simultaneous `apply` runs from corrupting state |

---

## Infrastructure Modules (Reusable)

### VPC Module

**Location**: [infra-structure-modules/vpc/](infra-structure-modules/vpc/)

Creates an AWS VPC that acts as the isolated network boundary for the entire stack.

#### Resources Created

```hcl
resource "aws_vpc" "main" {
    cidr_block           = var.vpc_cidr_block   # "10.0.0.0/16"
    enable_dns_hostnames = true                  # EC2 instances receive DNS hostnames
    enable_dns_support   = true                  # DNS queries resolve within the VPC
    tags = {
        Name        = "${var.environment}-vpc"   # e.g. "dev-vpc"
        Environment = var.environment
    }
}
```

#### Inputs

| Variable | Type | Description |
|---|---|---|
| `vpc_cidr_block` | `string` | IPv4 CIDR for the VPC (e.g. `10.0.0.0/16`) |
| `environment` | `string` | Environment name for naming and tagging |

#### Outputs

| Output | Used By |
|---|---|
| `vpc_id` | Subnet module — to attach subnets to this VPC |

---

### IAM Module

**Location**: [infra-structure-modules/iam/](infra-structure-modules/iam/)

Creates the **IAM Role** that the EKS control plane service assumes, plus attaches two AWS-managed policies granting it the necessary permissions to operate.

#### Resources Created

```hcl
# 1. The trust-policy role — allows EKS service to assume it
resource "aws_iam_role" "eks-cluster-role" {
    name = "${var.environment}-eks-cluster-role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect    = "Allow"
            Principal = { Service = "eks.amazonaws.com" }
            Action    = "sts:AssumeRole"
        }]
    })
}

# 2. AmazonEKSClusterPolicy — manage EC2, ELB, security groups, etc.
resource "aws_iam_role_policy_attachment" "eks-cluster-policy" {
    role       = aws_iam_role.eks-cluster-role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# 3. AmazonEKSServicePolicy — manage ENIs for pod networking
resource "aws_iam_role_policy_attachment" "eks-service-policy" {
    role       = aws_iam_role.eks-cluster-role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}
```

#### Inputs

| Variable | Type | Description |
|---|---|---|
| `environment` | `string` | Environment name for naming the IAM role |

#### Outputs

| Output | Used By |
|---|---|
| `eks_role_arn` | EKS module — passed as `role_arn` to the cluster |
| `eks_role_id` | Available for reference (not consumed downstream yet) |

---

### Subnet Module

**Location**: [infra-structure-modules/subnet/](infra-structure-modules/subnet/)

Dynamically creates **two public subnets** across two separate Availability Zones. EKS requires subnets in at least two AZs for control plane high availability.

#### Resources Created

```hcl
# Dynamically discovers available AZs — no hardcoding needed
data "aws_availability_zones" "available" {
    state = "available"
}

resource "aws_subnet" "main" {
    count = min(2, length(data.aws_availability_zones.available.names))

    vpc_id            = var.vpc_id
    # cidrsubnet("10.0.0.0/16", 8, 0) → "10.0.0.0/24"  (subnet 1)
    # cidrsubnet("10.0.0.0/16", 8, 1) → "10.0.1.0/24"  (subnet 2)
    cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
    availability_zone = data.aws_availability_zones.available.names[count.index]

    map_public_ip_on_launch = true  # Instances launched here get a public IP

    tags = {
        Name        = "${var.environment}-subnet-${count.index + 1}"
        Environment = var.environment

        # Required by AWS Load Balancer Controller to discover these subnets
        "kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"
        "kubernetes.io/role/elb"                               = "1"
    }
}
```

> **How `cidrsubnet` works**: It extends the prefix length of the VPC CIDR by 8 bits (`/16` → `/24`), then selects the Nth block (where N = `count.index`). With VPC CIDR `10.0.0.0/16`:
> - Index 0 → `10.0.0.0/24` (256 addresses, us-east-1a)
> - Index 1 → `10.0.1.0/24` (256 addresses, us-east-1b)

> **⚠️ Important**: The `vpc_cidr` input **must match** the VPC module's `vpc_cidr_block` exactly. A mismatch causes AWS to reject subnets as out-of-range (since the calculated subnet CIDRs would fall outside the VPC).

#### Inputs

| Variable | Type | Description |
|---|---|---|
| `vpc_id` | `string` | ID of the parent VPC (from VPC module output) |
| `vpc_cidr` | `string` | VPC CIDR used to calculate subnet ranges — must match VPC |
| `environment` | `string` | Environment name for naming and Kubernetes tags |

#### Outputs

| Output | Used By |
|---|---|
| `subnet_ids` | EKS module — list of subnet IDs for the cluster's `vpc_config` |

---

### EKS Module

**Location**: [infra-structure-modules/eks/](infra-structure-modules/eks/)

Creates the **Amazon EKS managed control plane**. EKS manages the Kubernetes API server, etcd, scheduler, and controller manager — you only supply the IAM role and subnets.

#### Resources Created

```hcl
resource "aws_eks_cluster" "main" {
    name     = "${var.environment}-eks-cluster"   # e.g. "dev-eks-cluster"
    role_arn = var.iam_role_arn                   # IAM role from iam module

    vpc_config {
        subnet_ids = var.subnet_ids               # Subnets from subnet module
        # EKS places cross-account ENIs into these subnets for pod networking
    }

    tags = {
        Name        = "${var.environment}-eks-cluster"
        Environment = var.environment
    }
}
```

> **Note**: This module provisions only the EKS **control plane**. Worker node groups (EC2 managed node groups or Fargate profiles) would be added as a separate module in a future iteration.

#### Inputs

| Variable | Type | Description |
|---|---|---|
| `environment` | `string` | Cluster name prefix (e.g. `dev` → `dev-eks-cluster`) |
| `iam_role_arn` | `string` | ARN of the IAM role the EKS control plane assumes |
| `subnet_ids` | `list(string)` | Subnet IDs across ≥2 AZs for EKS networking |

---

## Infrastructure Live — dev Environment

### root.hcl

**Location**: [infrastructure-live/root.hcl](infrastructure-live/root.hcl)

The shared configuration file inherited by all child `terragrunt.hcl` files. Generates two files inside each module's `.terragrunt-cache`:
- **`providers.tf`** — declares the `hashicorp/aws` provider targeting `us-east-1`
- **`remote-state.tf`** — configures the S3 backend with unique per-module state file paths

---

### dev/vpc

**Location**: [infrastructure-live/dev/vpc/terragrunt.hcl](infrastructure-live/dev/vpc/terragrunt.hcl)

Deploys the VPC module. Has **no dependencies** on other modules.

```hcl
inputs = {
    environment    = "dev"
    vpc_cidr_block = "10.0.0.0/16"
}
```

---

### dev/iam

**Location**: [infrastructure-live/dev/iam/terragrunt.hcl](infrastructure-live/dev/iam/terragrunt.hcl)

Deploys the IAM module. Has **no dependencies** on other modules (IAM is a global AWS service, independent of networking).

```hcl
inputs = {
    environment = "dev"
}
```

---

### dev/subnet

**Location**: [infrastructure-live/dev/subnet/terragrunt.hcl](infrastructure-live/dev/subnet/terragrunt.hcl)

Deploys the subnet module. **Depends on VPC** to read the `vpc_id` output.

```hcl
dependency "vpc" {
    config_path = "../vpc"

    # Mock outputs allow plan/validate/init commands to run
    # before the VPC has actually been deployed
    mock_outputs = {
        vpc_id = "mock-vpc-id"
    }
    mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
}

inputs = {
    environment = "dev"
    vpc_cidr    = "10.0.0.0/16"           # ← Must match dev/vpc vpc_cidr_block
    vpc_id      = dependency.vpc.outputs.vpc_id
}
```

---

### dev/eks

**Location**: [infrastructure-live/dev/eks/terragrunt.hcl](infrastructure-live/dev/eks/terragrunt.hcl)

Deploys the EKS cluster. **Depends on both IAM and Subnet** modules.

```hcl
dependency "iam" {
    config_path = "../iam"
    mock_outputs = {
        eks_role_arn = "arn:aws:iam::123456789012:role/mock-role"
    }
    mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
}

dependency "subnet" {
    config_path = "../subnet"
    mock_outputs = {
        subnet_ids = ["mock-subnet-id-1", "mock-subnet-id-2"]
    }
    mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
}

inputs = {
    environment  = "dev"
    iam_role_arn = dependency.iam.outputs.eks_role_arn
    subnet_ids   = dependency.subnet.outputs.subnet_ids
}
```

---

## Dependency Graph

Terragrunt builds this dependency graph automatically before any `--all` command:

```
     ┌─────────┐       ┌─────────┐
     │   vpc   │       │   iam   │
     └────┬────┘       └────┬────┘
          │                 │
          ▼                 │
     ┌──────────┐           │
     │  subnet  │◄──────────┘
     └────┬─────┘
          │
          ▼
       ┌─────┐
       │ eks │
       └─────┘

Step 1 (parallel): vpc + iam     (no inter-dependencies)
Step 2:            subnet        (needs vpc_id from vpc)
Step 3:            eks           (needs eks_role_arn from iam, subnet_ids from subnet)
```

When you run `terragrunt apply --all`, Terragrunt:
1. **Reads** all `terragrunt.hcl` files recursively.
2. **Builds** the dependency DAG from `dependency` blocks.
3. **Executes** modules in topological order, running independent modules in parallel.

---

## Mock Outputs Explained

When you run `terragrunt plan` or `terragrunt validate` before any modules are deployed, there are no real outputs stored in S3. Without mocks, Terragrunt would fail trying to read `vpc_id` from an empty state file.

**Mock outputs** solve this by providing placeholder values for these pre-deployment runs:

```hcl
dependency "vpc" {
    config_path = "../vpc"

    mock_outputs = {
        vpc_id = "mock-vpc-id"       # Placeholder used only during plan/validate/init
    }
    mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
    # ↑ Only use mocks for these safe read-only commands, never for apply
}
```

> **⚠️ Mock ARN requirement**: Mock IAM role ARNs must use a valid 12-digit AWS account ID (e.g., `123456789012`). The AWS provider validates ARN format even during plan, so a 10-digit or otherwise invalid account ID will cause plan to fail.

---

## Deployment Workflow

### Prerequisites

- AWS CLI configured with appropriate credentials and permissions
- Terragrunt installed (`brew install terragrunt`)
- Terraform installed (Terragrunt uses it internally)
- S3 bucket `s3-terraform-terragrunt-state` exists in `us-east-1`
- DynamoDB table `s3-terraform-terragrunt-state-locks` exists in `us-east-1`

### Full Stack Deployment

```bash
cd End-To-End-Project/infrastructure-live/dev

# Step 1: Initialize all modules (downloads providers, configures backends)
terragrunt init --all

# Step 2: Validate all configurations
terragrunt validate --all

# Step 3: Preview all changes
terragrunt plan --all

# Step 4: Deploy everything in dependency order
terragrunt apply --all
```

### Deploy Individual Modules

```bash
# Deploy only the VPC
cd End-To-End-Project/infrastructure-live/dev/vpc
terragrunt apply

# Deploy only the subnet (vpc must already be applied)
cd End-To-End-Project/infrastructure-live/dev/subnet
terragrunt apply
```

### Tear Down

```bash
cd End-To-End-Project/infrastructure-live/dev

# Destroys in reverse dependency order: eks → subnet → iam + vpc
terragrunt destroy --all
```

---

## Useful Commands

| Command | Description |
|---|---|
| `terragrunt init --all` | Initialize all modules (backend + providers) |
| `terragrunt validate --all` | Validate all configurations |
| `terragrunt plan --all` | Preview all resource changes |
| `terragrunt apply --all` | Deploy entire stack in dependency order |
| `terragrunt destroy --all` | Destroy entire stack in reverse order |
| `terragrunt output` | Show output values of an applied module |
| `terragrunt graph-dependencies` | Visualize the dependency graph |

---

## Troubleshooting

### `Missing label for dependency`
A `dependency` block is missing its required name label.
```hcl
# ❌ Wrong
dependency { config_path = "../vpc" }

# ✅ Correct
dependency "vpc" { config_path = "../vpc" }
```

### `InvalidSubnet.Range: The CIDR is invalid`
The `vpc_cidr` passed to the subnet module doesn't match the VPC's actual CIDR block. The `cidrsubnet()` function calculates subnets relative to `vpc_cidr` — if they don't align, AWS rejects them as out-of-range.

**Fix**: Ensure `vpc_cidr` in `dev/subnet/terragrunt.hcl` exactly matches `vpc_cidr_block` in `dev/vpc/terragrunt.hcl`.

### `invalid account ID value` in mock ARN
AWS IAM ARNs require exactly 12 digits in the account ID field.
```hcl
# ❌ Wrong (10 digits)
eks_role_arn = "arn:aws:iam::1234567890:role/mock-role"

# ✅ Correct (12 digits)
eks_role_arn = "arn:aws:iam::123456789012:role/mock-role"
```

### `This object does not have an attribute named "X"`
The key in `mock_outputs` doesn't match the actual output name in the source module's `output.tf`, or the output is not defined at all.

**Fix**: Check the source module's `output.tf` and ensure the key in `mock_outputs` and the reference in `inputs` both use the exact same name.

### `Unknown variable "dependency"`
The `dependency` reference is used in `inputs` but `"init"` is missing from `mock_outputs_allowed_terraform_commands`.

**Fix**: Add `"init"` to the `mock_outputs_allowed_terraform_commands` list.
```hcl
mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
```
