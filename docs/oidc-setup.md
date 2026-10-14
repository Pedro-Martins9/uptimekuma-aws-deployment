# GitHub Actions OIDC setup

The workflows are committed, but they do not have AWS permission until the OIDC provider, two IAM roles and repository/environment variables are configured. This is a one-time setup using an administrator session in the AWS Console. No AWS access keys should be stored in GitHub.

## 1. Create or verify the GitHub OIDC provider

In AWS IAM, open **Identity providers**. If there is no provider for GitHub Actions, add an **OpenID Connect** provider with:

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

Use the AWS Console's current provider setup flow rather than copying an old certificate thumbprint from a blog.

## 2. Create the trust roles

Account: `REPLACE_WITH_AWS_ACCOUNT_ID`  
Region: `eu-west-1`  
Repository: `Pedro-Martins9/uptimekuma-aws-deployment`  
OIDC provider ARN: `arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com`

Create role `uptimekuma-github-terraform-plan` with web identity as its trusted entity. Its trust relationship should restrict both audience and subject:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:Pedro-Martins9/uptimekuma-aws-deployment:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Create role `uptimekuma-github-terraform-apply` with the same structure, but change the subject condition to:

```json
"token.actions.githubusercontent.com:sub": "repo:Pedro-Martins9/uptimekuma-aws-deployment:environment:aws-deploy"
```

Do not use wildcard repository subjects. The plan workflow runs only on `main`; the apply job uses the `aws-deploy` GitHub Environment, so GitHub emits the Environment subject for it.

## 3. Configure permissions

Do not attach `AdministratorAccess`. Attach `ReadOnlyAccess` to both roles to cover provider refresh/describe operations, then add the backend policy below to **both** roles. The plan role should have no infrastructure write permissions beyond the S3 backend/lock operations.

Replace account or bucket names only if the deployment is intentionally moved to a different account. Save the following as an IAM inline policy, for example `uptimekuma-terraform-state`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadTerraformBucketMetadata",
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:GetBucketVersioning"],
      "Resource": "arn:aws:s3:::REPLACE_WITH_EXISTING_TFSTATE_BUCKET"
    },
    {
      "Sid": "ListOnlyTerraformStatePrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::REPLACE_WITH_EXISTING_TFSTATE_BUCKET",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["uptimekuma/*"]
        }
      }
    },
    {
      "Sid": "ReadWriteMainTerraformStateAndLock",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::REPLACE_WITH_EXISTING_TFSTATE_BUCKET/uptimekuma/terraform.tfstate",
        "arn:aws:s3:::REPLACE_WITH_EXISTING_TFSTATE_BUCKET/uptimekuma/terraform.tfstate.tflock"
      ]
    }
  ]
}
```

The S3 write/delete scope is needed for Terraform to save state and acquire/release the S3 native lock file. Do not add access to the bootstrap state's local file or broad bucket deletion permissions.

### Apply-role resource permissions

The apply role additionally needs create/update/delete actions for the exact resources managed by `terraform/`: VPC/subnets/routes/Internet Gateway/security groups/launch template; ALB/listener/target group; ECS cluster/service/task definition/capacity provider; Auto Scaling Group; CloudWatch log group/alarms/metric queries; SNS topic/subscription; SSM associations; and IAM roles, role policy attachments, inline policies and instance profile named `uptimekuma-*`.

As a practical starting point, add the provider write actions in a second inline policy and restrict IAM resources to these paths:

- `arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:role/uptimekuma-*`
- `arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:instance-profile/uptimekuma-*`

Restrict `iam:PassRole` to the EC2 instance role and ECS task-execution role, and use `iam:PassedToService` conditions for `ec2.amazonaws.com` and `ecs-tasks.amazonaws.com`. Keep resource-management permissions off the plan role. AWS APIs for some create/describe actions require `Resource: "*"`; use only those actions that require it, and add tags/request-tag conditions where the service supports them.

Because AWS provider behavior and the precise action set can evolve, run a plan first and grant only specific missing read actions if it returns AccessDenied. Review all policy changes before enabling apply. Do not solve an AccessDenied error by granting AdministratorAccess.

## 4. Configure GitHub

In **Settings → Secrets and variables → Actions → Variables**, add:

- `AWS_TERRAFORM_PLAN_ROLE_ARN`: ARN of `uptimekuma-github-terraform-plan`.
- `ALERT_EMAIL`: optional email address that should receive alarm notifications.

In **Settings → Environments**, create `aws-deploy`, allow deployments from `main`, and configure required reviewers if that feature is available for the repository/account plan. Add environment variable:

- `AWS_TERRAFORM_APPLY_ROLE_ARN`: ARN of `uptimekuma-github-terraform-apply`.

The email address is not an AWS credential. The SNS subscription remains pending until its confirmation link is accepted. The deploy workflow passes `ALERT_EMAIL` into Terraform as `TF_VAR_alert_email`; leave it empty if you are doing validation only and do not want an SNS subscription.

## 5. Prove the guardrails

1. Run **Terraform validation** and make sure formatting and validation pass for the main, state-bootstrap and backup-infrastructure directories.
2. From Actions, manually dispatch **Terraform deployment** on `main` with mode `plan`. Confirm it assumes the plan role and produces a plan without changing resources.
3. Review the plan artifact and summary. Plan artifacts may contain sensitive values; the workflow is configured for a private repository and one-day retention.
4. Only for a deliberate test deployment, select mode `deploy`, type `DEPLOY`, and let the `aws-deploy` Environment gate run before apply.
5. Verify the expected AWS account in the `aws sts get-caller-identity` step.
6. Destroy the test stack manually only after inspecting `terraform plan -destroy`. There is no automated destroy job.

The AWS-side trust provider and IAM roles must be created before this workflow can get credentials. A green YAML validation run alone does not prove OIDC trust or an AWS apply works.
