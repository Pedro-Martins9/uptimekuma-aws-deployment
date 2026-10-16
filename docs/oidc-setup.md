# GitHub Actions OIDC setup

The workflows need an AWS IAM OIDC provider, two IAM roles and GitHub Actions variables/secrets before they can access AWS. This is a one-time setup using an administrator session in the AWS Console. Do not store AWS access keys in GitHub.

This guide uses clearly marked placeholders so it can be shared safely. Replace every `<PLACEHOLDER>` with the value for your own account and repository before applying any IAM policy. Keep the repository, AWS account, bucket names and role names consistent across the guide and the Terraform configuration.

## 1. Create or verify the GitHub OIDC provider

In AWS IAM, open **Identity providers**. If there is no provider for GitHub Actions, add an **OpenID Connect** provider with:

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

Use the AWS Console's current provider setup flow rather than copying an old certificate thumbprint from a blog.

## 2. Create the trust roles

**Important — immutable subject claim:** repositories created after GitHub's subject-format rollout on 15 July 2026 use an immutable subject containing numeric owner and repository IDs by default. For this repository type, do not use the older name-only subject format. Confirm the exact claim emitted by your workflow and use the immutable form below. See GitHub's [AWS OIDC guide](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

Substitute these values throughout the examples:

- `<AWS_ACCOUNT_ID>`: the 12-digit AWS account ID.
- `<GITHUB_OWNER>`: GitHub owner/login.
- `<GITHUB_OWNER_ID>`: immutable numeric GitHub owner ID.
- `<GITHUB_REPOSITORY>`: repository name only, without owner.
- `<GITHUB_REPOSITORY_ID>`: immutable numeric repository ID.
- `<AWS_REGION>`: region used by Terraform, for example `eu-west-1`.
- `<TFSTATE_BUCKET>`: the Terraform state bucket configured in the backend.
- `<APP_BACKUP_BUCKET>`: the separate application-backup bucket.
- `<PLAN_ROLE_NAME>` and `<APPLY_ROLE_NAME>`: the role names used in GitHub Actions and IAM.

Create role `<PLAN_ROLE_NAME>` with web identity as its trusted entity. Its trust relationship should restrict both audience and subject:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:<GITHUB_OWNER>@<GITHUB_OWNER_ID>/<GITHUB_REPOSITORY>@<GITHUB_REPOSITORY_ID>:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Create role `<APPLY_ROLE_NAME>` with the same structure, but change the subject condition to the environment subject:

```json
"token.actions.githubusercontent.com:sub": "repo:<GITHUB_OWNER>@<GITHUB_OWNER_ID>/<GITHUB_REPOSITORY>@<GITHUB_REPOSITORY_ID>:environment:aws-deploy"
```

Do not use wildcard repository subjects. The plan workflow runs only on `main`; the apply job uses the `aws-deploy` GitHub Environment, so GitHub emits the Environment subject for it. Before relying on this configuration, confirm the exact subject format used for the repository and environment in GitHub's current OIDC documentation.

## 3. Configure permissions

Do not attach `AdministratorAccess`. Attach `ReadOnlyAccess` to both roles to cover provider refresh/describe operations, then add the backend policy below to **both** roles. The plan role should have no infrastructure write permissions beyond the S3 backend/lock operations.

Save the following as an IAM inline policy, for example `<STATE_POLICY_NAME>`. Substitute `<AWS_ACCOUNT_ID>` and `<TFSTATE_BUCKET>` in every ARN before saving:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadTerraformBucketMetadata",
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:GetBucketVersioning"],
      "Resource": "arn:aws:s3:::<TFSTATE_BUCKET>"
    },
    {
      "Sid": "ListOnlyTerraformStatePrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<TFSTATE_BUCKET>",
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
        "arn:aws:s3:::<TFSTATE_BUCKET>/uptimekuma/terraform.tfstate",
        "arn:aws:s3:::<TFSTATE_BUCKET>/uptimekuma/terraform.tfstate.tflock",
        "arn:aws:s3:::<TFSTATE_BUCKET>/uptimekuma/backup-infra.tfstate",
        "arn:aws:s3:::<TFSTATE_BUCKET>/uptimekuma/backup-infra.tfstate.tflock"
      ]
    }
  ]
}
```

S3 write/delete scope is needed for Terraform to save state and acquire/release the native S3 lock file. These resources cover the application and backup-infrastructure state keys. Do not add access to the bootstrap root's local state or broad bucket-deletion permissions.

### Apply-role resource permissions

Keep the plan role read-only apart from state/lock object access. For the apply role, attach an inline policy for the main application root plus the S3 operations needed to create/configure the separate application-backup bucket. Treat the resource policy below as a **portfolio-sandbox starting policy, not a guarantee of least privilege for every future edit**. Review its resource scope and AWS AccessDenied results before using it in an account containing unrelated workloads. Both roles also need the state policy from section 3.

Save the JSON below as `<APPLY_POLICY_NAME>` and attach it only to `<APPLY_ROLE_NAME>`. Substitute `<AWS_ACCOUNT_ID>`, `<APP_BACKUP_BUCKET>` and role names in every applicable ARN. The policy example is intentionally abbreviated to the service/action groups that were used by the tested configuration; review the Terraform and AWS provider behavior before reusing it.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageProjectVpcAndLaunchTemplate",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:RunInstances",
        "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
        "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
        "ec2:CreateRoute", "ec2:DeleteRoute",
        "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateLaunchTemplate", "ec2:CreateLaunchTemplateVersion",
        "ec2:ModifyLaunchTemplate", "ec2:DeleteLaunchTemplateVersions",
        "ec2:DeleteLaunchTemplate",
        "ec2:CreateTags", "ec2:DeleteTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageProjectLoadBalancer",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:DescribeTags", "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageProjectEcsAndCapacity",
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters", "ecs:ListClusters",
        "ecs:PutClusterCapacityProviders",
        "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DescribeTaskDefinition",
        "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService",
        "ecs:DescribeServices", "ecs:ListServices",
        "ecs:CreateCapacityProvider", "ecs:UpdateCapacityProvider",
        "ecs:DeleteCapacityProvider", "ecs:DescribeCapacityProviders",
        "ecs:TagResource", "ecs:UntagResource",
        "autoscaling:CreateAutoScalingGroup", "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup", "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeScalingActivities", "autoscaling:DescribePolicies",
        "autoscaling:CreateOrUpdateTags", "autoscaling:DeleteTags",
        "autoscaling:EnableMetricsCollection", "autoscaling:DisableMetricsCollection"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageProjectLogsAlarmsAndNotifications",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
        "logs:DescribeLogGroups", "logs:ListTagsForResource",
        "logs:TagResource", "logs:UntagResource",
        "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms", "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource",
        "sns:CreateTopic", "sns:DeleteTopic", "sns:Subscribe", "sns:Unsubscribe",
        "sns:GetTopicAttributes", "sns:SetTopicAttributes",
        "sns:ListTagsForResource", "sns:TagResource", "sns:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageProjectSsmAssociations",
      "Effect": "Allow",
      "Action": [
        "ssm:CreateAssociation", "ssm:UpdateAssociation", "ssm:DeleteAssociation",
        "ssm:DescribeAssociation", "ssm:DescribeAssociationExecutions",
        "ssm:DescribeAssociationExecutionTargets", "ssm:ListAssociations",
        "ssm:ListAssociationVersions", "ssm:GetParameter",
        "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageOnlyProjectIamRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
        "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
        "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::<AWS_ACCOUNT_ID>:role/uptimekuma-*",
        "arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/uptimekuma-*"
      ]
    },
    {
      "Sid": "ManageOnlyApplicationBackupBucket",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:GetBucketAcl",
        "s3:PutBucketVersioning", "s3:GetBucketVersioning",
        "s3:PutEncryptionConfiguration", "s3:GetEncryptionConfiguration",
        "s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPolicy", "s3:GetBucketPolicy",
        "s3:PutLifecycleConfiguration", "s3:GetLifecycleConfiguration",
        "s3:PutBucketTagging", "s3:GetBucketTagging",
        "s3:GetBucketLocation", "s3:ListBucket",
        "s3:ListBucketVersions", "s3:ListBucketMultipartUploads"
      ],
      "Resource": "arn:aws:s3:::<APP_BACKUP_BUCKET>"
    },
    {
      "Sid": "PassOnlyProjectRuntimeRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::<AWS_ACCOUNT_ID>:role/uptimekuma-ecs-instance-role",
        "arn:aws:iam::<AWS_ACCOUNT_ID>:role/uptimekuma-ecs-task-execution-role"
      ],
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "ec2.amazonaws.com",
            "ecs-tasks.amazonaws.com"
          ]
        }
      }
    }
  ]
}
```

Some create APIs and tagging operations do not support full resource scoping in the same way as update/delete APIs; the example uses `Resource: "*"` for several service groups. That is a trade-off, not perfect least privilege. For a shared or production account, split statements and restrict resources by ARN, request tags or existing tags wherever supported. Do not use this starter policy as a substitute for a policy review.

Earlier apply errors showed missing `ec2:RunInstances`, `elasticloadbalancing:ModifyLoadBalancerAttributes` and `elasticloadbalancing:ModifyTargetGroupAttributes`; these actions and the matching ELB attribute describe actions are included above. Auto Scaling launch-template usage may also require `ec2:CreateTags` and `iam:PassRole`. The example uses `ec2:Describe*` with `Resource: "*"`; do not add invalid EC2 action names based on guessed API operations. If the live role was configured from an earlier version of this guide, update its inline policy in IAM separately—changing this file does not change AWS permissions. Verify `ReadOnlyAccess` is attached to the apply role if that remains part of your intended design.

## 4. Configure GitHub

In **Settings → Secrets and variables → Actions → Variables**, add:

- `AWS_ACCOUNT_ID`: the same 12-digit AWS account ID used in the Terraform variable `aws_account_id`.

- `AWS_TERRAFORM_PLAN_ROLE_ARN`: `arn:aws:iam::<AWS_ACCOUNT_ID>:role/<PLAN_ROLE_NAME>`.
- `ALERT_EMAIL`: optional email address that should receive alarm notifications.
- `ALB_ALLOWED_CLIENT_CIDR`: your current public IPv4 address in `/32` notation. Get the address with `curl -4 https://checkip.amazonaws.com`, then append `/32` before saving it. Do not use `0.0.0.0/0`. If your public IP changes, update this variable and run a new plan.

The **Terraform deployment** workflow also has an optional `allowed_client_ipv4_cidr` input when you manually run it. Enter your current IPv4 address followed by `/32` there to override the repository variable for that run. The direct input takes precedence. If you recently edited a variable, start a **new workflow run** after saving it rather than re-running an old failed run.

In **Settings → Secrets and variables → Actions → Secrets**, add `TFPLAN_ENCRYPTION_KEY`. Generate a strong random value locally (for example, with `openssl rand -base64 48`), store it in a password manager, then add the same value as the GitHub Actions secret. **Never commit or paste this value into issues, logs, or chat.** The deployment workflow encrypts the saved Terraform plan before uploading it as a short-retention artifact.

In **Settings → Environments**, create `aws-deploy` and allow deployments from `main`. Configure at least one **Required reviewer**. The apply job will be held by GitHub until the environment is approved; branch restrictions alone do not pause a deployment. Add this environment variable:

- `AWS_TERRAFORM_APPLY_ROLE_ARN`: `arn:aws:iam::<AWS_ACCOUNT_ID>:role/<APPLY_ROLE_NAME>`.

The plan-review artifact is named `terraform-plan-encrypted` and expires after one day. To inspect it, download it from the workflow run, set the same `TFPLAN_ENCRYPTION_KEY` value in your local shell (without committing it), decrypt with OpenSSL using AES-256-CBC/PBKDF2 and 600,000 iterations, extract the archive, then inspect `tfplan-review.txt` from the matching run. Approve the GitHub environment deployment only after reviewing that plan.

The SNS email subscription remains pending until its confirmation link is accepted. The deploy workflow passes `ALERT_EMAIL` into Terraform as `TF_VAR_alert_email`; leave it empty if you are doing validation only and do not want an SNS subscription.

## 5. Prove the guardrails

1. Configure `TF_VAR_aws_account_id` for local Terraform commands, or set the equivalent variable input without committing it. Restore the existing state bucket name in the remote backend blocks before any Terraform initialization. In GitHub Actions, configure the `AWS_ACCOUNT_ID` repository variable and both role ARN values above.
2. Run **Terraform validation** and make sure formatting and validation pass for the main, state-bootstrap and backup-infrastructure directories.
3. From Actions, manually dispatch **Terraform deployment** on `main` with mode `plan`. Confirm it assumes the plan role and produces a plan without changing resources.
4. Review the plan artifact and summary. Plan artifacts may contain sensitive values; the workflow encrypts the plan artifact and retains it for one day.
5. Confirm the `aws-deploy` environment has a required reviewer and restricts deployments to `main`. Select target `backup-infra` and mode `plan` first. Review the plan; then select target `backup-infra`, mode `deploy`, and type `DEPLOY`. The apply job must pause for environment approval after the plan is created.
6. Run the workflow again with target `application` and mode `plan`; review the entire plan. Only choose `deploy` with typed confirmation `DEPLOY` for a deliberate application test.
7. Verify the expected AWS account in the `aws sts get-caller-identity` step.
8. Destroy the test stack manually only after inspecting `terraform plan -destroy`. There is no automated destroy job.

The AWS-side trust provider and IAM roles must be created before this workflow can get credentials. A green YAML validation run alone does not prove OIDC trust or an AWS apply works.
