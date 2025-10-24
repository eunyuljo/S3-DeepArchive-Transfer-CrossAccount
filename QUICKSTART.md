# Quick Start Guide

S3 Deep Archive 크로스 계정 전송을 10분 안에 시작하세요!

## Prerequisites (5분)

### 1. AWS CLI 설치

```bash
# Linux/macOS
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# 확인
aws --version
```

### 2. AWS 자격증명 구성

두 개의 AWS 계정이 필요합니다:

```bash
# Source account 구성
aws configure --profile source
# Access Key, Secret Key, Region (ap-northeast-2) 입력

# Target account 구성
aws configure --profile target
# Access Key, Secret Key, Region (ap-northeast-2) 입력

# 확인
aws sts get-caller-identity --profile source
aws sts get-caller-identity --profile target
```

### 3. Account ID 확인

```bash
# Source Account ID
SOURCE_ACCOUNT_ID=$(aws sts get-caller-identity --profile source --query Account --output text)
echo "Source Account: $SOURCE_ACCOUNT_ID"

# Target Account ID
TARGET_ACCOUNT_ID=$(aws sts get-caller-identity --profile target --query Account --output text)
echo "Target Account: $TARGET_ACCOUNT_ID"
```

## Option A: Terraform으로 자동 구성 (추천, 5분)

### 1. Source Account 설정

```bash
cd source-account

# terraform.tfvars 생성
cat > terraform.tfvars << EOF
aws_region         = "ap-northeast-2"
source_bucket_name = "my-deep-archive-source-$(date +%Y%m%d)"
target_account_id  = "$TARGET_ACCOUNT_ID"
environment        = "test"
EOF

# Terraform 실행
terraform init
terraform apply -auto-approve

# Bucket 이름 저장
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
echo $SOURCE_BUCKET
```

### 2. Target Account 설정

```bash
cd ../target-account

# terraform.tfvars 생성
cat > terraform.tfvars << EOF
aws_region         = "ap-northeast-2"
target_bucket_name = "my-deep-archive-target-$(date +%Y%m%d)"
source_account_id  = "$SOURCE_ACCOUNT_ID"
source_bucket_name = "$SOURCE_BUCKET"
environment        = "test"
create_iam_user    = true
EOF

# Terraform 실행
terraform init
terraform apply -auto-approve

# Bucket 이름 확인
terraform output target_bucket_name
```

### 3. 테스트 시작!

```bash
cd ../scripts

# Source account 프로파일 사용
export AWS_PROFILE=source

# 1. 테스트 데이터 업로드
./01-upload-to-deep-archive.sh $SOURCE_BUCKET

# 2. 복원 요청
./02-restore-from-deep-archive.sh $SOURCE_BUCKET Bulk 7

# 3. 12시간 대기... (복원 완료 체크)
# 복원 상태 확인 스크립트가 자동 생성됨

# 4. Target account 프로파일로 전환
export AWS_PROFILE=target

# 5. 복원 완료 후 복사
./03-cross-account-copy.sh $SOURCE_BUCKET $TARGET_BUCKET

# 6. 확인
aws s3 ls s3://$TARGET_BUCKET/restored/ --recursive
```

## Option B: AWS CLI로 수동 구성 (10분)

### 1. Source Bucket 생성

```bash
# Source account로 전환
export AWS_PROFILE=source

# Bucket 생성
SOURCE_BUCKET="deep-archive-source-$(date +%Y%m%d%H%M)"
aws s3 mb s3://$SOURCE_BUCKET --region ap-northeast-2

# 버전 관리 활성화
aws s3api put-bucket-versioning \
    --bucket $SOURCE_BUCKET \
    --versioning-configuration Status=Enabled

# Bucket Policy 설정 (cross-account 접근 허용)
cat > bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::$TARGET_ACCOUNT_ID:root"},
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::$SOURCE_BUCKET",
      "arn:aws:s3:::$SOURCE_BUCKET/*"
    ]
  }]
}
EOF

aws s3api put-bucket-policy \
    --bucket $SOURCE_BUCKET \
    --policy file://bucket-policy.json
```

### 2. Target Bucket 생성

```bash
# Target account로 전환
export AWS_PROFILE=target

# Bucket 생성
TARGET_BUCKET="deep-archive-target-$(date +%Y%m%d%H%M)"
aws s3 mb s3://$TARGET_BUCKET --region ap-northeast-2

# 버전 관리 활성화
aws s3api put-bucket-versioning \
    --bucket $TARGET_BUCKET \
    --versioning-configuration Status=Enabled
```

### 3. IAM 권한 설정

```bash
# Target account에서 IAM policy 생성
cat > iam-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::$SOURCE_BUCKET",
        "arn:aws:s3:::$SOURCE_BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::$TARGET_BUCKET/*"
    }
  ]
}
EOF

# Policy 생성 및 사용자에게 연결
aws iam create-policy \
    --policy-name S3CrossAccountCopyPolicy \
    --policy-document file://iam-policy.json

# 현재 사용자에게 policy 연결 (username 교체 필요)
aws iam attach-user-policy \
    --user-name YOUR-USERNAME \
    --policy-arn arn:aws:iam::$TARGET_ACCOUNT_ID:policy/S3CrossAccountCopyPolicy
```

### 4. 테스트 데이터 업로드

```bash
# Source account로 전환
export AWS_PROFILE=source

# 테스트 파일 생성
mkdir -p test-files
echo "Test data $(date)" > test-files/test.txt
dd if=/dev/urandom of=test-files/test-10mb.bin bs=1M count=10

# Deep Archive로 업로드
aws s3 cp test-files/test.txt \
    s3://$SOURCE_BUCKET/deep-archive/test.txt \
    --storage-class DEEP_ARCHIVE

aws s3 cp test-files/test-10mb.bin \
    s3://$SOURCE_BUCKET/deep-archive/test-10mb.bin \
    --storage-class DEEP_ARCHIVE

# 확인
aws s3 ls s3://$SOURCE_BUCKET/deep-archive/ --recursive
```

### 5. 복원 및 복사

```bash
# 복원 요청
aws s3api restore-object \
    --bucket $SOURCE_BUCKET \
    --key deep-archive/test.txt \
    --restore-request Days=7,GlacierJobParameters={Tier=Bulk}

aws s3api restore-object \
    --bucket $SOURCE_BUCKET \
    --key deep-archive/test-10mb.bin \
    --restore-request Days=7,GlacierJobParameters={Tier=Bulk}

# 복원 상태 확인
aws s3api head-object \
    --bucket $SOURCE_BUCKET \
    --key deep-archive/test.txt \
    | grep Restore

# 복원 완료 대기 (~12시간)
# "ongoing-request=\"false\"" 가 보이면 완료

# Target account로 복사
export AWS_PROFILE=target

aws s3 cp \
    s3://$SOURCE_BUCKET/deep-archive/test.txt \
    s3://$TARGET_BUCKET/restored/test.txt

aws s3 cp \
    s3://$SOURCE_BUCKET/deep-archive/test-10mb.bin \
    s3://$TARGET_BUCKET/restored/test-10mb.bin

# 확인
aws s3 ls s3://$TARGET_BUCKET/restored/ --recursive
```

## 빠른 검증

### Source Bucket 검증

```bash
export AWS_PROFILE=source

# Bucket 존재 확인
aws s3 ls s3://$SOURCE_BUCKET/

# 객체 및 Storage Class 확인
aws s3api head-object \
    --bucket $SOURCE_BUCKET \
    --key deep-archive/test.txt

# 출력에서 "StorageClass": "DEEP_ARCHIVE" 확인
```

### Target Bucket 검증

```bash
export AWS_PROFILE=target

# Bucket 존재 확인
aws s3 ls s3://$TARGET_BUCKET/

# Source bucket 접근 가능 확인
aws s3 ls s3://$SOURCE_BUCKET/deep-archive/
```

### Cross-Account 권한 검증

```bash
# Target account에서 source bucket 읽기 테스트
export AWS_PROFILE=target

aws s3api get-object \
    --bucket $SOURCE_BUCKET \
    --key deep-archive/test.txt \
    /tmp/test.txt

# 성공하면 권한이 올바르게 설정됨
```

## 일반적인 첫 실행 문제

### 문제 1: AccessDenied

```bash
# 현재 identity 확인
aws sts get-caller-identity --profile source
aws sts get-caller-identity --profile target

# 올바른 profile 사용 중인지 확인
echo $AWS_PROFILE
```

### 문제 2: BucketAlreadyExists

```bash
# Bucket 이름에 timestamp 추가
SOURCE_BUCKET="deep-archive-source-$USER-$(date +%Y%m%d%H%M%S)"
```

### 문제 3: InvalidObjectState (복원 안 됨)

```bash
# 복원 상태 확인
aws s3api head-object \
    --bucket $SOURCE_BUCKET \
    --key deep-archive/test.txt \
    | grep Restore

# "ongoing-request=\"true\"" → 아직 복원 중
# "ongoing-request=\"false\"" → 복원 완료
```

## 다음 단계

### 더 자세히 알아보기

- 전체 시나리오: [README.md](README.md)
- 비용 계산: [docs/cost-estimation.md](docs/cost-estimation.md)
- 문제 해결: [docs/troubleshooting.md](docs/troubleshooting.md)

### 프로덕션 사용

1. **자동화**: Scripts를 CI/CD 파이프라인에 통합
2. **모니터링**: CloudWatch 알람 설정
3. **비용 추적**: Cost Explorer에서 정기 확인
4. **백업**: Terraform state를 S3에 저장

### 정리

테스트 완료 후:

```bash
# Terraform 사용한 경우
cd source-account && terraform destroy -auto-approve
cd ../target-account && terraform destroy -auto-approve

# 또는 cleanup script 사용
cd scripts
./04-cleanup.sh --all
```

## 도움말

### 명령어 치트시트

```bash
# Bucket 목록
aws s3 ls

# Bucket 내용 확인
aws s3 ls s3://bucket-name/ --recursive

# Object 메타데이터
aws s3api head-object --bucket bucket-name --key key

# 복원 요청
aws s3api restore-object --bucket bucket --key key \
    --restore-request Days=7,GlacierJobParameters={Tier=Bulk}

# 파일 복사
aws s3 cp s3://source/key s3://target/key

# Storage class 지정 복사
aws s3 cp file.txt s3://bucket/key --storage-class DEEP_ARCHIVE
```

### 유용한 프로파일 설정

```bash
# ~/.bashrc 또는 ~/.zshrc에 추가
alias aws-source='export AWS_PROFILE=source && echo "Using SOURCE account"'
alias aws-target='export AWS_PROFILE=target && echo "Using TARGET account"'

# 사용
aws-source  # Source account로 전환
aws-target  # Target account로 전환
```

## 5분 체크리스트

완료된 항목을 체크하세요:

- [ ] AWS CLI 설치 및 구성
- [ ] Source와 Target account 자격증명 설정
- [ ] Source bucket 생성 및 bucket policy 설정
- [ ] Target bucket 생성
- [ ] IAM 권한 설정
- [ ] 테스트 파일 Deep Archive로 업로드
- [ ] 복원 요청
- [ ] 복원 완료 대기 설정
- [ ] Cross-account 권한 검증

모두 완료했다면 이제 복원이 완료되기를 기다리면 됩니다! (약 12시간)

## 지원

질문이나 이슈가 있으면:
- GitHub Issues
- AWS Forums
- AWS Support (프로덕션 환경)

Happy archiving! 🚀
