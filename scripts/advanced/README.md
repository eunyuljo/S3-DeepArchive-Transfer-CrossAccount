# Advanced Scripts - Realistic Scenario

대용량 데이터를 연도별/타입별로 선택적으로 처리하는 고급 스크립트입니다.

## 📋 스크립트 목록

| Script | Purpose | Usage |
|--------|---------|-------|
| `00-create-realistic-test-data.sh` | 연도별 테스트 데이터 생성 | `./00 [bucket] [size-mode]` |
| `01-upload-selective.sh` | 선택적 업로드 (연도/타입) | `./01 [bucket] [year] [type]` |
| `02-restore-selective.sh` | 선택적 복원 | `./02 [bucket] [year] [type]` |
| `03-copy-selective.sh` | 선택적 복사 | `./03 [source] [target] [year] [type]` |

## 🎯 사용 대상

- ✅ 대용량 데이터 처리 (100GB ~ TB급)
- ✅ 연도별 데이터 관리
- ✅ 선택적 복원 (비용 최적화)
- ✅ 프로덕션 환경 준비
- ✅ 실전 시나리오 테스트

## 📊 데이터 구조

```
2022/
├── backups/  (500GB, 1,234 files)
├── logs/     (120GB, 8,901 files)
└── reports/  (50GB, 456 files)

2023/
├── backups/  (800GB, 2,100 files)
├── logs/     (200GB, 12,345 files)
└── reports/  (80GB, 678 files)

2024/
├── backups/  (1.2TB, 3,456 files)
├── logs/     (350GB, 18,901 files)
└── reports/  (120GB, 890 files)

2025/
├── backups/  (300GB, 890 files)
├── logs/     (80GB, 4,567 files)
└── reports/  (30GB, 234 files)
```

## 🚀 Quick Start

### 시나리오 1: 최신 데이터만 전송 (추천)

```bash
cd /home/ec2-user/claude-code/s3-deep-archive/scripts/advanced

# 1. 테스트 데이터 생성 (medium = ~10GB)
./00-create-realistic-test-data.sh my-bucket medium

# 2. 2024년 데이터만 업로드
./01-upload-selective.sh my-bucket 2024

# 3. 2024년 데이터 복원 요청
./02-restore-selective.sh my-bucket 2024
# Output: Cost: $42.50, ETA: 12 hours

# 4. 12시간 대기...
/tmp/monitor-restore-2024-all.sh  # 상태 확인

# 5. 복사
./03-copy-selective.sh my-source-bucket my-target-bucket 2024
```

### 시나리오 2: 백업만 선택적 전송 (비용 절감)

```bash
# 2024년 백업만 업로드
./01-upload-selective.sh my-bucket 2024 backups

# 백업만 복원 (로그 제외로 비용 29% 절감)
./02-restore-selective.sh my-bucket 2024 backups

# 12시간 후 복사
./03-copy-selective.sh my-source my-target 2024 backups
```

## 📏 Size Modes

테스트 데이터 크기 선택:

| Mode | 총 크기 | 파일수/타입 | 용도 | 비용 |
|------|---------|-------------|------|------|
| **small** | ~100 MB | 5 | 빠른 테스트 | ~$0.01 |
| **medium** | ~10 GB | 20 | 실전 연습 | ~$5 |
| **large** | ~100 GB | 50 | 프로덕션 시뮬레이션 | ~$50 |

```bash
# Small - 빠른 테스트
./00-create-realistic-test-data.sh my-bucket small

# Medium - 추천
./00-create-realistic-test-data.sh my-bucket medium

# Large - 실전 시뮬레이션
./00-create-realistic-test-data.sh my-bucket large
```

## 🎬 상세 사용법

### 0️⃣ Create Test Data

**목적**: 연도별/타입별로 분류된 현실적인 테스트 데이터 생성

```bash
./00-create-realistic-test-data.sh bucket-name [size-mode]

# Examples:
./00-create-realistic-test-data.sh my-bucket small
./00-create-realistic-test-data.sh my-bucket medium

# Output:
# ✓ Created 2022/ (15 files)
# ✓ Created 2023/ (15 files)
# ✓ Created 2024/ (15 files)
# ✓ Created 2025/ (15 files)
# Summary: test-data/realistic/summary.txt
```

**생성 위치**: `../test-data/realistic/`

### 1️⃣ Upload Selective

**목적**: 특정 연도나 타입만 선택적으로 업로드

```bash
./01-upload-selective.sh bucket [year|all] [type|all]

# Examples:
./01-upload-selective.sh my-bucket 2024          # 2024년 전체
./01-upload-selective.sh my-bucket 2024 backups  # 2024년 백업만
./01-upload-selective.sh my-bucket all           # 전체 연도
./01-upload-selective.sh my-bucket 2024 logs     # 2024년 로그만

# Output:
# ✓ Uploaded: 60 files
# ✓ 2024/backups: 20 files, 1.2 GB
# ✓ 2024/logs: 20 files, 350 MB
# ✓ 2024/reports: 20 files, 120 MB
```

### 2️⃣ Restore Selective

**목적**: 특정 연도/타입만 선택적으로 복원

```bash
./02-restore-selective.sh bucket [year] [type] [tier] [days]

# Examples:
./02-restore-selective.sh my-bucket 2024
./02-restore-selective.sh my-bucket 2024 backups
./02-restore-selective.sh my-bucket 2024 all Bulk 7

# Output:
# Objects: 60
# Size: 1.67 GB
# Cost: $42.50 (Bulk tier)
# ETA: ~12 hours
# Monitor: /tmp/monitor-restore-2024-all.sh
```

**복원 상태 모니터링**:
```bash
# 자동 생성된 모니터링 스크립트
/tmp/monitor-restore-2024-all.sh

# Output:
# ✓ Completed: 2024/backups/backups_2024_0001.dat
# ⟳ In Progress: 2024/logs/logs_2024_0001.dat
# Summary: Completed: 45/60
```

### 3️⃣ Copy Selective

**목적**: 복원된 데이터를 Target 계정으로 선택적 복사

```bash
./03-copy-selective.sh source-bucket target-bucket [year] [type]

# Examples:
./03-copy-selective.sh source target 2024
./03-copy-selective.sh source target 2024 backups

# Output:
# Progress: 45/60 (75%)
# Successful: 45
# Skipped: 15 (already exists)
# Speed: 12.5 MB/s
# Report: /tmp/copy-report-2024-all.txt
```

## 💰 비용 예시

### 시나리오별 비용 (Medium 크기 기준)

| 시나리오 | 데이터 | 복원 비용 | 전송 비용 | 총 비용 |
|---------|--------|----------|----------|---------|
| 2024년 전체 | 1.7 GB | $0.04 | $0 | **$0.04** |
| 2024년 백업만 | 1.2 GB | $0.03 | $0 | **$0.03** |
| 2024+2025 | 2.0 GB | $0.05 | $0 | **$0.05** |
| 전체 (2022-2025) | 3.8 GB | $0.10 | $0 | **$0.10** |

### Large 크기 (프로덕션 시뮬레이션)

| 시나리오 | 데이터 | 복원 비용 | 총 비용 |
|---------|--------|----------|---------|
| 2024년 전체 | 17 GB | $0.43 | **$0.43** |
| 백업만 | 12 GB | $0.30 | **$0.30** |
| 전체 | 38 GB | $0.95 | **$0.95** |

## 🎯 시나리오 선택 가이드

### 언제 Basic을 사용할까?

- 처음 Deep Archive를 배우는 경우
- 개념만 빠르게 이해하고 싶을 때
- 몇 개 파일만 테스트
- 비용: $0.01 미만

### 언제 Advanced를 사용할까?

- 실제 프로덕션 환경 준비
- 대용량 데이터 처리 연습
- 선택적 복원으로 비용 최적화
- 연도별/타입별 관리 필요
- 비용: $0.04 ~ $1

## ⏱️ 타임라인 예시

### Day 1

| 시간 | 작업 | 소요 |
|------|------|------|
| 09:00 | 테스트 데이터 생성 | 10분 |
| 09:30 | 2024년 업로드 | 30분 |
| 10:00 | 복원 요청 | 5분 |
| 10:05 | ⏰ **대기 시작** | - |

### Day 2 (12시간 후)

| 시간 | 작업 | 소요 |
|------|------|------|
| 09:00 | 복원 상태 확인 | 2분 |
| 09:10 | 복사 시작 | - |
| 10:00 | 복사 완료 | 50분 |
| 10:10 | 검증 | 10분 |

## 🆚 Basic vs Advanced 비교

| 기능 | Basic | Advanced |
|------|-------|----------|
| **데이터 구조** | 단순 (5 files) | 연도별/타입별 |
| **크기** | 11 MB | 100MB ~ 100GB |
| **선택적 업로드** | ❌ | ✅ |
| **선택적 복원** | ❌ | ✅ |
| **선택적 복사** | ❌ | ✅ |
| **진행 상황 추적** | 기본 | 상세 |
| **재시도** | ❌ | ✅ (체크포인트) |
| **비용 최적화** | - | ✅ |
| **프로덕션 준비** | ❌ | ✅ |

## 📝 Best Practices

### 1. 작은 크기부터 시작

```bash
# Small로 먼저 테스트
./00-create-realistic-test-data.sh my-bucket small
./01-upload-selective.sh my-bucket 2024 backups
./02-restore-selective.sh my-bucket 2024 backups

# 성공 후 Medium으로 확장
./00-create-realistic-test-data.sh my-bucket medium

# 프로덕션 전 Large로 검증
./00-create-realistic-test-data.sh my-bucket large
```

### 2. 선택적 복원으로 비용 절감

```bash
# ❌ 비효율적: 전체 복원
./02-restore-selective.sh my-bucket 2024  # 모든 타입 복원

# ✅ 효율적: 필요한 것만
./02-restore-selective.sh my-bucket 2024 backups  # 백업만
# 비용 29% 절감!
```

### 3. 복원 상태 모니터링

```bash
# 복원 후 자동 생성된 모니터링 스크립트
/tmp/monitor-restore-2024-backups.sh

# 또는 주기적 체크
watch -n 300 /tmp/monitor-restore-2024-backups.sh
# 5분마다 자동 확인
```

### 4. 배치 처리

```bash
# 여러 연도를 한번에 업로드
for YEAR in 2022 2023 2024; do
    ./01-upload-selective.sh my-bucket $YEAR &
done
wait

# 복원도 병렬로
for YEAR in 2022 2023 2024; do
    ./02-restore-selective.sh my-bucket $YEAR &
done
wait
```

## 🔧 고급 기능

### 중복 방지 (자동 스킵)

```bash
# 이미 복사된 파일은 자동 스킵
./03-copy-selective.sh source target 2024

# Output:
# ✓ Copied: 45
# ⊙ Skipped: 15 (already exists, same size)
```

### 진행 상황 파일

```bash
# 실시간 진행 상황
tail -f /tmp/copy-progress-2024-all.txt

# Output:
# SUCCESS:2024/backups/file001.dat
# SUCCESS:2024/backups/file002.dat
# SKIP:2024/logs/file001.dat
```

### 상세 리포트

```bash
# 완료 후 생성되는 리포트
cat /tmp/copy-report-2024-all-20250124-093000.txt

# 포함 내용:
# - 복사 통계
# - 성공/실패/스킵 목록
# - 소요 시간
# - 전송 속도
```

## 🚨 주의사항

1. **복원 대기 시간**: 12시간 필수
2. **Large 모드**: 실제 비용 발생 ($0.50~$1)
3. **동시 복원**: 리전별 제한 확인
4. **네트워크**: 안정적인 연결 필요

## 📚 Related Docs

- **Basic Scripts**: `../basic/README.md`
- **Realistic Scenarios**: `../../REALISTIC_SCENARIO.md`
- **Cost Estimation**: `../../docs/cost-estimation.md`
- **Troubleshooting**: `../../docs/troubleshooting.md`

---

**Ready for production-like testing?**
```bash
./00-create-realistic-test-data.sh my-bucket medium
./01-upload-selective.sh my-bucket 2024
```
