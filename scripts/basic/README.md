# Basic Scripts - Simple Scenario

간단한 테스트와 학습을 위한 기본 스크립트입니다.

## 📋 스크립트 목록

| Script | Purpose | Usage |
|--------|---------|-------|
| `01-upload-to-deep-archive.sh` | 테스트 파일을 Deep Archive로 업로드 | `./01-upload-to-deep-archive.sh [bucket]` |
| `02-restore-from-deep-archive.sh` | Deep Archive 복원 요청 | `./02-restore-from-deep-archive.sh [bucket] [tier] [days]` |
| `02b-wait-for-restore.sh` | 복원 완료 대기 (자동) | `./02b-wait-for-restore.sh [bucket]` |
| `03-cross-account-copy.sh` | Target 계정으로 복사 | `./03-cross-account-copy.sh [source] [target]` |
| `04-cleanup.sh` | 리소스 정리 | `./04-cleanup.sh [options]` |

## 🎯 사용 대상

- ✅ Deep Archive 처음 사용하는 경우
- ✅ 기본 개념 학습
- ✅ 빠른 테스트 (몇 개 파일)
- ✅ 크로스 계정 권한 검증

## 🚀 Quick Start

```bash
cd /home/ec2-user/claude-code/s3-deep-archive/scripts/basic

# 1. 테스트 데이터 업로드
./01-upload-to-deep-archive.sh my-source-bucket

# 2. 복원 요청
./02-restore-from-deep-archive.sh my-source-bucket Bulk 7

# 3. 12시간 대기...

# 4. 복사
./03-cross-account-copy.sh my-source-bucket my-target-bucket

# 5. 정리
./04-cleanup.sh
```

## 📊 생성되는 테스트 데이터

```
test-data/sample-files/
├── test-small.txt      (~100 bytes)
├── test-medium.bin     (1 MB)
├── test-large.bin      (10 MB)
├── test-data.json      (JSON format)
├── test-data.csv       (CSV format)
└── checksums.txt       (무결성 검증용)

총: ~11 MB, 5 files
```

## ⏱️ 소요 시간

- **업로드**: 1-5분
- **복원 요청**: 1분
- **복원 대기**: ~12시간
- **복사**: 5-10분
- **총 실습 시간**: ~20분 (대기 제외)

## 💰 예상 비용

- Storage (1개월): ~$0.01
- Restore (11MB): ~$0.00 (거의 무료)
- Transfer: $0 (같은 리전)
- **총: < $0.01**

## 🔍 상세 가이드

### 1️⃣ Upload Script

**기능**:
- 5개의 다양한 테스트 파일 생성
- Deep Archive storage class로 업로드
- MD5/SHA256 체크섬 생성
- 업로드 검증

**실행**:
```bash
./01-upload-to-deep-archive.sh my-bucket

# Output:
# ✓ Created test files
# ✓ Uploaded to s3://my-bucket/deep-archive/
# ✓ Storage Class: DEEP_ARCHIVE
```

### 2️⃣ Restore Script

**기능**:
- Deep Archive 객체 목록 확인
- 복원 요청 (Bulk/Standard tier)
- 복원 상태 모니터링 스크립트 생성

**실행**:
```bash
./02-restore-from-deep-archive.sh my-bucket Bulk 7

# Parameters:
#   bucket: Source bucket name
#   tier: Bulk (12h, 저렴) or Standard (12h)
#   days: 복원 데이터 유지 기간 (기본: 7일)

# Output:
# ✓ Restore requests sent: 5
# ✓ ETA: ~12 hours
# ✓ Monitor: /tmp/monitor-restore-*.sh
```

**복원 상태 확인**:
```bash
# 자동 생성된 모니터링 스크립트 사용
/tmp/monitor-restore-my-bucket.sh

# 또는 직접 확인
aws s3api head-object \
    --bucket my-bucket \
    --key deep-archive/test-small.txt \
    | grep Restore
```

### 3️⃣ Copy Script

**기능**:
- 복원 상태 확인
- Source → Target 복사
- 체크섬 검증
- 리포트 생성

**실행**:
```bash
./03-cross-account-copy.sh source-bucket target-bucket

# Output:
# ✓ All objects restored
# ✓ Copied: 5 files
# ✓ Integrity verified
# Report: /tmp/copy-report-*.txt
```

### 4️⃣ Cleanup Script

**기능**:
- S3 객체 삭제
- 로컬 테스트 데이터 삭제
- Terraform 리소스 destroy (선택)

**실행**:
```bash
# 대화형 모드
./04-cleanup.sh

# S3 객체만 삭제
./04-cleanup.sh --keep-buckets

# 전체 삭제
./04-cleanup.sh --all
```

## 🆚 Basic vs Advanced

| 항목 | Basic | Advanced |
|------|-------|----------|
| **데이터 구조** | 단순 (5개 파일) | 연도별/타입별 분류 |
| **파일 크기** | ~11 MB | 100MB ~ 100GB |
| **선택적 작업** | ❌ 전체만 | ✅ 연도/타입별 |
| **비용** | ~$0.01 | $5 ~ $100 |
| **학습 목적** | 개념 이해 | 실전 연습 |
| **소요 시간** | 20분 | 1-2일 |

## 🎓 학습 목표

이 스크립트들로 배우는 내용:

1. ✅ Deep Archive 업로드 방법
2. ✅ 복원 프로세스 이해
3. ✅ 복원 대기 시간 체감
4. ✅ 크로스 계정 권한 설정
5. ✅ 데이터 무결성 검증
6. ✅ S3 API 사용법

## 🚧 제한사항

- 소량 데이터만 처리
- 전체 업로드/복원만 가능
- 선택적 작업 불가
- 대용량 처리 최적화 없음

**대용량 데이터나 실전 사용**은 `../advanced/` 스크립트를 사용하세요.

## 📝 Workflow Diagram

```
┌─────────────────────┐
│ 01-upload.sh        │  ← 테스트 파일 업로드
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│ 02-restore.sh       │  ← 복원 요청 (1분)
└──────────┬──────────┘
           │
           v
      ⏰ 12 hours
           │
           v
┌─────────────────────┐
│ 03-copy.sh          │  ← 크로스 계정 복사
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│ 04-cleanup.sh       │  ← 정리
└─────────────────────┘
```

## 🔗 Related

- **Advanced Scripts**: `../advanced/README.md`
- **Main Guide**: `../README.md`
- **Troubleshooting**: `../../docs/troubleshooting.md`
- **Cost Estimation**: `../../docs/cost-estimation.md`

## 💡 Tips

1. **처음 실행 시**: 작은 버킷 이름으로 시작 (나중에 삭제 쉬움)
2. **복원 대기 시**: 저녁에 요청 → 다음날 아침 복사
3. **검증**: 체크섬 파일 확인 (test-data/sample-files/checksums.txt)
4. **비용**: AWS Cost Explorer에서 확인

---

**Ready to start?**
```bash
./01-upload-to-deep-archive.sh your-bucket-name
```
