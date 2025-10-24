# S3 Deep Archive 크로스 계정 전송 시나리오

## 목적
S3 Deep Archive에 저장된 데이터를 다른 AWS 계정으로 안전하게 전송하는 방법을 단계별로 실습합니다.

## 시나리오 구성

```
Account A (Source)          Account B (Target)
   └─ Bucket A                  └─ Bucket B
      └─ Deep Archive              └─ Standard/IA
         Data
```

## 디렉토리 구조

```
s3-deep-archive/
├── README.md                    # 이 파일
├── source-account/              # Source 계정 설정
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── bucket-policy.json
├── target-account/              # Target 계정 설정
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── iam-policy.json
├── scripts/                     # 실행 스크립트
│   ├── 01-upload-to-deep-archive.sh
│   ├── 02-restore-from-deep-archive.sh
│   ├── 03-cross-account-copy.sh
│   └── 04-cleanup.sh
├── test-data/                   # 테스트용 샘플 데이터
│   └── sample-files/
└── docs/                        # 추가 문서
    ├── cost-estimation.md
    └── troubleshooting.md
```

## 실습 단계

### Phase 1: 환경 준비
1. **Prerequisites 확인**
   - AWS CLI 설치 및 구성
   - 두 개의 AWS 계정 액세스 권한
   - Terraform 설치 (선택사항)

2. **Source 계정 설정**
   ```bash
   cd source-account
   terraform init
   terraform plan
   terraform apply
   ```

3. **Target 계정 설정**
   ```bash
   cd target-account
   terraform init
   terraform plan
   terraform apply
   ```

### Phase 2: Deep Archive 테스트
1. **테스트 데이터 업로드**
   ```bash
   cd scripts
   ./01-upload-to-deep-archive.sh
   ```
   - 샘플 파일을 Deep Archive로 즉시 저장
   - 업로드 완료 확인

2. **Deep Archive 복원**
   ```bash
   ./02-restore-from-deep-archive.sh
   ```
   - Bulk 복원 요청 (12시간 소요)
   - 복원 상태 모니터링
   - 복원 완료 확인

### Phase 3: 크로스 계정 전송
1. **크로스 계정 복사**
   ```bash
   ./03-cross-account-copy.sh
   ```
   - Source 버킷 정책 확인
   - Target 계정으로 데이터 복사
   - 전송 완료 확인

2. **검증**
   - Target 버킷에서 데이터 확인
   - 파일 무결성 검증 (MD5/SHA256)
   - 메타데이터 확인

### Phase 4: 정리
```bash
./04-cleanup.sh
```

## 주요 학습 포인트

### 1. Deep Archive 특성
- **최저 비용**: $0.00099/GB/월
- **복원 시간**: 12시간 (Bulk), 12시간 (Standard)
- **최소 보관 기간**: 180일
- **최소 객체 크기**: 128KB

### 2. 복원 프로세스
```bash
# 복원 요청
aws s3api restore-object \
    --bucket my-bucket \
    --key myfile.txt \
    --restore-request Days=7,GlacierJobParameters={Tier=Bulk}

# 복원 상태 확인
aws s3api head-object \
    --bucket my-bucket \
    --key myfile.txt
```

### 3. 크로스 계정 권한
- Source: Bucket Policy로 Target 계정 허용
- Target: IAM Policy로 Source 버킷 접근 권한

### 4. 비용 최적화
- Bulk 복원 사용 (저렴)
- 같은 리전 내 전송 (무료)
- 복원 기간 최소화

## 예상 비용 (1GB 기준)

| 항목 | 비용 |
|------|------|
| Deep Archive 저장 (1개월) | $0.00099 |
| Bulk 복원 | $0.025 |
| 데이터 전송 (같은 리전) | $0 |
| Target S3 Standard (1개월) | $0.023 |
| **총계** | **~$0.05** |

## 주의사항

1. **복원 대기 시간**: Deep Archive는 복원에 최소 12시간 소요
2. **복원 비용**: 데이터 크기에 따라 비용 발생
3. **임시 복원**: 복원된 데이터는 지정한 기간(Days) 후 자동 삭제
4. **최소 보관**: 180일 이전 삭제 시 나머지 기간 비용 청구
5. **계정 제한**: 각 계정의 서비스 쿼터 확인 필요

## 다음 단계

각 디렉토리의 README를 참고하여 단계별로 진행하세요:
1. `source-account/README.md` - Source 계정 설정
2. `target-account/README.md` - Target 계정 설정
3. `scripts/README.md` - 스크립트 실행 가이드

## 참고 자료
- [AWS S3 Glacier Deep Archive](https://aws.amazon.com/s3/storage-classes/glacier/)
- [S3 Cross-Account Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-walkthroughs-managing-access-example2.html)
- [S3 Restore Objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects.html)
# S3-DeepArchive-Transfer-CrossAccount
# S3-DeepArchive-Transfer-CrossAccount
# S3-DeepArchive-Transfer-CrossAccount
