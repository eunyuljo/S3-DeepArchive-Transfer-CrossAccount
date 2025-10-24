# Git Repository Setup Guide

이 프로젝트를 Git 저장소로 관리하는 방법입니다.

## 초기 설정

### 1. Git 저장소 초기화

```bash
cd /home/ec2-user/claude-code/s3-deep-archive

# Git 저장소 초기화
git init

# .gitignore 확인
cat .gitignore
```

### 2. terraform.tfvars 파일 생성

**중요**: `terraform.tfvars` 파일은 민감한 정보(Account ID, bucket 이름 등)를 포함하므로 Git에 커밋하지 않습니다.

#### Source Account

```bash
cd source-account

# Example 파일을 복사하여 실제 값으로 수정
cp terraform.tfvars.example terraform.tfvars

# 편집
vim terraform.tfvars  # 또는 nano, code 등
```

**terraform.tfvars** 내용:
```hcl
aws_profile        = "your-source-profile"     # 실제 AWS profile
source_bucket_name = "your-source-bucket-2025" # 실제 bucket 이름
target_account_id  = "123456789012"            # 실제 Target Account ID
```

#### Target Account

```bash
cd ../target-account

# Example 파일을 복사하여 실제 값으로 수정
cp terraform.tfvars.example terraform.tfvars

# 편집
vim terraform.tfvars
```

**terraform.tfvars** 내용:
```hcl
aws_profile        = "your-target-profile"     # 실제 AWS profile
target_bucket_name = "your-target-bucket-2025" # 실제 bucket 이름
source_account_id  = "987654321098"            # 실제 Source Account ID
source_bucket_name = "your-source-bucket-2025" # Source bucket 이름
create_iam_user    = true
```

### 3. Git에 커밋

```bash
cd ..  # 프로젝트 루트로 이동

# 상태 확인
git status

# .gitignore 확인 (terraform.tfvars는 무시되어야 함)
git status --ignored

# 파일 추가
git add .

# 커밋
git commit -m "Initial commit: S3 Deep Archive cross-account transfer setup"
```

## 원격 저장소 설정

### GitHub

```bash
# GitHub에서 새 repository 생성 후

# 원격 저장소 추가
git remote add origin https://github.com/username/s3-deep-archive.git

# 또는 SSH
git remote add origin git@github.com:username/s3-deep-archive.git

# Push
git branch -M main
git push -u origin main
```

### GitLab

```bash
# GitLab에서 새 project 생성 후

git remote add origin https://gitlab.com/username/s3-deep-archive.git
git branch -M main
git push -u origin main
```

### AWS CodeCommit

```bash
# CodeCommit repository 생성 후

git remote add origin https://git-codecommit.ap-northeast-2.amazonaws.com/v1/repos/s3-deep-archive
git push -u origin main
```

## 보안 사항

### .gitignore에 의해 무시되는 파일들

다음 파일들은 자동으로 Git에 추적되지 않습니다:

```
# Terraform 민감 파일
**/*.tfvars              # 실제 설정 값
**/terraform.tfstate     # Terraform 상태 파일
**/.terraform/           # Terraform 플러그인

# AWS 자격증명
*.pem
*.key
.aws/

# 테스트 데이터
test-data/sample-files/*

# 임시 파일
*.log
*.tmp
```

### Git에 포함되는 파일들

```
✓ *.tf                    # Terraform 코드
✓ *.tfvars.example        # 설정 예시 (민감정보 제외)
✓ *.md                    # 문서
✓ *.sh                    # 스크립트
✓ .gitignore              # Git 설정
```

## 팀 협업

### 새 팀원 온보딩

1. **저장소 클론**
   ```bash
   git clone https://github.com/username/s3-deep-archive.git
   cd s3-deep-archive
   ```

2. **AWS Profile 설정**
   ```bash
   aws configure --profile source-account
   aws configure --profile target-account
   ```

3. **terraform.tfvars 생성**
   ```bash
   # Source account
   cd source-account
   cp terraform.tfvars.example terraform.tfvars
   # 편집하여 실제 값 입력

   # Target account
   cd ../target-account
   cp terraform.tfvars.example terraform.tfvars
   # 편집하여 실제 값 입력
   ```

4. **Terraform 초기화**
   ```bash
   cd source-account
   terraform init

   cd ../target-account
   terraform init
   ```

### 설정 값 공유 방법

**민감한 정보를 안전하게 공유**:

#### 방법 1: AWS Secrets Manager (추천)

```bash
# 설정 값을 Secrets Manager에 저장
aws secretsmanager create-secret \
    --name s3-deep-archive/source-account \
    --secret-string file://source-account/terraform.tfvars \
    --profile admin

# 팀원이 가져오기
aws secretsmanager get-secret-value \
    --secret-id s3-deep-archive/source-account \
    --query SecretString \
    --output text > source-account/terraform.tfvars
```

#### 방법 2: AWS Systems Manager Parameter Store

```bash
# Account ID 저장
aws ssm put-parameter \
    --name /s3-deep-archive/source-account-id \
    --value "123456789012" \
    --type String \
    --profile admin

# 가져오기
SOURCE_ACCOUNT_ID=$(aws ssm get-parameter \
    --name /s3-deep-archive/source-account-id \
    --query Parameter.Value \
    --output text)
```

#### 방법 3: 1Password / LastPass (팀용)

- 팀 vault에 terraform.tfvars 내용 저장
- 필요한 팀원만 접근 권한 부여

#### 방법 4: 암호화된 파일 공유

```bash
# 암호화
gpg -c source-account/terraform.tfvars
# → terraform.tfvars.gpg 생성

# Git에 추가 (암호화된 파일만)
git add source-account/terraform.tfvars.gpg

# 복호화 (팀원)
gpg -d source-account/terraform.tfvars.gpg > source-account/terraform.tfvars
```

## Branch 전략

### Feature Branch Workflow

```bash
# Feature branch 생성
git checkout -b feature/add-monitoring

# 작업 후 커밋
git add .
git commit -m "Add CloudWatch monitoring for restore operations"

# Push
git push origin feature/add-monitoring

# Pull Request 생성
```

### 환경별 Branch

```
main           # Production
├─ develop     # Development
├─ staging     # Staging
└─ feature/*   # Feature branches
```

## Pre-commit Hooks (선택사항)

### Terraform 검증 자동화

`.git/hooks/pre-commit` 생성:

```bash
#!/bin/bash

echo "Running Terraform validation..."

# Source account
cd source-account
if [ -f "main.tf" ]; then
    terraform fmt -check
    if [ $? -ne 0 ]; then
        echo "❌ Terraform fmt failed for source-account"
        exit 1
    fi

    terraform validate
    if [ $? -ne 0 ]; then
        echo "❌ Terraform validate failed for source-account"
        exit 1
    fi
fi

# Target account
cd ../target-account
if [ -f "main.tf" ]; then
    terraform fmt -check
    if [ $? -ne 0 ]; then
        echo "❌ Terraform fmt failed for target-account"
        exit 1
    fi

    terraform validate
    if [ $? -ne 0 ]; then
        echo "❌ Terraform validate failed for target-account"
        exit 1
    fi
fi

echo "✅ All checks passed"
exit 0
```

실행 권한 부여:
```bash
chmod +x .git/hooks/pre-commit
```

### pre-commit framework 사용

```bash
# 설치
pip install pre-commit

# .pre-commit-config.yaml 생성
cat > .pre-commit-config.yaml << 'EOF'
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.83.5
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_docs
      - id: terraform_tflint

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: detect-aws-credentials
        args: ['--allow-missing-credentials']
      - id: detect-private-key
EOF

# 설치
pre-commit install

# 수동 실행
pre-commit run --all-files
```

## GitHub Actions CI/CD (선택사항)

`.github/workflows/terraform.yml`:

```yaml
name: Terraform Validation

on:
  pull_request:
    paths:
      - '**.tf'
      - '**.tfvars.example'
  push:
    branches:
      - main

jobs:
  validate:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.6.0

      - name: Terraform Format Check
        run: |
          cd source-account && terraform fmt -check
          cd ../target-account && terraform fmt -check

      - name: Terraform Init (Source)
        run: |
          cd source-account
          terraform init -backend=false

      - name: Terraform Validate (Source)
        run: |
          cd source-account
          terraform validate

      - name: Terraform Init (Target)
        run: |
          cd target-account
          terraform init -backend=false

      - name: Terraform Validate (Target)
        run: |
          cd target-account
          terraform validate
```

## 문제 해결

### terraform.tfvars가 Git에 추가됨

```bash
# Git cache에서 제거
git rm --cached source-account/terraform.tfvars
git rm --cached target-account/terraform.tfvars

# 커밋
git commit -m "Remove terraform.tfvars from git"
```

### 민감한 정보가 이미 커밋됨

```bash
# Git history에서 완전히 제거 (주의!)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch source-account/terraform.tfvars" \
  --prune-empty --tag-name-filter cat -- --all

# 또는 BFG Repo-Cleaner 사용
java -jar bfg.jar --delete-files terraform.tfvars

# Force push (주의!)
git push origin --force --all
```

### .gitignore 동작 확인

```bash
# 무시되는 파일 목록 확인
git status --ignored

# 특정 파일이 무시되는지 확인
git check-ignore -v source-account/terraform.tfvars

# 출력:
# .gitignore:11:**/*.tfvars    source-account/terraform.tfvars
```

## 체크리스트

커밋 전 확인사항:

- [ ] terraform.tfvars 파일이 Git에 추가되지 않았는가?
- [ ] AWS credentials (.pem, .key)가 포함되지 않았는가?
- [ ] Terraform state 파일이 제외되었는가?
- [ ] 민감한 Account ID나 bucket 이름이 코드에 하드코딩되지 않았는가?
- [ ] terraform.tfvars.example이 최신 상태인가?
- [ ] README.md가 업데이트되었는가?

## 참고 자료

- [Git Documentation](https://git-scm.com/doc)
- [GitHub Best Practices](https://github.com/skills/introduction-to-github)
- [Terraform .gitignore](https://github.com/github/gitignore/blob/main/Terraform.gitignore)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
