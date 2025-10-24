# Source Account Configuration

Source 계정에 Deep Archive를 지원하는 S3 버킷을 생성합니다.

## 구성 내용

### 생성되는 리소스
1. **S3 Bucket**: Deep Archive 저장용 버킷
2. **Bucket Policy**: Target 계정의 크로스 계정 접근 허용
3. **Lifecycle Rule**: Deep Archive로 자동 전환
4. **Encryption**: 기본 암호화 활성화
5. **Versioning**: 버전 관리 활성화

### Lifecycle Rule 설정
```hcl
deep-archive/ prefix로 업로드된 파일은 즉시 Deep Archive로 전환
```

## 사용 방법

### 1. Variables 설정

`terraform.tfvars` 파일을 생성하거나 직접 입력:

```hcl
# terraform.tfvars
aws_region          = "ap-northeast-2"
source_bucket_name  = "my-deep-archive-source-2025"  # 전역으로 유니크해야 함
target_account_id   = "987654321098"                  # Target AWS Account ID
environment         = "test"
```

### 2. Terraform 초기화

```bash
terraform init
```

### 3. 계획 확인

```bash
terraform plan
```

### 4. 적용

```bash
terraform apply
```

### 5. Output 확인

```bash
terraform output
```

출력된 정보를 메모해두세요:
- `source_bucket_name`: Target account 설정에 필요
- `source_bucket_arn`: 권한 확인에 필요

## AWS CLI로 직접 설정하는 방법

Terraform을 사용하지 않고 AWS CLI로 설정:

```bash
# 1. 버킷 생성
aws s3api create-bucket \
    --bucket my-deep-archive-source \
    --region ap-northeast-2 \
    --create-bucket-configuration LocationConstraint=ap-northeast-2

# 2. 버전 관리 활성화
aws s3api put-bucket-versioning \
    --bucket my-deep-archive-source \
    --versioning-configuration Status=Enabled

# 3. 암호화 설정
aws s3api put-bucket-encryption \
    --bucket my-deep-archive-source \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }'

# 4. Lifecycle 정책 설정
aws s3api put-bucket-lifecycle-configuration \
    --bucket my-deep-archive-source \
    --lifecycle-configuration file://lifecycle-policy.json

# 5. 버킷 정책 설정
aws s3api put-bucket-policy \
    --bucket my-deep-archive-source \
    --policy file://bucket-policy.json
```

### lifecycle-policy.json 예시
```json
{
  "Rules": [
    {
      "Id": "move-to-deep-archive",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "deep-archive/"
      },
      "Transitions": [
        {
          "Days": 0,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ]
    }
  ]
}
```

### bucket-policy.json 예시
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossAccountRead",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::TARGET-ACCOUNT-ID:root"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-deep-archive-source",
        "arn:aws:s3:::my-deep-archive-source/*"
      ]
    }
  ]
}
```

## 검증

### 버킷 생성 확인
```bash
aws s3 ls | grep deep-archive-source
```

### Lifecycle 정책 확인
```bash
aws s3api get-bucket-lifecycle-configuration \
    --bucket my-deep-archive-source
```

### 버킷 정책 확인
```bash
aws s3api get-bucket-policy \
    --bucket my-deep-archive-source | jq -r '.Policy | fromjson'
```

## 문제 해결

### 버킷 이름 중복
```
Error: bucket already exists
```
→ 버킷 이름을 전역으로 유니크하게 변경

### 권한 오류
```
Error: Access Denied
```
→ AWS 자격증명 및 IAM 권한 확인

### 리전 오류
```
Error: IllegalLocationConstraintException
```
→ us-east-1이 아닌 경우 LocationConstraint 필수

## 정리

```bash
terraform destroy
```

주의: 버킷에 데이터가 있으면 삭제 실패합니다. 먼저 버킷을 비워야 합니다.

```bash
aws s3 rm s3://my-deep-archive-source --recursive
terraform destroy
```

## 다음 단계

Source account 설정 완료 후:
1. `../target-account/` 디렉토리로 이동
2. Target account 설정 진행
3. 테스트 스크립트 실행
