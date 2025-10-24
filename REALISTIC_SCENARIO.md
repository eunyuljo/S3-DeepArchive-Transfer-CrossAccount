## 🎯 현실적인 대용량 시나리오

연도별로 분류된 대용량 파일을 선택적으로 전송하는 시나리오입니다.

## 📊 데이터 구조

```
Deep Archive (Source Account)
├─ 2022/
│  ├─ backups/  (500GB, 1,234 files)
│  ├─ logs/     (120GB, 8,901 files)
│  └─ reports/  (50GB, 456 files)
├─ 2023/
│  ├─ backups/  (800GB, 2,100 files)
│  ├─ logs/     (200GB, 12,345 files)
│  └─ reports/  (80GB, 678 files)
├─ 2024/
│  ├─ backups/  (1.2TB, 3,456 files)
│  ├─ logs/     (350GB, 18,901 files)
│  └─ reports/  (120GB, 890 files)
└─ 2025/
   ├─ backups/  (300GB, 890 files)
   ├─ logs/     (80GB, 4,567 files)
   └─ reports/  (30GB, 234 files)

총: ~3.8TB, 53,652 files
```

## 🎬 시나리오별 전략

### 시나리오 1: 최신 데이터만 마이그레이션 ⭐ (추천)

**목표**: 2024년 데이터만 Target 계정으로 이전

```bash
# Day 1 - 준비
cd source-account
terraform apply  # Source 인프라 구성

cd ../target-account
terraform apply  # Target 인프라 구성

# Day 1 - 테스트 데이터 생성
cd ../scripts
./00-create-realistic-test-data.sh eyjo-archive-source-2025 medium
# medium: ~10GB 테스트 데이터

# Day 1 - 2024년 데이터만 업로드
./01-upload-selective.sh eyjo-archive-source-2025 2024
# Output: 2024/backups, 2024/logs, 2024/reports 업로드

# Day 1 - 2024년 데이터 복원 요청
./02-restore-selective.sh eyjo-archive-source-2025 2024
# Output:
#   Estimated Cost: $42.50 (Bulk tier)
#   ETA: 12 hours

# ⏰ 12시간 대기 (Day 1 저녁 → Day 2 아침)

# Day 2 - 복원 상태 확인
/tmp/monitor-restore-2024-all.sh
# Output: ✓ All objects restored!

# Day 2 - Target으로 복사
./03-copy-selective.sh \
    eyjo-archive-source-2025 \
    eyjo-archive-target-2025 \
    2024
# Output: Successful: 60 files, 1.67 GB
```

**비용 (1.7TB 기준)**:
- 복원: $42.50 (Bulk)
- 전송: $0 (같은 리전)
- **총: ~$43**

---

### 시나리오 2: 백업 파일만 선택적 전송

**목표**: 로그는 제외하고 백업 파일만 전송 (비용 절감)

```bash
# 2024년 백업만 업로드
./01-upload-selective.sh eyjo-archive-source-2025 2024 backups

# 백업만 복원
./02-restore-selective.sh eyjo-archive-source-2025 2024 backups
# 비용: ~$30 (로그 제외로 $12 절약)

# 백업만 복사
./03-copy-selective.sh \
    eyjo-archive-source-2025 \
    eyjo-archive-target-2025 \
    2024 \
    backups
```

**비용 절감**:
- 전체 복원: $42.50
- 백업만: $30.00
- **절약: $12.50 (29%)**

---

### 시나리오 3: 다년도 순차적 전송

**목표**: 여러 연도를 우선순위대로 전송

```bash
# Phase 1: 최신 연도 (2024, 2025)
./01-upload-selective.sh eyjo-archive-source-2025 2024
./01-upload-selective.sh eyjo-archive-source-2025 2025

./02-restore-selective.sh eyjo-archive-source-2025 2024
./02-restore-selective.sh eyjo-archive-source-2025 2025

# 12시간 후
./03-copy-selective.sh \
    eyjo-archive-source-2025 \
    eyjo-archive-target-2025 \
    2024

./03-copy-selective.sh \
    eyjo-archive-source-2025 \
    eyjo-archive-target-2025 \
    2025

# Phase 2: 이전 연도 (필요 시)
# 1주일 후...
./02-restore-selective.sh eyjo-archive-source-2025 2023
# 12시간 후
./03-copy-selective.sh \
    eyjo-archive-source-2025 \
    eyjo-archive-target-2025 \
    2023
```

---

### 시나리오 4: 전체 데이터 마이그레이션

**목표**: 모든 데이터를 Target으로 이전

```bash
# 전체 업로드
./01-upload-selective.sh eyjo-archive-source-2025 all

# 배치로 복원 (리전 제한 고려)
# Batch 1: 2022, 2023
./02-restore-selective.sh eyjo-archive-source-2025 2022 &
./02-restore-selective.sh eyjo-archive-source-2025 2023 &
wait

# Batch 2: 2024, 2025
./02-restore-selective.sh eyjo-archive-source-2025 2024 &
./02-restore-selective.sh eyjo-archive-source-2025 2025 &
wait

# 12시간 후 - 복사
for YEAR in 2022 2023 2024 2025; do
    ./03-copy-selective.sh \
        eyjo-archive-source-2025 \
        eyjo-archive-target-2025 \
        $YEAR
done
```

**비용 (3.8TB 전체)**:
- 복원: $95.00 (Bulk)
- 전송: $0
- **총: ~$95**

---

## 🎯 추천 전략 결정 트리

```
데이터를 어떻게 전송할까?
    │
    ├─ 전체 필요?
    │   └─ YES → 시나리오 4 (전체 마이그레이션)
    │
    └─ NO → 일부만 필요
        │
        ├─ 최신 연도만?
        │   └─ YES → 시나리오 1 (2024만)
        │
        └─ NO → 특정 타입만?
            │
            ├─ 백업만?
            │   └─ YES → 시나리오 2 (백업만)
            │
            └─ 여러 연도?
                └─ YES → 시나리오 3 (순차적)
```

## 📅 타임라인 예시

### Week 1: 테스트 및 최신 데이터

| Day | 시간 | 작업 | 상태 |
|-----|------|------|------|
| Mon | 09:00 | 인프라 구성 (Terraform) | ✓ 완료 (30분) |
| Mon | 10:00 | 테스트 데이터 생성 | ✓ 완료 (10분) |
| Mon | 10:30 | 2024년 업로드 | ✓ 완료 (30분) |
| Mon | 11:00 | 복원 요청 | ✓ 완료 (5분) |
| Mon | 11:00 | ⏰ **대기 시작** | 12시간 |
| Mon | 23:00 | 복원 완료 | ✓ |
| Tue | 09:00 | 복원 확인 | ✓ |
| Tue | 09:30 | 복사 시작 | 진행 중 |
| Tue | 10:30 | 복사 완료 | ✓ 완료 |
| Tue | 11:00 | 검증 | ✓ 완료 |

### Week 2: 추가 연도 (선택사항)

| Day | 작업 |
|-----|------|
| Mon | 2025년 복원 요청 |
| Tue | 2025년 복사 |
| Wed | 검증 및 보고서 |

---

## 💡 Best Practices

### 1. 작은 것부터 시작 (Recommended)

```bash
# 1단계: Small 크기로 테스트
./00-create-realistic-test-data.sh my-bucket small
./01-upload-selective.sh my-bucket 2024 backups

# 검증 OK → 2단계
./00-create-realistic-test-data.sh my-bucket medium

# 검증 OK → 3단계 (프로덕션)
# 실제 데이터로 진행
```

### 2. 복원 전 비용 확인

```bash
# Dry-run: 비용 확인만
./02-restore-selective.sh my-bucket 2024
# Output:
#   Objects: 1,234
#   Size: 1.7 GB
#   Cost: $42.50
# → n 입력 (취소)

# 승인 후 실제 실행
# → y 입력
```

### 3. 진행 상황 추적

```bash
# 복원 모니터링
watch -n 300 /tmp/monitor-restore-2024-all.sh
# 5분마다 자동 체크

# 복사 진행 상황
tail -f /tmp/copy-progress-2024-all.txt
# 실시간 로그
```

### 4. 체크포인트 저장

```bash
# 복사 중 중단되어도 재개 가능
./03-copy-selective.sh source target 2024
# 이미 복사된 파일은 자동 스킵
# (크기 비교로 중복 방지)
```

### 5. 배치 처리

```bash
# 여러 연도/타입을 한 번에
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

---

## 📊 비용 비교표

| 시나리오 | 데이터 크기 | 복원 비용 | 전송 비용 | 총 비용 |
|---------|------------|----------|----------|---------|
| 2024년만 | 1.7TB | $42.50 | $0 | **$42.50** |
| 백업만 (2024) | 1.2TB | $30.00 | $0 | **$30.00** |
| 2024+2025 | 2.0TB | $50.00 | $0 | **$50.00** |
| 전체 (3.8TB) | 3.8TB | $95.00 | $0 | **$95.00** |

### 비용 절감 팁

1. **Bulk tier 사용**: Standard 대비 75% 저렴
2. **선택적 복원**: 필요한 것만 복원
3. **같은 리전**: 데이터 전송 비용 무료
4. **복원 기간 최소화**: 7일 → 3일로 단축

---

## 🚀 빠른 시작

### 테스트 환경 (10분)

```bash
# 1. 인프라
cd source-account && terraform apply && cd -
cd target-account && terraform apply && cd -

# 2. Small 테스트 데이터
cd scripts
./00-create-realistic-test-data.sh eyjo-archive-source-2025 small

# 3. 2024년 백업만 테스트
./01-upload-selective.sh eyjo-archive-source-2025 2024 backups
./02-restore-selective.sh eyjo-archive-source-2025 2024 backups

# 4. 12시간 후
./03-copy-selective.sh \
    eyjo-archive-source-2025 \
    eyjo-archive-target-2025 \
    2024 \
    backups
```

### 프로덕션 (실제 데이터)

```bash
# 실제 데이터를 연도별 prefix로 업로드
aws s3 sync /backup/2024 s3://my-bucket/2024/ --storage-class DEEP_ARCHIVE

# 복원 및 전송
./02-restore-selective.sh my-bucket 2024
# (12시간 후)
./03-copy-selective.sh my-bucket target-bucket 2024
```

---

## 📝 체크리스트

시작 전 확인:

- [ ] Source/Target 계정 Terraform 적용 완료
- [ ] AWS Profile 설정 완료
- [ ] 버킷 접근 권한 확인
- [ ] 예상 비용 계산 완료
- [ ] 복원 대기 시간 고려 (12시간)
- [ ] Target storage class 결정
- [ ] 백업 검증 계획 수립

작업 중:

- [ ] 복원 요청 완료
- [ ] 복원 상태 모니터링 중
- [ ] 복사 진행 상황 추적
- [ ] 검증 완료
- [ ] 리포트 생성

완료 후:

- [ ] 비용 확인 (AWS Cost Explorer)
- [ ] 데이터 무결성 검증
- [ ] 문서화
- [ ] Source 데이터 정리 (선택)

---

이제 원하는 시나리오를 선택해서 진행하세요! 🎯
