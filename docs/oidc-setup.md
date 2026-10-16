# GitHub Actions OIDC setup

The workflows are committed, but they do not have AWS permission until the OIDC provider, two IAM roles and repository/environment variables are configured. This is a one-time setup using an administrator session in the AWS Console. No AWS access keys should be stored in GitHub.

## 1. Create or verify the GitHub OIDC provider

In AWS IAM, open **Identity providers**. If there is no provider for GitHub Actions, add an **OpenID Connect** provider with:

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

Use the AWS Console's current provider setup flow rather than copying an old certificate thumbprint from a blog.

## 2. Create the trust roles

**Important for this repository:** it was created after 15 July 2026, so GitHub's default immutable subject format includes the numeric owner and repository IDs. Use the exact subject strings below; the older name-only format will not match this repository's default tokens. GitHub documents this change in its [AWS OIDC guide](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

Account: `REPLACE_WITH_AWS_ACCOUNT_ID`  
Region: `eu-west-1`  
Repository: `Pedro-Martins9/uptimekuma-aws-deployment`  
OIDC provider ARN: `arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com`

Create role `uptimekuma-terraform-plan` with web identity as its trusted entity. Its trust relationship should restrict both audience and subject:

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
          "token.actions.githubusercontent.com:sub": "repo:Pedro-Martins9@151472460/uptimekuma-aws-deployment@1417298757:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Create role `uptimekuma-terraform-apply` with the same structure, but change the subject condition to:

```json
"token.actions.githubusercontent.com:sub": "repo:Pedro-Martins9@151472460/uptimekuma-aws-deployment@1417298757:environment:aws-deploy"
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
        "arn:aws:s3:::REPLACE_WITH_EXISTING_TFSTATE_BUCKET/uptimekuma/terraform.tfstate.tflock",
        "arn:aws:s3:::REPLACE_WITH_EXISTING_TFSTATE_BUCKET/uptimekuma/backup-infra.tfstate",
        "arn:aws:s3:::REPLACE_WITH_EXISTING_TFSTATE_BUCKET/uptimekuma/backup-infra.tfstate.tflock"
      ]
    }
  ]
}
```

The S3 write/delete scope is needed for Terraform to save state and acquire/release the S3 native lock file. The policy includes both application and backup-infrastructure state keys because the workflow can target either root. Do not add access to the bootstrap's local state or broad bucket deletion permissions.

### Apply-role resource permissions

Keep the plan role read-only apart from the state/lock object access. For the apply role, attach an inline policy for the main application root plus the S3 operations needed to create/configure the separate application-backup bucket. This is a **portfolio-sandbox starting policy, not a guarantee of least privilege for every future edit**. Review the resource scope and AWS AccessDenied results before using it in an account containing unrelated workloads. Both roles also need the state policy in section 3.

Save the JSON below as `uptimekuma-terraform-apply` and attach it only to `uptimekuma-terraform-apply`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageProjectVpcAndLaunchTemplate",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
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
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetHealth",
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
        "arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:role/uptimekuma-*",
        "arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:instance-profile/uptimekuma-*"
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
      "Resource": "arn:aws:s3:::REPLACE_WITH_APP_BACKUP_BUCKET"
    },
    {
      "Sid": "PassOnlyProjectRuntimeRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:role/uptimekuma-ecs-instance-role",
        "arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:role/uptimekuma-ecs-task-execution-role"
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

The latest failed apply exposed missing permissions for `ec2:DescribeVpcs` and `cloudwatch:ListTagsForResource`. The example policy grants the read-only EC2 Describe API family using `ec2:Describe*` with `Resource: "*"`; AWS documents that EC2 Describe APIs do not support resource-level permissions. Do not add `ec2:DescribeSubnetAttribute`: it is not a valid action in the EC2 Service Authorization Reference. `cloudwatch:ListTagsForResource` is a valid CloudWatch IAM action and is included in the alarm/notification statement. If the live role was configured from an earlier version of this guide, update its inline policy in IAM as well; changing this file does not change permissions in AWS. Also verify that the `ReadOnlyAccess` managed policy is actually attached to the live apply role, as intended.

Some create APIs and tagging operations do not support full resource scoping in the same way as update/delete APIs; the example uses `Resource: "*"` for several service groups. That is a trade-off, not perfect least privilege. For a shared or production account, split statements and restrict resources by ARN, request tags or existing tags wherever supported. Do not use this starter policy as a substitute for a policy review. The managed `ReadOnlyAccess` policy plus the state policy from section 3 remains on each role.

## 4. Configure GitHub

In **Settings → Secrets and variables → Actions → Variables**, add:

- `AWS_TERRAFORM_PLAN_ROLE_ARN`: `arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:role/uptimekuma-terraform-plan`.
- `ALERT_EMAIL`: optional email address that should receive alarm notifications.
- `ALB_ALLOWED_CLIENT_CIDR`: your current public IPv4 address in `/32` notation. Get the address with `curl -4 https://checkip.amazonaws.com`, then append `/32` before saving it. Do not use `0.0.0.0/0`. If your public IP changes, update this variable and run a new plan.

The **Terraform deployment** workflow also has an optional `allowed_client_ipv4_cidr` input when you manually run it. Enter your current IPv4 address followed by `/32` there to override the repository variable for that run. The direct input takes precedence. If you recently edited a variable, start a **new workflow run** after saving it rather than re-running an old failed run.

In **Settings → Secrets and variables → Actions → Secrets**, add `TFPLAN_ENCRYPTION_KEY`. Generate a strong random value locally (for example, with `openssl rand -base64 48`), store it in a password manager, then add the same value as the GitHub Actions secret. **Never commit or paste this value into issues, logs, or chat.** The deployment workflow encrypts the saved Terraform plan because this portfolio repository is public; only the encrypted artifact is uploaded.

In **Settings → Environments**, create `aws-deploy` and allow deployments from `main`. Configure at least one **Required reviewer**. The apply job will be held by GitHub until the environment is approved; branch restrictions alone do not pause a deployment. Add this environment variable:

- `AWS_TERRAFORM_APPLY_ROLE_ARN`: `arn:aws:iam::REPLACE_WITH_AWS_ACCOUNT_ID:role/uptimekuma-terraform-apply`.


The plan-review artifact is named `terraform-plan-encrypted` and expires after one day. To inspect it, download it from the workflow run, set the same `TFPLAN_ENCRYPTION_KEY` value in your local shell (without committing it), decrypt with OpenSSL using AES-256-CBC/PBKDF2 and 600,000 iterations, extract the archive, then inspect `tfplan-review.txt` from the matching run. Approve the GitHub environment deployment only after reviewing that plan.

The email address is not an AWS credential. The SNS subscription remains pending until its confirmation link is accepted. The deploy workflow passes `ALERT_EMAIL` into Terraform as `TF_VAR_alert_email`; leave it empty if you are doing validation only and do not want an SNS subscription.

## 5. Prove the guardrails

1. Run **Terraform validation** and make sure formatting and validation pass for the main, state-bootstrap and backup-infrastructure directories.
2. From Actions, manually dispatch **Terraform deployment** on `main` with mode `plan`. Confirm it assumes the plan role and produces a plan without changing resources.
3. Review the plan artifact and summary. Plan artifacts may contain sensitive values; the workflow encrypts the plan artifact and retains it for one day.
4. Confirm the `aws-deploy` environment has a required reviewer and restricts deployments to `main`. Select target `backup-infra` and mode `plan` first. Review the plan; then select target `backup-infra`, mode `deploy`, and type `DEPLOY`. The apply job must pause for environment approval after the plan is created.
5. Run the workflow again with target `application` and mode `plan`; review the entire plan. Only choose `deploy` with typed confirmation `DEPLOY` for a deliberate application test.
6. Verify the expected AWS account in the `aws sts get-caller-identity` step.
7. Destroy the test stack manually only after inspecting `terraform plan -destroy`. There is no automated destroy job.

The AWS-side trust provider and IAM roles must be created before this workflow can get credentials. A green YAML validation run alone does not prove OIDC trust or an AWS apply works.
