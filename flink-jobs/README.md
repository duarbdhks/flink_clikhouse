# Flink Jobs - Gradle Multi-module Project

Flink CDC 및 동기화 Job을 위한 Gradle 멀티모듈 프로젝트입니다.

## 프로젝트 구조

```
flink-jobs/
├── common/              # 공통 모델 및 유틸리티
├── flink-cdc-job/       # MySQL CDC → Kafka Job
├── flink-sync-job/      # Kafka → ClickHouse Sync Job
├── build.gradle         # 루트 빌드 설정
└── settings.gradle      # 멀티모듈 설정
```

## 모듈 설명

### 1. common
- 공통 데이터 모델 (OrderEvent, CDCEvent 등)
- 유틸리티 클래스
- 설정 클래스

### 2. flink-cdc-job
- **목적**: MySQL binlog를 읽어 Kafka로 전송
- **의존성**: flink-connector-mysql-cdc, flink-connector-kafka
- **Main Class**: `com.example.flink.cdc.MySQLCDCJob`

### 3. flink-sync-job
- **목적**: Kafka 메시지를 읽어 ClickHouse로 동기화
- **의존성**: flink-connector-kafka, clickhouse-jdbc
- **Main Class**: `com.example.flink.sync.KafkaToClickHouseJob`

## 빌드 방법

### 전체 프로젝트 빌드
```bash
./gradlew build
```

### 특정 모듈 빌드
```bash
./gradlew :flink-cdc-job:build
./gradlew :flink-sync-job:build
```

### Fat JAR 생성 (향후 구현 시)
```bash
./gradlew :flink-cdc-job:buildJobJar
./gradlew :flink-sync-job:buildJobJar
```

## Job 제출 방법

### Flink CDC Job
```bash
flink run \
  --detached \
  --class com.example.flink.cdc.MySQLCDCJob \
  flink-cdc-job/build/libs/flink-cdc-job-1.0.0.jar
```

### Flink Sync Job
```bash
flink run \
  --detached \
  --class com.example.flink.sync.KafkaToClickHouseJob \
  flink-sync-job/build/libs/flink-sync-job-1.0.0.jar
```

## 개발 상태

**현재 상태**: 프로젝트 구조만 생성됨 (코드 미구현)

**다음 단계**:
1. common 모듈에 공통 모델 구현
2. flink-cdc-job 구현 (claudedocs/pipeline/02 참조)
3. flink-sync-job 구현 (claudedocs/pipeline/04 참조)
4. 단위 테스트 작성
5. Integration 테스트 작성

## 참고 문서

- `claudedocs/pipeline/02-flink-cdc-mysql.md` - CDC Job 구현 가이드
- `claudedocs/pipeline/04-flink-sync-connector.md` - Sync Job 구현 가이드
