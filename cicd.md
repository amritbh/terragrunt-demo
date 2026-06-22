# CI/CD Pipeline Documentation

This document explains the GitHub Actions CI/CD pipelines that automate the planning and deployment of Terraform infrastructure managed by Terragrunt.

---

## Table of Contents

1. [Overview](#overview)
2. [Repository Branch Strategy](#repository-branch-strategy)
3. [Workflow Files](#workflow-files)
4. [Workflow 1 — End-To-End-Project (dev EKS Stack)](#workflow-1--end-to-end-project-dev-eks-stack)
5. [Workflow 2 — VPC Multi-Environment (dev / uat / prod)](#workflow-2--vpc-multi-environment-dev--uat--prod)
6. [Pipeline Execution Flow](#pipeline-execution-flow)
7. [Required Configuration](#required-configuration)
   - [GitHub Secrets](#github-secrets)
   - [GitHub Environments](#github-environments)
   - [IAM Permissions Required](#iam-permissions-required)
8. [How to Activate the Pipelines](#how-to-activate-the-pipelines)
9. [PR Plan Comments](#pr-plan-comments)
10. [Approval Gates](#approval-gates)
11. [Troubleshooting](#troubleshooting)

---

## Overview

The CI/CD pipelines follow the **Plan on PR, Apply on Merge** pattern:

| Event | Action |
|---|---|
| Pull Request opened/updated | `terragrunt plan` — previews infrastructure changes, posts output as a PR comment |
| Pull Request merged into `main` | `terragrunt apply` — deploys actual infrastructure changes to AWS |

This ensures **no infrastructure change is ever applied without a human first reviewing the plan output**.

---

## Repository Branch Strategy

```
main        ← production-ready code; Apply runs here
  └── cicd  ← branch where CI/CD workflows are developed
  └── feature/xyz  ← feature branches; PRs to main trigger Plan
```

| Branch | Purpose |
|---|---|
| `main` | Protected branch; triggers `apply` on push |
| `cicd` | CI/CD workflow development branch (merge to `main` to activate) |

---

## Workflow Files

Both workflow files live in [`.github/workflows/`](.github/workflows/):

| File | Project | Environments |
|---|---|---|
| [`terragrunt-e2e-dev.yml`](.github/workflows/terragrunt-e2e-dev.yml) | End-To-End-Project | `dev` only |
| [`terragrunt-vpc-multienv.yml`](.github/workflows/terragrunt-vpc-multienv.yml) | Project 1 (VPC) | `dev` → `uat` → `prod` |

---

## Workflow 1 — End-To-End-Project (dev EKS Stack)

**File**: [`.github/workflows/terragrunt-e2e-dev.yml`](.github/workflows/terragrunt-e2e-dev.yml)

Manages the full EKS infrastructure stack in the `End-To-End-Project/infrastructure-live/dev/` directory, which includes VPC, IAM, Subnet, and EKS modules.

### Triggers

```yaml
on:
  pull_request:
    paths: ['End-To-End-Project/**']   # Only runs when these files change
  push:
    branches: [main]
    paths: ['End-To-End-Project/**']
```

### Jobs

#### `plan` (Pull Requests only)

```
Checkout → Configure AWS → Install Terraform → Install Terragrunt
  → terragrunt init --all
  → terragrunt validate --all
  → terragrunt plan --all        ← output saved to file
  → Post plan output as PR comment
```

#### `apply` (Push to main only)

```
Checkout → Configure AWS → Install Terraform → Install Terragrunt
  → terragrunt init --all
  → terragrunt apply --all       ← deploys to AWS
```

> The `apply` job uses the `dev` GitHub Environment. If you configure a required reviewer on the `dev` environment, a human must approve before `apply` runs.

### Execution Order of Terragrunt Modules (resolved automatically)

```
Step 1 (parallel):  vpc + iam
Step 2:             subnet       (waits for vpc)
Step 3:             eks          (waits for iam + subnet)
```

---

## Workflow 2 — VPC Multi-Environment (dev / uat / prod)

**File**: [`.github/workflows/terragrunt-vpc-multienv.yml`](.github/workflows/terragrunt-vpc-multienv.yml)

Manages the VPC infrastructure in `infrastructure-live/` across three environments, applying in a sequential promotion chain: `dev` → `uat` → `prod`.

### Triggers

```yaml
on:
  pull_request:
    paths: ['infrastructure-live/**', 'infrastructure-modules/**']
  push:
    branches: [main]
    paths: ['infrastructure-live/**', 'infrastructure-modules/**']
```

### Jobs

#### `plan` (Pull Requests only — runs all 3 environments in parallel)

```
Matrix: [dev, uat, prod]
  ↓ (each runs simultaneously)
  Checkout → Configure AWS → Install Tools
  → terragrunt init
  → terragrunt plan          ← posts per-environment comment to PR
```

#### `apply-dev` → `apply-uat` → `apply-prod` (Push to main — sequential)

```
apply-dev   → terragrunt apply (dev VPC)
    ↓ (on success)
apply-uat   → [awaits manual approval if env protection is set]
              → terragrunt apply (uat VPC)
    ↓ (on success)
apply-prod  → [awaits manual approval]
              → terragrunt apply (prod VPC)
```

This sequential promotion ensures that changes are verified in lower environments before reaching production.

---

## Pipeline Execution Flow

### On Pull Request

```
Developer pushes feature branch
         │
         ▼
  GitHub Actions triggered
         │
         ▼
  ┌─────────────────────────────────────┐
  │  Job: plan                          │
  │  1. Install Terraform + Terragrunt  │
  │  2. Configure AWS credentials       │
  │  3. terragrunt init --all           │
  │  4. terragrunt validate --all       │
  │  5. terragrunt plan --all           │
  │  6. Post plan output → PR comment   │
  └─────────────────────────────────────┘
         │
         ▼
  Developer reviews plan in PR comment
         │
         ▼
  Developer approves and merges PR
```

### On Merge to main

```
PR merged to main
         │
         ▼
  GitHub Actions triggered
         │
         ▼
  ┌─────────────────────────────────────┐
  │  Job: apply                         │
  │  1. Install Terraform + Terragrunt  │
  │  2. Configure AWS credentials       │
  │  3. [Optional: await approval]      │
  │  4. terragrunt init --all           │
  │  5. terragrunt apply --all          │
  └─────────────────────────────────────┘
         │
         ▼
  Infrastructure deployed to AWS
```

---

## Required Configuration

### GitHub Secrets

Navigate to: **GitHub → Repository → Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Value | Required For |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key ID | Both workflows |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret access key | Both workflows |

> **Security tip**: Create a dedicated IAM user for CI/CD with only the permissions listed below. Never use root account credentials.

---

### GitHub Environments

Navigate to: **GitHub → Repository → Settings → Environments → New environment**

Create the following environments and configure protection rules as needed:

| Environment | Recommended Protection |
|---|---|
| `dev` | None — auto-deploys immediately on merge |
| `uat` | Required reviewers: add yourself or your team lead |
| `prod` | Required reviewers + optional wait timer (e.g. 30 min) |

**How to add a required reviewer**:
1. Open the environment (e.g. `uat`)
2. Enable **Required reviewers**
3. Add GitHub usernames who must approve before apply runs

---

### IAM Permissions Required

The AWS IAM user/role used in CI/CD needs the following permissions:

#### For the EKS stack (End-To-End-Project)

| Service | Actions Needed |
|---|---|
| `EC2` | Create/Describe/Delete VPCs, Subnets, Security Groups |
| `EKS` | Create/Describe/Delete clusters |
| `IAM` | Create/Attach/Delete roles and policies |
| `S3` | Read/Write to the Terraform state bucket |
| `DynamoDB` | Read/Write to the state lock table |

#### For the VPC project

| Service | Actions Needed |
|---|---|
| `EC2` | Create/Describe/Delete VPCs, Subnets |
| `S3` | Read/Write to the Terraform state bucket |
| `DynamoDB` | Read/Write to the state lock table |

#### Minimum IAM Policy (example)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:GetRole",
        "iam:PassRole",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## How to Activate the Pipelines

The workflow files currently live on the `cicd` branch. GitHub Actions only executes workflows that exist on the **default branch** (`main`) for push/PR events.

**Steps to activate:**

1. Open a Pull Request from `cicd` → `main` on GitHub
2. Review the workflow files in the PR diff
3. Merge the PR
4. The workflows are now active — any future PR touching `End-To-End-Project/**` or `infrastructure-live/**` will trigger them

---

## PR Plan Comments

When a Pull Request is opened or updated, the pipeline automatically posts the `terragrunt plan` output as a **collapsible comment** on the PR:

```
## 🔍 Terragrunt Plan — `dev` environment

<details><summary>Click to expand plan output</summary>

Terraform will perform the following actions:
  # aws_vpc.main will be created
  + resource "aws_vpc" "main" {
      ...
  }

Plan: 1 to add, 0 to change, 0 to destroy.
</details>

Plan exit code: `0`
```

This allows the reviewer to see exactly what will change in AWS before approving the merge.

---

## Approval Gates

The `uat` and `prod` apply jobs are gated behind **GitHub Environments with required reviewers**. When the pipeline reaches one of these jobs:

1. GitHub sends an **email notification** to all required reviewers
2. The job is **paused** until someone approves or rejects
3. Reviewer clicks **"Review deployments"** in the GitHub Actions UI
4. After approval, the job continues and applies the infrastructure

This creates a full audit trail of who approved each deployment.

---

## Troubleshooting

### `Error: credentials not found`
The GitHub Secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are missing or named incorrectly.
**Fix**: Go to Settings → Secrets → Actions and verify the secret names match exactly.

### `AccessDeniedException` during plan or apply
The IAM user doesn't have sufficient permissions.
**Fix**: Attach the required policies to the IAM user used for CI/CD.

### Plan passes but apply fails with state lock error
Another `apply` run is holding the DynamoDB state lock (possibly a stuck run).
**Fix**: Go to DynamoDB → `s3-terraform-terragrunt-state-locks` table and manually delete the lock item, or cancel the stuck GitHub Actions run.

### Workflow doesn't trigger on PR
The workflow file isn't on the `main` branch yet.
**Fix**: Merge the `cicd` branch into `main` first.

### `terragrunt: command not found`
The Terragrunt install step failed, usually due to a network issue in the runner.
**Fix**: Re-run the failed job from the GitHub Actions UI. If it persists, pin the download URL to a specific release version.
