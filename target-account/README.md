# Target Account Configuration

Target 계정에 데이터를 받을 S3 버킷과 필요한 IAM 권한을 생성합니다.

## 구성 내용

### 생성되는 리소스
1. **S3 Bucket**: 데이터를 받을 타겟 버킷
2. **IAM Role**: 크로스 계정 접근용 역할
3. **IAM Policies**: Source 버킷 읽기 + Target 버킷 쓰기 권한
4. **IAM User** (선택): 테스트용 사용자 및 Access Key
5. **CloudWatch Log Group**: 모니터링용

## 사용 방법

### 1. Source Account 정보 준비

Source account에서 다음 정보를 가져옵니다:

```bash
cd ../source-account
terraform output
```

필요한 정보:
- `source_bucket_name`
- `source_account_id` (AWS Console 또는 `aws sts get-caller-identity`로 확인)

### 2. Variables 설정

`terraform.tfvars` 파일 생성:

```hcl
# terraform.tfvars
aws_region          = "ap-northeast-2"
target_bucket_name  = "my-deep-archive-target-2024"  # 전역으로 유니크해야 함
source_account_id   = "123456789012"                  # Source AWS Account ID
source_bucket_name  = "my-deep-archive-source-2024"   # Source bucket name
create_iam_user     = true                            # 테스트용 IAM user 생성
environment         = "test"
```

### 3. Terraform 초기화

```bash
terraform init
```

### 4. 계획 확인

```bash
terraform plan
```

### 5. 적용

```bash
terraform apply
```

### 6. Credentials 확인 (IAM User 생성한 경우)

```bash
# Access Key 확인
terraform output -raw iam_user_access_key

# Secret Key 확인 (한 번만 확인 가능)
terraform output -raw iam_user_secret_key
```

이 credentials를 안전하게 저장하세요!

### 7. AWS CLI 프로파일 구성

```bash
# ~/.aws/credentials 파일에 추가
[s3-copy-profile]
aws_access_key_id = <ACCESS_KEY>
aws_secret_access_key = <SECRET_KEY>
region = ap-northeast-2
```

## AWS CLI로 직접 설정하는 방법

### 1. Target Bucket 생성

```bash
aws s3api create-bucket \
    --bucket my-deep-archive-target \
    --region ap-northeast-2 \
    --create-bucket-configuration LocationConstraint=ap-northeast-2

# 버전 관리 활성화
aws s3api put-bucket-versioning \
    --bucket my-deep-archive-target \
    --versioning-configuration Status=Enabled

# 암호화 설정
aws s3api put-bucket-encryption \
    --bucket my-deep-archive-target \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }'
```

### 2. IAM Policy 생성

```bash
# Source bucket 읽기 권한
aws iam create-policy \
    --policy-name SourceBucketReadPolicy \
    --policy-document file://source-read-policy.json

# Target bucket 쓰기 권한
aws iam create-policy \
    --policy-name TargetBucketWritePolicy \
    --policy-document file://target-write-policy.json
```

### 3. IAM User 생성 및 권한 부여

```bash
# User 생성
aws iam create-user --user-name s3-copy-user

# Policy 연결
aws iam attach-user-policy \
    --user-name s3-copy-user \
    --policy-arn arn:aws:iam::ACCOUNT-ID:policy/SourceBucketReadPolicy

aws iam attach-user-policy \
    --user-name s3-copy-user \
    --policy-arn arn:aws:iam::ACCOUNT-ID:policy/TargetBucketWritePolicy

# Access Key 생성
aws iam create-access-key --user-name s3-copy-user
```

## 권한 검증

### 1. Source Bucket 접근 테스트

```bash
# Profile 지정하여 테스트
aws s3 ls s3://SOURCE-BUCKET-NAME/ \
    --profile s3-copy-profile
```

성공하면 Source bucket의 객체 목록이 표시됩니다.

### 2. Target Bucket 쓰기 테스트

```bash
# 테스트 파일 업로드
echo "test" > test.txt
aws s3 cp test.txt s3://TARGET-BUCKET-NAME/ \
    --profile s3-copy-profile

# 확인
aws s3 ls s3://TARGET-BUCKET-NAME/ \
    --profile s3-copy-profile
```

### 3. 크로스 계정 복사 테스트

```bash
# Source에서 Target으로 복사 (복원된 객체만 가능)
aws s3 cp \
    s3://SOURCE-BUCKET-NAME/deep-archive/file.txt \
    s3://TARGET-BUCKET-NAME/restored/file.txt \
    --profile s3-copy-profile
```

## IAM Policy 예시

### source-read-policy.json

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::SOURCE-BUCKET-NAME"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::SOURCE-BUCKET-NAME/*"
    }
  ]
}
```

### target-write-policy.json

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::TARGET-BUCKET-NAME"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::TARGET-BUCKET-NAME/*"
    }
  ]
}
```

## 문제 해결

### Access Denied 오류

```
An error occurred (AccessDenied) when calling the GetObject operation
```

원인:
1. Source bucket policy에서 target account 허용 안 함
2. IAM user/role에 필요한 권한 없음
3. 객체가 아직 Deep Archive에서 복원되지 않음

해결:
```bash
# Source bucket policy 확인
aws s3api get-bucket-policy \
    --bucket SOURCE-BUCKET-NAME \
    --query Policy \
    --output text | jq

# IAM 권한 확인
aws iam list-attached-user-policies --user-name s3-copy-user
```

### InvalidObjectState 오류

```
The operation is not valid for the object's storage class
```

원인: Deep Archive 객체를 복원하지 않고 접근 시도

해결:
```bash
# 먼저 복원 필요
aws s3api restore-object \
    --bucket SOURCE-BUCKET-NAME \
    --key deep-archive/file.txt \
    --restore-request Days=7,GlacierJobParameters={Tier=Bulk}
```

## 보안 고려사항

### 1. Least Privilege 원칙
- 필요한 최소 권한만 부여
- Bucket policy에서 특정 prefix만 허용 가능

### 2. Access Key 보안
- Access key를 코드에 하드코딩하지 말 것
- AWS Secrets Manager나 Parameter Store 사용 고려
- 주기적으로 key rotation

### 3. 로깅 및 모니터링
- S3 access logging 활성화
- CloudTrail로 API 호출 모니터링
- CloudWatch로 이상 패턴 감지

## 비용 최적화

### Target Bucket Storage Class 선택

데이터 접근 패턴에 따라 선택:

| Storage Class | 비용/GB/월 | 사용 사례 |
|---------------|------------|----------|
| Standard | $0.023 | 자주 접근 |
| Intelligent-Tiering | $0.023 + $0.0025 (모니터링) | 접근 패턴 불규칙 |
| Glacier Instant Retrieval | $0.004 | 분기별 1회 접근 |
| Glacier Flexible Retrieval | $0.0036 | 연 1-2회 접근 |

Terraform에서 변경:
```hcl
# main.tf의 lifecycle rule 수정
transition {
  days          = 0
  storage_class = "INTELLIGENT_TIERING"  # 또는 다른 class
}
```

## 정리

```bash
# IAM User의 Access Key 삭제 (선택사항)
aws iam delete-access-key \
    --user-name s3-copy-user \
    --access-key-id ACCESS_KEY_ID

# Terraform으로 모든 리소스 삭제
terraform destroy
```

## 다음 단계

Target account 설정 완료 후:
1. `../scripts/` 디렉토리로 이동
2. 테스트 스크립트 실행
3. 실제 데이터 전송 테스트
