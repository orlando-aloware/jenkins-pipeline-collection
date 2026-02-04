# Exercise — Deep Dive: Jenkins concurrency, Terraform workspace collisions and safe patterns

This is a detailed, hands-on exercise for a junior engineer to learn how Jenkins handles concurrent builds, the effect of `disableConcurrentBuilds` and `abortPrevious`, and strategies to safely run long Terraform operations so parallel commits don't collide.

Overview
- Goal: reproduce a collision caused by two near-simultaneous triggers that run Terraform in parallel using the same workspace name and S3 bucket name. Use the experiment to learn Jenkins queueing, abort behavior, Lockable Resources usage, and Terraform backend locking (S3 + DynamoDB).
- Outcome: trainee will document the observed failed behaviors and implement/verify at least one mitigation (queueing, lock, idempotent checks, or backend locking).

Prerequisites
- A Jenkins instance and ability to create/modify jobs.
- Terraform >= 1.0 and AWS CLI available on the Jenkins agent or in the workspace.
- Access to a sandbox AWS account or profile (do NOT run this in production).
- The `sandbox` branch in the `jenkins-pipeline-collection` repo for placing artifact files (Jenkinsfile + terraform/). For this unit-test repo we will only store the exercise text and optional helpers under `exercises/`.

Learning objectives (what you'll learn)
- How Jenkins serializes or aborts running builds using `disableConcurrentBuilds` and its `abortPrevious` flag.
- How to scope serialization to critical sections using Lockable Resources so that only resource-sensitive operations (e.g., Terraform apply) are serialized.
- Why killing an in-progress Terraform apply can leave partial resources and cause provider errors.
- How Terraform S3 backend + DynamoDB locking prevents concurrent state mutation.
- How to write idempotent workspace selection/creation and simple pre-checks for S3 bucket existence.
- How to interpret Jenkins console logs and Terraform output to diagnose race conditions.

Repository layout for the exercise
- Place the following files under the `sandbox` branch where your Jenkins pipeline will checkout the project (for trainees who run the pipeline end-to-end):
  - `sandbox-environment/Jenkinsfile` (or pipeline configured to use that Jenkinsfile)
  - `sandbox-environment/terraform/main.tf`
  - `sandbox-environment/terraform/backend.tf` (optional, if you want to test backend locking)
  - `sandbox-environment/scripts/select_or_create_workspace.sh` (helper)

In this unit-test repo, we keep a copy of the exercise description and helper scripts under `exercises/` for convenience.

Exercise artifacts (copy & use as templates)

1) terraform/main.tf (simple S3 bucket)

```hcl
variable "bucket_name" { type = string }

provider "aws" {
  region = "us-west-2"
}

resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name
  acl    = "private"

  tags = {
    ManagedBy = "exercise-jenkins-concurrency"
    Name      = "exercise-${var.bucket_name}"
  }
}

output "bucket" {
  value = aws_s3_bucket.site.id
}
```

2) terraform/backend.tf (optional S3 + DynamoDB backend)

```hcl
terraform {
  backend "s3" {
    bucket         = "your-tfstate-bucket-sandbox"
    key            = "sandbox/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

- Note: create the DynamoDB `terraform-state-locks` table in the AWS sandbox account before using this backend. That table prevents concurrent state writes by acquiring a lock for terraform operations.

3) scripts/select_or_create_workspace.sh (idempotent helper)

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <workspace>" >&2
  exit 2
fi
ws="$1"

retry_cmd() {
  local tries=5
  local base_delay=2
  for i in $(seq 1 "$tries"); do
    if "$@"; then
      return 0
    fi
    sleep $((base_delay * i))
  done
  return 1
}

# Select if exists, otherwise create (with retries)
if terraform workspace list | grep -qw "$ws"; then
  terraform workspace select "$ws"
else
  retry_cmd terraform workspace new "$ws" || terraform workspace select "$ws"
fi
```

Mark the script executable:

```bash
chmod +x sandbox-environment/scripts/select_or_create_workspace.sh
```

4) Jenkinsfile (exercise pipeline)

This Jenkinsfile is intentionally verbose and instructive. The trainee will toggle `abortPrevious` and optionally enable/disable a `lock(...)` wrapper to see differences.

```groovy
pipeline {
  agent any

  // Toggle this option to observe Jenkins behavior:
  // - abortPrevious: true  -> new triggers abort running build (interrupt)
  // - abortPrevious: false -> new triggers are queued
  options {
    disableConcurrentBuilds(abortPrevious: true)
  }

  environment {
    TF_DIR = 'sandbox-environment/terraform'
  }

  stages {
    stage('Prepare') {
      steps {
        script {
          env.SHORTSHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.DATE = sh(script: "date +%b%d-%Y | tr '[:upper:]' '[:lower:]'", returnStdout: true).trim()
          env.BUCKET = "${env.SHORTSHA}-${env.DATE}"
          env.TF_WORKSPACE = "sandbox-${env.SHORTSHA}"

          echo "SHORTSHA=${env.SHORTSHA}"
          echo "BUCKET=${env.BUCKET}"
          echo "TF_WORKSPACE=${env.TF_WORKSPACE}"
        }
      }
    }

    stage('Terraform init') {
      steps {
        dir("${TF_DIR}") {
          sh 'terraform init -input=false || true'
        }
      }
    }

    stage('Terraform critical') {
      steps {
        dir("${TF_DIR}") {
          script {
            // Option A: run without Jenkins lock (observe abort behavior when abortPrevious:true)
            // Option B: uncomment lock(...) to serialize only this critical section

            // lock(resource: "tf-${env.TF_WORKSPACE}") {
              sh '''
                set -euxo pipefail

                echo "Simulating long-running apply (sleep 120s)"
                sleep 120

                # idempotent workspace select/create
                if terraform workspace list | grep -qw "${TF_WORKSPACE}"; then
                  terraform workspace select "${TF_WORKSPACE}"
                else
                  terraform workspace new "${TF_WORKSPACE}" || terraform workspace select "${TF_WORKSPACE}"
                fi

                # Plan and apply
                terraform plan -var "bucket_name=${BUCKET}"
                terraform apply -var "bucket_name=${BUCKET}" -auto-approve
              '''
            // } // end lock
          }
        }
      }
    }

    stage('Verify') {
      steps {
        dir("${TF_DIR}") {
          sh '''
            echo "Current workspace:"
            terraform workspace show || true

            echo "Resource count in state:"
            terraform state list | wc -l || true
          '''
        }
      }
    }
  }

  post {
    always {
      script {
        dir("${TF_DIR}") {
          sh 'terraform workspace select default || true'
        }
      }
    }
  }
}
```

Exercise run guide (step-by-step)

1. Setup
  - Create the `sandbox` branch and put the Jenkinsfile and terraform artifacts into the `sandbox-environment/` folder. Ensure Jenkins job is configured to use this branch and Jenkinsfile.
  - Ensure Terraform and AWS CLI are available on the Jenkins agent.
  - If testing backend locking, create the S3 bucket and DynamoDB table referenced by `backend.tf` in the sandbox account.

2. Scenario A — Abort previous (unsafe)
  - Set `disableConcurrentBuilds(abortPrevious: true)` in Jenkinsfile (this is intended to simulate the repo behavior you observed).
  - Start the job (either push commit or trigger the job).
  - While it sleeps in the Terraform critical section (120s), trigger the job again.
  - Observe: Jenkins will send an interrupt to the first run and start the second run. The first run may fail with provider/plugin errors and leave partial resources.
  - Save logs from both builds.

3. Scenario B — Queue or Lock (safe)
  - Option 1: set `disableConcurrentBuilds(abortPrevious: false)` and run two triggers quickly. The second is queued and will run only after the first finishes.
  - Option 2: leave `abortPrevious: true` (or current global behaviour) but **uncomment** and enable the `lock(resource: ...)` block around the Terraform steps. Ensure the Lockable Resources plugin is installed in Jenkins.
  - Trigger two builds quickly and observe: the second build will wait at the lock and only proceed after the first has released it; the first will not be aborted.

4. Compare logs and document:
  - Console output for both runs in scenario A and B
  - Terraform plan/apply output
  - Any errors encountered (workspace exists, bucket already exists, provider errors)
  - Wall-clock times for each build (start/end) to show overlap

5. Cleanup
  - After experiments, destroy test resources and workspaces:

```bash
cd sandbox-environment/terraform
terraform workspace select default || true
terraform workspace delete sandbox-<shortsha> || true
terraform destroy -var "bucket_name=<shortsha-...>" -auto-approve || true
aws s3 rb s3://<bucket-name> --force || true
```

Discussion points and hints for the trainee
- Why aborting an in-flight Terraform apply is dangerous:
  - Terraform may be mid-way through a provider action (e.g., creating a bucket). Killing the process leaves resources half-created or partially configured.
  - Terraform provider plugins are separate processes; abrupt termination can leave lockfiles or inconsistent state.
- Why a backend with S3 + DynamoDB prevents simultaneous state mutation:
  - Terraform acquires a lock in DynamoDB for the state key before writing state. If a second runner attempts to run, it fails to acquire the lock and will either wait or error depending on retry logic.
- Why name uniqueness avoids collisions but requires cleanup:
  - If each pipeline run uses an effectively-unique name (timestamp/uuid), collisions are unlikely; however this creates orphaned resources unless lifecycle/cleanup is implemented.
- Where to use Jenkins locks vs. global job options:
  - Locking critical sections is flexible and safe; changing job-level `disableConcurrentBuilds` is blunt and affects the entire job lifecycle (sometimes desirable, sometimes not).

Deliverables for evaluation
- Console logs from both builds for scenario A and B
- A short write-up with:
  - What happened in your runs
  - How queue vs abort vs lock changed behavior
  - Your recommended mitigation for production pipelines (short answer: use S3+DynamoDB backend locking plus per-workspace Jenkins locks and idempotent checks)

Optional extensions (extra credit)
- Implement a cleanup Jenkins job that finds `sandbox-*` workspaces older than X hours and destroys them.
- Add an automatic GitHub check that prevents multiple simultaneous deployments from the same branch/PR (e.g., serialize deploys per-pr using a small GitHub App or check-run gating).
- Instrument the Jenkinsfile to produce a JSON artifact summarizing build start/end times, workspace names, and state resource counts.

---

Good luck! When you're done, share logs and the short write-up and we'll review together.
