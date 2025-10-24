# Multi-Account Setup Guide

Terraform에서 여러 AWS 계정을 관리하는 방법입니다.

## AWS Profile 설정

### 1. AWS CLI Profile 구성

먼저 두 개의 AWS 계정에 대한 profile을 설정합니다:

```bash
# Source 계정 profile 구성
aws configure --profile source-account
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region: ap-northeast-2
# Default output format: json

# Target 계정 profile 구성
aws configure --profile target-account
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region: ap-northeast-2
# Default output format: json
```

### 2. Profile 확인

```bash
# Source 계정 확인
aws sts get-caller-identity --profile source-account
# Output:
# {
#     "UserId": "AIDA...",
#     "Account": "111111111111",
#     "Arn": "arn:aws:iam::111111111111:user/username"
# }

# Target 계정 확인
aws sts get-caller-identity --profile target-account
# Output:
# {
#     "UserId": "AIDA...",
#     "Account": "222222222222",
#     "Arn": "arn:aws:iam::222222222222:user/username"
# }
```

### 3. Profile 파일 위치

```bash
# Credentials 파일
cat ~/.aws/credentials

# Output:
# [source-account]
# aws_access_key_id = AKIA...
# aws_secret_access_key = ...
#
# [target-account]
# aws_access_key_id = AKIA...
# aws_secret_access_key = ...

# Config 파일
cat ~/.aws/config

# Output:
# [profile source-account]
# region = ap-northeast-2
# output = json
#
# [profile target-account]
# region = ap-northeast-2
# output = json
```

## Terraform에서 Profile 사용

### 방법 1: terraform.tfvars에 Profile 지정 (추천)

각 계정별로 `terraform.tfvars` 파일을 생성합니다.

#### Source Account

```bash
cd source-account

cat > terraform.tfvars << 'EOF'
# AWS Profile 설정
aws_profile         = "source-account"
aws_region          = "ap-northeast-2"

# Bucket 설정
source_bucket_name  = "my-deep-archive-source-20250124"
target_account_id   = "222222222222"  # Target 계정 ID

# Environment
environment         = "test"
EOF
```

#### Target Account

```bash
cd ../target-account

cat > terraform.tfvars << 'EOF'
# AWS Profile 설정
aws_profile         = "target-account"
aws_region          = "ap-northeast-2"

# Bucket 설정
target_bucket_name  = "my-deep-archive-target-20250124"
source_account_id   = "111111111111"  # Source 계정 ID
source_bucket_name  = "my-deep-archive-source-20250124"

# IAM
create_iam_user     = true

# Environment
environment         = "test"
EOF
```

#### Terraform 실행

```bash
# Source 계정 배포
cd source-account
terraform init
terraform plan    # Profile이 올바르게 적용되는지 확인
terraform apply

# Target 계정 배포
cd ../target-account
terraform init
terraform plan    # Profile이 올바르게 적용되는지 확인
terraform apply
```

### 방법 2: 명령줄에서 Profile 지정

```bash
# Source 계정
cd source-account
terraform apply -var="aws_profile=source-account"

# Target 계정
cd ../target-account
terraform apply -var="aws_profile=target-account"
```

### 방법 3: 환경변수 사용

```bash
# Source 계정
export TF_VAR_aws_profile=source-account
cd source-account
terraform apply

# Target 계정
export TF_VAR_aws_profile=target-account
cd ../target-account
terraform apply
```

### 방법 4: AWS_PROFILE 환경변수 (Profile 변수 없이)

**주의**: 이 방법은 `var.aws_profile`을 제거하고 provider에서 profile 설정을 빼야 합니다.

```bash
# Source 계정
export AWS_PROFILE=source-account
cd source-account
terraform apply

# Target 계정
export AWS_PROFILE=target-account
cd ../target-account
terraform apply
```

## Profile 검증

### Terraform Plan으로 확인

```bash
cd source-account
terraform plan

# Output에서 확인할 내용:
# - Bucket이 생성될 계정
# - Bucket policy의 Principal에 올바른 target account ID
```

### 실제 Account ID 확인

```bash
# Source account에서
cd source-account
terraform console
# > data.aws_caller_identity.current.account_id

# Target account에서
cd ../target-account
terraform console
# > data.aws_caller_identity.current.account_id
```

이를 위해 data source 추가:

```hcl
# main.tf에 추가
data "aws_caller_identity" "current" {}

output "current_account_id" {
  value = data.aws_caller_identity.current.account_id
}
```

## 계정별 격리 전략

### 1. 별도 디렉토리 (현재 구조)

```
s3-deep-archive/
├── source-account/        # Source 계정용
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars
└── target-account/        # Target 계정용
    ├── main.tf
    ├── variables.tf
    └── terraform.tfvars
```

**장점**:
- 명확한 분리
- 각 계정별로 독립적인 state 관리
- 실수로 다른 계정에 배포할 위험 감소

### 2. Terraform Workspace (대안)

**사용하지 않는 이유**: Cross-account 시나리오에서는 별도 디렉토리가 더 안전

```bash
# Workspace 사용 예시 (참고용)
terraform workspace new source
terraform workspace new target

terraform workspace select source
terraform apply -var-file=source.tfvars

terraform workspace select target
terraform apply -var-file=target.tfvars
```

### 3. Terragrunt (고급)

대규모 multi-account 관리 시 고려:

```hcl
# terragrunt.hcl
remote_state {
  backend = "s3"
  config = {
    bucket  = "terraform-state-${get_aws_account_id()}"
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "${get_env("AWS_PROFILE", "default")}"
  }
}
```

## 보안 Best Practices

### 1. Profile별 권한 최소화

Source account profile:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "iam:GetUser"
      ],
      "Resource": "*"
    }
  ]
}
```

Target account profile:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "iam:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2. MFA 사용

```bash
# ~/.aws/config
[profile source-account]
region = ap-northeast-2
mfa_serial = arn:aws:iam::111111111111:mfa/username

[profile target-account]
region = ap-northeast-2
mfa_serial = arn:aws:iam::222222222222:mfa/username
```

### 3. Assume Role 사용 (권장)

더 안전한 방법:

```bash
# ~/.aws/config
[profile source-base]
region = ap-northeast-2

[profile source-account]
source_profile = source-base
role_arn = arn:aws:iam::111111111111:role/TerraformRole
mfa_serial = arn:aws:iam::111111111111:mfa/username

[profile target-account]
source_profile = source-base
role_arn = arn:aws:iam::222222222222:role/TerraformRole
mfa_serial = arn:aws:iam::222222222222:mfa/username
```

## 자동화 스크립트

### 전체 배포 스크립트

```bash
#!/bin/bash
# deploy-all.sh

set -e

SOURCE_PROFILE="source-account"
TARGET_PROFILE="target-account"

echo "=========================================="
echo "Deploying Source Account"
echo "=========================================="
cd source-account
terraform init
terraform plan -var="aws_profile=$SOURCE_PROFILE"
terraform apply -var="aws_profile=$SOURCE_PROFILE" -auto-approve

SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
SOURCE_ACCOUNT_ID=$(terraform output -raw current_account_id 2>/dev/null || aws sts get-caller-identity --profile $SOURCE_PROFILE --query Account --output text)

echo ""
echo "=========================================="
echo "Deploying Target Account"
echo "=========================================="
cd ../target-account

# Update terraform.tfvars with source info
cat > terraform.tfvars << EOF
aws_profile        = "$TARGET_PROFILE"
aws_region         = "ap-northeast-2"
target_bucket_name = "my-deep-archive-target-$(date +%Y%m%d)"
source_account_id  = "$SOURCE_ACCOUNT_ID"
source_bucket_name = "$SOURCE_BUCKET"
create_iam_user    = true
environment        = "test"
EOF

terraform init
terraform plan
terraform apply -auto-approve

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo "Source Bucket: $SOURCE_BUCKET"
echo "Source Account: $SOURCE_ACCOUNT_ID"
echo ""
echo "Next: cd ../scripts && ./01-upload-to-deep-archive.sh $SOURCE_BUCKET"
```

### 정리 스크립트

```bash
#!/bin/bash
# destroy-all.sh

set -e

echo "Destroying Target Account..."
cd target-account
terraform destroy -auto-approve

echo "Destroying Source Account..."
cd ../source-account
terraform destroy -auto-approve

echo "Cleanup complete!"
```

## Troubleshooting

### Profile이 인식되지 않음

```bash
# Profile 목록 확인
aws configure list-profiles

# 특정 profile로 테스트
aws s3 ls --profile source-account
```

### 잘못된 계정에 배포됨

```bash
# 현재 사용 중인 계정 확인
terraform console
> data.aws_caller_identity.current.account_id

# 또는
aws sts get-caller-identity --profile source-account
```

### Access Denied

```bash
# IAM 권한 확인
aws iam get-user --profile source-account
aws iam list-attached-user-policies --user-name USERNAME --profile source-account
```

## 요약

### 빠른 시작

```bash
# 1. AWS Profile 구성
aws configure --profile source-account
aws configure --profile target-account

# 2. Account ID 확인
SOURCE_ID=$(aws sts get-caller-identity --profile source-account --query Account --output text)
TARGET_ID=$(aws sts get-caller-identity --profile target-account --query Account --output text)

echo "Source Account: $SOURCE_ID"
echo "Target Account: $TARGET_ID"

# 3. Source 배포
cd source-account
cat > terraform.tfvars << EOF
aws_profile        = "source-account"
source_bucket_name = "deep-archive-source-$(date +%Y%m%d)"
target_account_id  = "$TARGET_ID"
EOF
terraform init && terraform apply

# 4. Target 배포
cd ../target-account
SOURCE_BUCKET=$(cd ../source-account && terraform output -raw source_bucket_name)
cat > terraform.tfvars << EOF
aws_profile        = "target-account"
target_bucket_name = "deep-archive-target-$(date +%Y%m%d)"
source_account_id  = "$SOURCE_ID"
source_bucket_name = "$SOURCE_BUCKET"
create_iam_user    = true
EOF
terraform init && terraform apply
```

완료! 이제 각 Terraform 구성이 올바른 AWS 계정을 사용합니다. 🎉
