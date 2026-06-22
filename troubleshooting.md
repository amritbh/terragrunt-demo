# Terragrunt CI/CD Troubleshooting Guide

This guide documents the common issues encountered during the setup and execution of the Terragrunt CI/CD pipelines, along with their root causes and verified solutions.

---

## Table of Contents

1. [Git Push Fails Due to Large Files Exceeding 100MB](#1-git-push-fails-due-to-large-files-exceeding-100mb)
2. [Workflow Fails with `flag provided but not defined: -terragrunt-non-interactive`](#2-workflow-fails-with-flag-provided-but-not-defined--terragrunt-non-interactive)
3. [Workflow Plan Succeeds but Apply Fails on State Lock](#3-workflow-plan-succeeds-but-apply-fails-on-state-lock)
4. [Missing Dependencies (`Unknown variable "dependency"`)](#4-missing-dependencies-unknown-variable-dependency)

---

## 1. Git Push Fails Due to Large Files Exceeding 100MB

### Symptoms
When running `git push`, you receive an error similar to this:
```
remote: error: File .../.terraform/providers/.../terraform-provider-aws_v6.51.0_x5 is 796.99 MB; this exceeds GitHub's file size limit of 100.00 MB
remote: error: GH001: Large files detected. You may want to try Git Large File Storage - https://git-lfs.github.com.
 ! [remote rejected] main -> main (pre-receive hook declined)
error: failed to push some refs to 'https://github.com/amritbh/terragrunt-demo.git'
```

### Root Cause
When you run `terragrunt init` locally, it downloads the AWS Terraform provider binary inside the `.terragrunt-cache/` and `.terraform/` directories. This binary can be nearly 800MB. If these directories are not ignored, `git commit` will capture them, and GitHub will hard-reject the push because it exceeds the strict 100MB per-file limit.

### Solution

Simply deleting the files and committing is **not enough** because the large file remains in your Git commit history, which GitHub scans. You must remove it from history entirely.

**Step 1. Create a proper `.gitignore`**
```gitignore
# Terragrunt cache directories
**/.terragrunt-cache/

# Terraform cache and state
**/.terraform/
**/.terraform.lock.hcl
*.tfstate
*.tfstate.backup

# Terraform plan files
*.tfplan
```

**Step 2. Rewrite Git History (if the large file is in the very first commit)**
If this was your first commit, the easiest way to purge the history is to create a clean orphan branch:
```bash
# Create a new branch with no history
git checkout --orphan newmain

# Add all files (the .gitignore will automatically exclude the caches this time)
git add -A

# Commit the clean state
git commit -m "Initial commit: terragrunt modules"

# Replace the old main branch
git branch -D main
git branch -m main

# Force push to GitHub
git push -u origin main --force
```

---

## 2. Workflow Fails due to Interactive Prompts / Flag Parsing Errors

### Symptoms
When running `terragrunt apply` in GitHub Actions, you might encounter two different errors depending on how you configure the command:

**Error A (Flag parsing failure on init/plan):**
```
* Failed to execute "terraform init -terragrunt-non-interactive"
  │ Error: Failed to parse command-line flags
  │ flag provided but not defined: -terragrunt-non-interactive
```

**Error B (EOF failure on apply):**
```
Are you sure you want to run 'terragrunt apply' in each unit of the run queue displayed above? (y/n) 
ERROR  EOF
Process completed with exit code 1.
```

### Root Cause
In Terragrunt v1.0.1 (and newer CLI redesign versions), passing the old `--terragrunt-non-interactive` flag inline can cause Terragrunt to incorrectly forward the flag down to the underlying `terraform` binary, resulting in Error A. 

However, if you simply remove all non-interactive flags, Terragrunt defaults to prompting for a `(y/n)` confirmation during the `apply` phase. Because GitHub Actions doesn't have a human to type "y", it immediately throws an EOF error (Error B).

### Solution
To properly run Terragrunt in CI without interactive prompts, you must bypass **both** Terragrunt's prompt and Terraform's prompt simultaneously using the correct combination of Environment Variables and flags.

**Step 1. Set the Environment Variable**
In your `.github/workflows/` YAML, define `TERRAGRUNT_NON_INTERACTIVE` globally. This tells Terragrunt itself not to ask `(y/n)`.

```yaml
env:
  TERRAGRUNT_NON_INTERACTIVE: "true"
```

**Step 2. Use `-auto-approve` for Apply**
Remove the deprecated `--terragrunt-non-interactive` flag from all commands. For `apply` and `destroy` commands, append `-auto-approve` to bypass the underlying Terraform prompt.

```yaml
# Correct Init / Plan (No flags needed)
run: terragrunt init --all
run: terragrunt plan --all

# Correct Apply / Destroy (Needs -auto-approve)
run: terragrunt apply --all -auto-approve
run: terragrunt destroy --all -auto-approve
```

---

## 3. Workflow Plan Succeeds but Apply Fails on State Lock

### Symptoms
The PR `plan` job passes, but when merged to main, the `apply` job fails with:
```
Error: Error acquiring the state lock
Error message: ConditionalCheckFailedException: The conditional request failed
Lock Info:
  ID:        1a2b3c4d-5e6f-7g8h-9i0j-1k2l3m4n5o6p
  Operation: OperationTypePlan
```

### Root Cause
Another workflow run (or a local developer) currently holds the lock for this environment in the DynamoDB `terragrunt-state-locks` table. This often happens if a previous CI/CD run was manually cancelled mid-execution, leaving the lock "orphaned."

### Solution
1. Ensure no other workflows or team members are currently running `apply` for that environment.
2. Go to the AWS Console → **DynamoDB** → **Tables** → `s3-terraform-terragrunt-state-locks`.
3. Click **Explore table items**.
4. Find the item matching the path of the failed module (e.g., `dev/vpc/terraform.tfstate`) and delete it.
5. Re-run the failed GitHub Action job.

---

## 4. Missing Dependencies (`Unknown variable "dependency"`)

### Symptoms
When running `terragrunt plan` on a PR, or when running `terragrunt destroy` on an environment that hasn't been deployed yet, it fails with:
```
ERRO[0000] This object does not have an attribute named "vpc_id".
```
OR
```
ERRO[0000] Unknown variable "dependency"
```

### Root Cause
When evaluating modules in a CI environment during `plan` (or `destroy`), upstream resources (like the VPC) might not exist yet, meaning they don't have real outputs saved in the S3 state file for downstream modules (like Subnet) to read.

### Solution
Ensure every `dependency` block in `terragrunt.hcl` includes `mock_outputs` and correctly whitelists **all** commands that might need to evaluate the file before resources exist (including `destroy` for manual teardowns of broken/unapplied environments):

```hcl
dependency "vpc" {
    config_path = "../vpc"

    mock_outputs = {
        vpc_id = "mock-vpc-id"
    }
    
    # CRITICAL: Without this line, the mock outputs won't be used!
    mock_outputs_allowed_terraform_commands = ["plan", "validate", "init", "destroy"]
}
```

> **Warning for IAM Roles**: If you are mocking an IAM Role ARN, AWS strictly validates that the mock ARN contains exactly **12 digits** in the account ID field (e.g., `arn:aws:iam::123456789012:role/mock-role`). Using a fake 10-digit account ID will cause plan to fail validation.
