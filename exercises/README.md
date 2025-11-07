# Exercise: Jenkins pipeline + Terraform workspace collision

Objective
---------
Create a Jenkins pipeline and Terraform configuration that deploys an S3-backed static site with a CloudFront distribution, using a Terraform workspace named `sandbox-<SHORT_SHA>` and a bucket named `<SHORT_SHA>-nov7-2025` (current date). The goal is to intentionally cause a resource collision when the pipeline runs twice with the same SHORT_SHA: the second run should fail because the Terraform workspace and S3 bucket already exist.

Why this exercise
------------------
This teaches:
- How Jenkins pipelines can drive Terraform operations.
- How Terraform workspaces and state interact with repeated runs.
- How to reproduce and diagnose resource collisions (existing workspace / existing S3 bucket).

What to add in the repository
----------------------------
Path: `jenkins-pipeline-collection/sandbox/sandbox-environment/Jenkinsfile` (branch: `sandbox`)
Place the Terraform configuration in the same folder (relative path `jenkins-pipeline-collection/sandbox/sandbox-environment/terraform/`)

Do not push any code except the exercise README in `jenkins-pipeline-collection-unit-test/exercises` (this file). The rest is the developer task.

Exercise details and starter code
--------------------------------
1) Jenkins pipeline (declarative) — create a minimal pipeline that checks out the repo, computes SHORT_SHA, creates/selects the terraform workspace, applies a simple terraform config that creates an S3 bucket.

Example Jenkinsfile snippet (put into `sandbox-environment/Jenkinsfile`):

```groovy
pipeline {
  agent any
  environment {
    TF_DIR = 'terraform'
    DATE = 'nov7-2025'
  }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Prepare') {
      steps {
        script {
          // Short SHA (first 8 chars)
          SHORT_SHA = sh(script: "git rev-parse --short=8 HEAD", returnStdout: true).trim()
          env.SANDBOX_WORKSPACE = "sandbox-${SHORT_SHA}"
          env.BUCKET_NAME = "${SHORT_SHA}-${DATE}"
          echo "Workspace: ${env.SANDBOX_WORKSPACE}"
          echo "Bucket: ${env.BUCKET_NAME}"
        }
      }
    }

    stage('Terraform init & workspace') {
      steps {
        dir("${env.TF_DIR}") {
          sh 'terraform init -input=false'

          // Try to create workspace; if it exists, select it. We intentionally _don't_ abort on existing workspace to reproduce collision logs.
          sh '''
          if terraform workspace list | grep -w "${SANDBOX_WORKSPACE}" >/dev/null 2>&1; then
            echo "Selecting existing workspace ${SANDBOX_WORKSPACE}"
            terraform workspace select ${SANDBOX_WORKSPACE}
          else
            echo "Creating workspace ${SANDBOX_WORKSPACE}"
            terraform workspace new ${SANDBOX_WORKSPACE}
          fi
          '''
        }
      }
    }

    stage('Terraform apply') {
      steps {
        dir("${env.TF_DIR}") {
          // Intentionally wait 2 minutes to increase chance of collision if job triggered concurrently
          sh 'sleep 120'

          // Run apply creating an S3 bucket named by BUCKET_NAME
          sh "terraform apply -auto-approve -var='bucket_name=${BUCKET_NAME}'"
        }
      }
    }
  }
}
```

Notes:
- The sleep of 120 seconds is important: it lets you trigger a second build that will try to create the same workspace and S3 bucket while the first is still running.
- The pipeline uses the repo's `terraform` subfolder.

2) Terraform starter configuration (place under `terraform/`)

`terraform/main.tf` (very small example):

```hcl
provider "aws" {
  region = "us-west-2"
}

variable "bucket_name" {
  type = string
}

resource "aws_s3_bucket" "site_bucket" {
  bucket = var.bucket_name
  acl    = "private"

  tags = {
    Name = "sandbox-${var.bucket_name}"
    Env  = "sandbox"
  }
}
```

`terraform/versions.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}
```

`terraform/outputs.tf` (optional):

```hcl
output "bucket_name" {
  value = aws_s3_bucket.site_bucket.bucket
}
```

3) How to test the collision
---------------------------
- Create a Jenkins job pointing to the `sandbox` branch in the `jenkins-pipeline-collection` repository (or configure multibranch pipeline and set branch= sandbox).
- Run the job once. It will create the terraform workspace `sandbox-<shortsha>` and the S3 bucket `<shortsha>-nov7-2025`.
- While the job is sleeping (the 2 minute `sleep 120`), immediately trigger the job again (or trigger two concurrent builds). The second run will attempt to create/select the same workspace and the same S3 bucket. You should see terraform apply fail with an error like "Error creating S3 bucket: BucketAlreadyOwnedByYou" or terraform complaining about an existing resource.

Expected errors and interpretation
----------------------------------
- Workspace collision: you'll see "Workspace \"sandbox-<shortsha>\" already exists" when attempting to create it. The pipeline snippet above handles that by selecting if exists, so you won't fail at workspace creation, but you will see logs indicating the workspace exists.
- Bucket collision: Terraform apply may fail with errors like `BucketAlreadyOwnedByYou` or `BucketAlreadyExists`, depending on if the bucket exists in the same account or globally. This simulates the orphaned resource problem.

4) Cleanup suggestions
----------------------
- If you want to remove the workspace and S3 bucket after testing, run:

```bash
cd terraform
terraform workspace select ${SANDBOX_WORKSPACE}
terraform destroy -var="bucket_name=${BUCKET_NAME}" -auto-approve
terraform workspace select default
terraform workspace delete ${SANDBOX_WORKSPACE}
```

- Or use the `mde-talk2-destroy` Jenkins pipeline or similar destroy pipeline if present in the `jenkins-pipeline-collection` repo.

5) Assessment/Deliverables for the junior developer
--------------------------------------------------
- Add the pipeline `Jenkinsfile` as described to `jenkins-pipeline-collection/sandbox/sandbox-environment/Jenkinsfile` in branch `sandbox`.
- Add the `terraform/` folder with the provided Terraform configuration.
- Verify the pipeline runs and reproduces the collision scenario.
- Document what you observed (log excerpts and errors) in a short `TEST_RESULTS.md` file in the same folder.

Hints & tips
------------
- Use `git rev-parse --short=8 HEAD` to get the short SHA.
- Use `terraform workspace list | grep -w <name>` to check for workspace existence.
- If your AWS profile isn't configured on Jenkins, mock AWS with `localstack` or use a real AWS account and a sandbox profile.

Appendix — Troubleshooting
-------------------------
- If `terraform init` fails due to backends: for this exercise you may use a local backend by adding this to `terraform/backend.tf`:

```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

- For an S3 remote state backend, ensure the backend bucket exists and the Jenkins node has AWS credentials.

-- End of exercise --
