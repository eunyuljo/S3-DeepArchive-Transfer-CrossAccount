# S3 Deep Archive Scripts

S3 Deep Archive 크로스 계정 전송을 위한 자동화 스크립트 모음입니다.

## 📁 디렉토리 구조

```
scripts/
├── README.md          ← 이 파일
│
├── basic/             ← 기본 시나리오 (학습용)
│   ├── README.md
│   ├── 01-upload-to-deep-archive.sh
│   ├── 02-restore-from-deep-archive.sh
│   ├── 02b-wait-for-restore.sh
│   ├── 03-cross-account-copy.sh
│   └── 04-cleanup.sh
│
└── advanced/          ← 고급 시나리오 (실전용)
    ├── README.md
    ├── 00-create-realistic-test-data.sh
    ├── 01-upload-selective.sh
    ├── 02-restore-selective.sh
    └── 03-copy-selective.sh
```

## 🎯 어떤 스크립트를 사용해야 할까?

### 📌 Decision Tree

```
목적이 무엇인가요?
    │
    ├─ Deep Archive 처음 사용
    │  └─> basic/ (5-10개 파일, 11MB, 무료)
    │
    ├─ 개념만 빠르게 학습
    │  └─> basic/ (20분 실습, 12시간 대기)
    │
    ├─ 대용량 데이터 처리 연습
    │  └─> advanced/ (100MB-100GB, ~$1)
    │
    ├─ 선택적 복원으로 비용 절감
    │  └─> advanced/ (연도/타입별 선택)
    │
    └─ 프로덕션 환경 준비
       └─> advanced/ (실전 시뮬레이션)
```

## 🆚 Basic vs Advanced

| 항목 | Basic | Advanced |
|------|-------|----------|
| **대상** | 초보자, 학습자 | 실무자, 대용량 처리 |
| **데이터 크기** | 11 MB (5 files) | 100MB ~ 100GB |
| **데이터 구조** | 단순 | 연도별/타입별 |
| **선택적 작업** | ❌ 전체만 | ✅ 연도/타입별 |
| **비용** | ~$0.01 | $0.04 ~ $1 |
| **실습 시간** | 20분 + 12시간 대기 | 1시간 + 12시간 대기 |
| **난이도** | ⭐ 쉬움 | ⭐⭐⭐ 중급 |
| **프로덕션** | 학습용 | 실전 가능 |

## 🚀 Quick Start

### 시작하기 전에

1. **인프라 구성 완료**
   ```bash
   cd ../source-account && terraform apply
   cd ../target-account && terraform apply
   ```

2. **AWS Profile 설정**
   ```bash
   aws configure --profile source-account
   aws configure --profile target-account
   ```

3. **스크립트 선택**
   - 처음이라면: `basic/`
   - 실전 준비라면: `advanced/`

---

## 📘 Basic Scripts - 기본 시나리오

**대상**: Deep Archive 초보자, 빠른 학습

**특징**:
- ✅ 5개의 간단한 테스트 파일
- ✅ 전체 업로드/복원/복사
- ✅ 무료에 가까운 비용
- ✅ 20분 실습

**사용법**:
```bash
cd basic/

# 1. 업로드 (~5분)
./01-upload-to-deep-archive.sh my-bucket

# 2. 복원 요청 (~1분)
./02-restore-from-deep-archive.sh my-bucket

# 3. 12시간 대기...

# 4. 복사 (~10분)
./03-cross-account-copy.sh source-bucket target-bucket

# 5. 정리
./04-cleanup.sh
```

**자세히**: `basic/README.md`

---

## 📕 Advanced Scripts - 고급 시나리오

**대상**: 대용량 데이터 처리, 비용 최적화, 실전 준비

**특징**:
- ✅ 연도별/타입별 데이터 구조
- ✅ 선택적 업로드/복원/복사
- ✅ 3가지 크기 모드 (small/medium/large)
- ✅ 진행 상황 추적
- ✅ 비용 최적화

**사용법**:

```bash
cd advanced/

# 0. 테스트 데이터 생성 (~10분)
./00-create-realistic-test-data.sh my-bucket medium

# 1. 선택적 업로드 (~30분)
./01-upload-selective.sh my-bucket 2024 backups

# 2. 선택적 복원 (~5분)
./02-restore-selective.sh my-bucket 2024 backups

# 3. 12시간 대기...
/tmp/monitor-restore-2024-backups.sh  # 상태 확인

# 4. 선택적 복사 (~50분)
./03-copy-selective.sh source-bucket target-bucket 2024 backups
```

**자세히**: `advanced/README.md`

---

## 📊 비교표

### 데이터 크기

| Mode | Basic | Advanced (small) | Advanced (medium) | Advanced (large) |
|------|-------|------------------|-------------------|------------------|
| 크기 | 11 MB | 100 MB | 10 GB | 100 GB |
| 파일수 | 5 | 60 | 240 | 600 |
| 비용 | $0.01 | $0.01 | $0.25 | $2.50 |

### 학습 내용

| 학습 목표 | Basic | Advanced |
|-----------|-------|----------|
| Deep Archive 개념 | ✅ | ✅ |
| 복원 프로세스 | ✅ | ✅ |
| 크로스 계정 권한 | ✅ | ✅ |
| 선택적 복원 | ❌ | ✅ |
| 비용 최적화 | ❌ | ✅ |
| 대용량 처리 | ❌ | ✅ |
| 진행 상황 추적 | 기본 | 상세 |
| 재시도 메커니즘 | ❌ | ✅ |

### 소요 시간

| 단계 | Basic | Advanced (medium) |
|------|-------|-------------------|
| 데이터 생성 | - | 10분 |
| 업로드 | 5분 | 30분 |
| 복원 요청 | 1분 | 5분 |
| 복원 대기 | 12시간 | 12시간 |
| 복사 | 10분 | 50분 |
| **총 작업** | 16분 | 95분 |
| **총 대기** | 12시간 | 12시간 |

## 🎓 학습 경로 추천

### 1단계: Basic으로 시작 (Day 1)
```bash
cd basic/
./01-upload-to-deep-archive.sh test-bucket-001
./02-restore-from-deep-archive.sh test-bucket-001
```
**목표**: Deep Archive 기본 개념 이해

### 2단계: Advanced Small (Day 2-3)
```bash
cd advanced/
./00-create-realistic-test-data.sh test-bucket-002 small
./01-upload-selective.sh test-bucket-002 2024 backups
./02-restore-selective.sh test-bucket-002 2024 backups
```
**목표**: 선택적 작업 학습

### 3단계: Advanced Medium (Week 2)
```bash
./00-create-realistic-test-data.sh test-bucket-003 medium
./01-upload-selective.sh test-bucket-003 2024
./02-restore-selective.sh test-bucket-003 2024
```
**목표**: 대용량 처리 연습

### 4단계: 프로덕션 준비 (Week 3)
```bash
# 실제 데이터로 테스트
./01-upload-selective.sh prod-bucket 2024 backups
```
**목표**: 실전 배포 준비

## 💡 Tips

### Basic 사용 팁

1. **빠른 검증**: 권한 설정이 올바른지 빠르게 확인
2. **학습 자료**: 팀 교육용으로 활용
3. **비용 절감**: 거의 무료로 전체 프로세스 경험

### Advanced 사용 팁

1. **점진적 확장**: small → medium → large 순서로
2. **비용 관리**: 필요한 연도/타입만 선택
3. **병렬 처리**: 여러 연도를 동시 처리
4. **모니터링**: 자동 생성된 스크립트 활용

## 🔧 문제 해결

### Basic에서 에러가 나면?

1. `basic/README.md` 확인
2. `../../docs/troubleshooting.md` 참고
3. AWS credentials 확인

### Advanced에서 에러가 나면?

1. `advanced/README.md` 확인
2. 먼저 small 크기로 테스트
3. 복원 상태 확인 스크립트 실행

## 📚 추가 문서

- **Basic 상세**: `basic/README.md`
- **Advanced 상세**: `advanced/README.md`
- **현실적 시나리오**: `../REALISTIC_SCENARIO.md`
- **비용 계산**: `../docs/cost-estimation.md`
- **문제 해결**: `../docs/troubleshooting.md`

## 🎯 시작하기

### 처음 사용하는 경우
```bash
cd basic/
cat README.md  # 먼저 읽어보기
./01-upload-to-deep-archive.sh your-bucket
```

### 실전 준비하는 경우
```bash
cd advanced/
cat README.md  # 먼저 읽어보기
./00-create-realistic-test-data.sh your-bucket small
```

---

**어떤 스크립트를 선택하셨나요?**

- 🟢 **Basic**: 처음이라면 여기서 시작! → `cd basic/`
- 🔵 **Advanced**: 실전 준비라면! → `cd advanced/`

각 디렉토리의 README.md를 확인하세요! 📖
