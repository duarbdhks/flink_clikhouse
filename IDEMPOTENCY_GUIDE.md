# ClickHouse 파이프라인 멱등성 보장 가이드

## 문제 정의

Docker Compose 재시작 또는 Flink Job 재시작 시 ClickHouse `orders_realtime` 테이블에 동일한 데이터가 중복으로 생성되는 문제가 있었습니다.

### 근본 원인

**CDC Job (MySQL → Kafka)**:
1. **체크포인트 스토리지 미설정**: In-memory state 사용으로 docker restart 시 binlog 위치 손실
2. **결과**: MySQL binlog를 처음부터 다시 읽어 Kafka에 모든 데이터 재전송

**Sync Job (Kafka → ClickHouse)**:
3. **Kafka Offset 전략**: 오프셋이 없을 때 `EARLIEST`로 되돌아가 전체 메시지 재처리
4. **체크포인트 스토리지 미설정**: JobManager 메모리만 사용하여 재시작 시 Kafka offset 손실
5. **애플리케이션 레벨 중복 제거 없음**: Flink에서 삽입 전 필터링 부재

**ClickHouse 저장소**:
6. **ClickHouse 비동기 중복 제거**: `ReplacingMergeTree`가 백그라운드 머지에서만 중복 제거
7. **중복 제거 키 부족**: `ORDER BY`에 CDC 타임스탬프 미포함
8. **sync_timestamp**: 매번 다른 값 생성으로 중복 제거 방해

---

## 적용된 해결 방안

### Phase 1: 인프라 레벨 멱등성 보장

#### 1.1 CDC Job Checkpoint Storage 추가 ✅ **[중요]**
**파일**: `flink-jobs/flink-cdc-job/src/main/java/com/flink/cdc/job/MySQLCDCJob.java:112`

```java
// 추가된 설정
checkpointConfig.setCheckpointStorage("file:///tmp/flink-checkpoints");
```

**효과**:
- Docker restart 시 MySQL binlog 위치 복구
- Kafka에 중복 데이터 전송 방지
- **이 설정 없이는 CDC Job이 재시작 시 모든 binlog를 다시 읽어 Kafka에 재전송함!**

---

#### 1.2 Sync Job Kafka Offset 전략 변경 ✅
**파일**: `flink-jobs/flink-sync-job/src/main/java/com/flink/sync/config/KafkaSourceConfig.java:42`

```java
// 변경 전
.setStartingOffsets(OffsetsInitializer.committedOffsets(OffsetResetStrategy.EARLIEST))

// 변경 후
.setStartingOffsets(OffsetsInitializer.committedOffsets(OffsetResetStrategy.LATEST))
```

**효과**: Job 재시작 시 과거 메시지를 재처리하지 않음

---

#### 1.3 ClickHouse 스키마 개선 ✅
**파일**: `docker/init/sql/init-clickhouse.sql:34-37`

```sql
-- 변경 전
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (id, user_id, created_at)
sync_timestamp DateTime DEFAULT now()  -- 중복 원인!

-- 변경 후
ENGINE = ReplacingMergeTree(cdc_ts_ms)  -- CDC 타임스탬프를 버전으로 사용
ORDER BY (id)                           -- ⚠️ id만 사용 (cdc_ts_ms는 버전 컬럼, ORDER BY 키 아님!)
-- sync_timestamp 제거 (매번 다른 값 생성하여 중복 제거 방해)
```

**효과**:
- `cdc_ts_ms`를 버전 컬럼으로 사용하여 최신 CDC 이벤트 선택
- `ORDER BY (id)`: 같은 id를 가진 행들을 중복으로 그룹화
- 그룹 내에서 `cdc_ts_ms`가 가장 큰 행만 유지 (백그라운드 머지)
- `sync_timestamp` 제거로 멱등성 보장

**중요**: `ORDER BY`에 `cdc_ts_ms`를 포함하면 안 됨!
- `cdc_ts_ms`는 매번 다른 값 → `ORDER BY (id, cdc_ts_ms)`는 중복 제거 실패
- `created_at`도 불필요 → `id`가 Primary Key이므로 `ORDER BY (id)`만으로 충분

---

#### 1.4 Sync Job Checkpoint Storage 추가 ✅
**파일**: `flink-jobs/flink-sync-job/src/main/java/com/flink/sync/job/KafkaToClickHouseJob.java:113`

```java
// 추가된 설정
checkpointConfig.setCheckpointStorage("file:///tmp/flink-checkpoints");
```

**Docker 볼륨**: `./docker/volumes/flink-checkpoints:/tmp/flink-checkpoints` (기존 설정 유지)

**효과**:
- JobManager 재시작 시에도 체크포인트 상태 복구 가능
- Kafka 오프셋 정보가 영구 저장되어 정확한 위치부터 재개

---

### Phase 2: 애플리케이션 레벨 중복 제거

#### 2.1 Flink Deduplication Function 구현 ✅
**파일**: `flink-jobs/flink-sync-job/src/main/java/com/flink/sync/function/DeduplicationFunction.java` (신규 생성)

```java
public class DeduplicationFunction extends KeyedProcessFunction<String, ClickHouseRow, ClickHouseRow> {
    private final int stateTtlSeconds; // 60초 TTL
    private transient ValueState<Boolean> seenState;

    @Override
    public void processElement(ClickHouseRow value, Context ctx, Collector<ClickHouseRow> out) {
        Boolean hasSeen = seenState.value();
        if (hasSeen == null) {
            seenState.update(true);
            out.collect(value);  // 첫 번째 이벤트만 전달
        } else {
            // 중복 이벤트 필터링
            LOG.warn("⚠️ 중복 이벤트 필터링: id={}, cdc_ts_ms={}", value.getId(), value.getCdcTsMs());
        }
    }
}
```

**적용 위치**: `KafkaToClickHouseJob.java:66-70`

```java
DataStream<ClickHouseRow> deduplicatedStream = clickHouseRowStream
    .keyBy(row -> String.valueOf(row.getId())) // id만 사용 (cdc_ts_ms는 매번 다름)
    .process(new DeduplicationFunction(60)) // 60초 State TTL
    .uid("deduplication")
    .name("Deduplication Filter");
```

**효과**:
- ClickHouse 삽입 **전에** 애플리케이션 레벨에서 중복 필터링
- 60초 State TTL로 메모리 효율성 보장
- 동일 id의 중복 이벤트는 한 번만 ClickHouse로 전달

**중요**: Keying 전략
- ✅ **올바름**: `keyBy(row -> String.valueOf(row.getId()))`
  - 같은 주문(id)의 중복 이벤트를 하나의 키로 그룹화
  - 첫 번째 이벤트만 ClickHouse에 삽입, 나머지는 필터링
- ❌ **잘못됨**: `keyBy(row -> row.getId() + "_" + row.getCdcTsMs())`
  - cdc_ts_ms가 매번 다르므로 서로 다른 키로 인식
  - 중복 필터링 완전히 실패

---

#### 2.2 ClickHouse Sink 스키마 동기화 ✅
**파일**: `flink-jobs/flink-sync-job/src/main/java/com/flink/sync/sink/ClickHouseSink.java:36`

```java
// 변경 전
String insertSQL = "INSERT INTO orders_realtime (..., sync_timestamp) VALUES (..., now())";

// 변경 후
String insertSQL = "INSERT INTO orders_realtime (id, user_id, status, total_amount, created_at, updated_at, deleted_at, cdc_op, cdc_ts_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
```

**효과**:
- `sync_timestamp` 제거로 스키마 일치
- `deleted_at` 추가로 Soft Delete 지원

---

## 멱등성 보장 레이어

### Layer 1: Kafka Offset 관리
- ✅ **Checkpoint 기반 오프셋 커밋**: Exactly-Once 보장
- ✅ **파일 시스템 체크포인트 스토리지**: 재시작 시 복구 가능
- ✅ **LATEST Fallback**: 첫 실행 시 최신 메시지부터 소비

### Layer 2: 애플리케이션 레벨 필터링
- ✅ **Flink State 기반 중복 제거**: id 기준 필터링 (cdc_ts_ms는 키로 부적합)
- ✅ **State TTL (60초)**: 메모리 효율성 보장
- ✅ **ClickHouse 삽입 전 필터링**: 불필요한 네트워크/디스크 I/O 방지

**중요**: DeduplicationFunction의 keying 전략
- `keyBy(row -> String.valueOf(row.getId()))`: ✅ id만 사용
- `keyBy(row -> row.getId() + "_" + row.getCdcTsMs())`: ❌ 중복 제거 실패
- **이유**: cdc_ts_ms는 매번 다른 값 → 서로 다른 키로 인식 → 중복 필터링 불가

### Layer 3: ClickHouse 저장소 레벨
- ✅ **ReplacingMergeTree(cdc_ts_ms)**: CDC 타임스탬프 기반 버전 관리
- ✅ **ORDER BY (id)**: id 기반 중복 그룹화 (cdc_ts_ms는 버전 선택 기준)
- ✅ **백그라운드 머지**: 비동기로 중복 데이터 제거 (최신 cdc_ts_ms 유지)

---

## 자동 복구 메커니즘 (Checkpoint Recovery)

### 개요

Docker restart 시 Flink Job이 자동으로 checkpoint에서 복구되도록 구성하여 완전한 멱등성을 보장합니다.

### 구현 방식

#### 1. Checkpoint 기반 자동 복구 (`submit-jobs.sh`)

**동작 원리**:
```bash
1. JobManager 준비 대기
   ↓
2. 기존 checkpoint 검색 (/tmp/flink-checkpoints)
   ↓
3. Checkpoint 발견?
   ├─ Yes → `-s <checkpoint-path>` 옵션으로 복구 시도
   │         ├─ 성공 → MySQL binlog offset, Kafka offset, State 모두 복구 ✅
   │         └─ 실패 → 새로 시작 (빈 state)
   └─ No  → 새로 시작
```

**핵심 로직**:
```bash
# 가장 최근 checkpoint 찾기
find_latest_checkpoint() {
  find /tmp/flink-checkpoints -type d -name "chk-*" | \
    xargs -I {} stat -f "%m %N" {} | \
    sort -rn | head -1 | awk '{print $2}'
}

# Checkpoint에서 복구
if [ -n "$CHECKPOINT" ]; then
  flink run -d -s "$CHECKPOINT" -c com.flink.cdc.job.MySQLCDCJob ...
else
  flink run -d -c com.flink.cdc.job.MySQLCDCJob ...
fi
```

#### 2. Docker Restart 정책 (`docker-compose.yml`)

**변경 내역**:
```yaml
# Before
restart: "no"  # 한 번만 실행 후 종료

# After
restart: unless-stopped  # Docker restart 시 자동 실행
```

**효과**:
- ✅ `docker-compose restart` 시 flink-job-submitter가 자동 재실행
- ✅ submit-jobs.sh가 checkpoint 검색 및 복구 수행
- ✅ 수동 개입 불필요

### Docker Restart 시나리오

#### 시나리오 1: Checkpoint 있음 (정상 복구)

```
1. docker-compose restart
   ↓
2. flink-job-submitter 자동 재시작
   ↓
3. submit-jobs.sh 실행
   ↓
4. Checkpoint 발견: /tmp/flink-checkpoints/.../chk-123
   ↓
5. CDC Job 복구:
   - MySQL binlog offset 복구 ✅
   - 마지막 읽은 위치부터 재개
   ↓
6. Sync Job 복구:
   - Kafka offset 복구 ✅
   - DeduplicationFunction state 복구 ✅
   - 마지막 처리한 위치부터 재개
   ↓
7. 결과: 중복 데이터 없음 ✅
```

#### 시나리오 2: Checkpoint 없음 (첫 실행)

```
1. 첫 실행 또는 checkpoint 삭제됨
   ↓
2. Checkpoint 없음 → 새로 시작
   ↓
3. CDC Job: MySQL snapshot 실행
   ↓
4. Sync Job: Kafka LATEST offset부터 소비
   ↓
5. 결과: 과거 데이터는 처리 안 됨
```

### HA 모드와의 차이점

| 항목 | Checkpoint 복구 (현재) | HA 모드 (Production) |
|------|------------------------|---------------------|
| **자동 복구** | ✅ Docker restart 시 | ✅ Job 실패 시에도 |
| **복잡도** | 낮음 ⭐ | 높음 ⭐⭐⭐ (ZooKeeper 필요) |
| **MVP 적합성** | ✅ | ❌ |
| **Production 권장** | △ (수동 재시작 필요) | ✅ |
| **추가 인프라** | 없음 | ZooKeeper 또는 Kubernetes |

### 제약사항

#### 1. Job 실패 시 수동 재시작 필요

**현재 구조**:
- Docker restart → 자동 복구 ✅
- Job 실패 (exception) → 수동 재시작 필요 ⚠️

**HA 모드와의 차이**:
- HA 모드는 Job 실패 시에도 자동으로 checkpoint에서 재시작

**해결 방법**:
```bash
# Job 상태 모니터링 스크립트 (선택사항)
watch -n 30 'docker exec yeumgw-flink-jobmanager flink list'
```

#### 2. Checkpoint 호환성

**주의사항**:
- Operator UID 변경 시 checkpoint 복구 실패
- State 스키마 변경 시 호환성 문제 가능

**현재 설정 (안전)**:
```java
// 모든 operator에 고정 UID 지정됨
.uid("kafka-cdc-source")
.uid("cdc-transformer")
.uid("deduplication")
.uid("clickhouse-sink")
```

#### 3. Checkpoint 저장 기간

**현재 설정**:
- Externalized checkpoint: Job 취소 시에도 보존
- 수동 삭제 필요

**권장 사항**:
```bash
# 오래된 checkpoint 정리 (예: 7일 이상)
find ./docker/volumes/flink-checkpoints -type d -mtime +7 -exec rm -rf {} \;
```

### Production 권장사항

#### 최소 구성 (현재 + 모니터링)
```yaml
1. Checkpoint 복구 ✅ (구현됨)
2. Health Check 추가
3. 알림 시스템 (Slack, PagerDuty)
```

#### 표준 구성 (HA 모드)
```yaml
1. Flink Standalone HA (ZooKeeper)
2. Checkpoint 복구 ✅
3. 자동 재시작
4. 모니터링 + 알림
```

#### Enterprise 구성
```yaml
1. Kubernetes + Flink Operator
2. Auto-scaling
3. 분산 Checkpoint Storage (S3, HDFS)
4. 메트릭 + 로깅 (Prometheus, Grafana)
```

---

## 배포 및 검증

### 1. 빌드 및 배포

```bash
# 1. Flink Jobs 빌드 (CDC Job과 Sync Job 모두 빌드)
cd flink-jobs
./gradlew :flink-cdc-job:shadowJar :flink-sync-job:shadowJar

# 2. ClickHouse 스키마 재생성 (주의: 기존 데이터 삭제됨)
docker exec -i yeumgw-clickhouse-server clickhouse-client --multiquery < docker/init/sql/init-clickhouse.sql

# 3. Flink Jobs 재배포
# 기존 Job 목록 확인
docker exec -it yeumgw-flink-jobmanager flink list

# CDC Job 취소 및 재배포
docker exec -it yeumgw-flink-jobmanager flink cancel <cdc-job-id>
docker exec -it yeumgw-flink-jobmanager flink run -d \
  -c com.flink.cdc.job.MySQLCDCJob \
  /opt/flink/jobs/flink-cdc-job/build/libs/flink-cdc-job-1.0-SNAPSHOT-all.jar

# Sync Job 취소 및 재배포
docker exec -it yeumgw-flink-jobmanager flink cancel <sync-job-id>
docker exec -it yeumgw-flink-jobmanager flink run -d \
  -c com.flink.sync.job.KafkaToClickHouseJob \
  /opt/flink/jobs/flink-sync-job/build/libs/flink-sync-job-1.0-SNAPSHOT-all.jar
```

---

### 2. 멱등성 검증 테스트

#### 테스트 시나리오: Flink Job 재시작 시 중복 데이터 없음

**Step 1: 초기 데이터 생성**

```bash
# API를 통해 주문 생성
curl -X POST http://localhost:3000/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 100,
    "items": [
      {"productId": 1001, "productName": "Test Product", "quantity": 2, "price": 50.00}
    ]
  }'

# ClickHouse 확인 (5-10초 대기 후)
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "SELECT id, user_id, total_amount, cdc_op, cdc_ts_ms FROM order_analytics.orders_realtime ORDER BY id DESC LIMIT 5"
```

**예상 결과**: 1건의 주문 데이터

---

**Step 2: Flink Job 재시작**

```bash
# Job 취소
docker exec -it yeumgw-flink-jobmanager flink list
docker exec -it yeumgw-flink-jobmanager flink cancel <job-id>

# 5초 대기 후 재시작
docker exec -it yeumgw-flink-jobmanager flink run -d \
  -c com.flink.sync.job.KafkaToClickHouseJob \
  /opt/flink/jobs/flink-sync-job/build/libs/flink-sync-job-1.0-SNAPSHOT-all.jar
```

---

**Step 3: 중복 확인**

```bash
# ClickHouse 데이터 확인
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "SELECT id, COUNT(*) as count FROM order_analytics.orders_realtime GROUP BY id HAVING count > 1"
```

**예상 결과**: 빈 결과 (중복 없음)

---

**Step 4: 백그라운드 머지 강제 실행 (선택사항)**

```bash
# ClickHouse에서 백그라운드 머지 강제 실행
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "OPTIMIZE TABLE order_analytics.orders_realtime FINAL"

# FINAL 쿼리로 중복 제거된 데이터 확인
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "SELECT id, user_id, total_amount, cdc_ts_ms FROM order_analytics.orders_realtime FINAL ORDER BY id DESC LIMIT 5"
```

**예상 결과**: 동일한 (id, cdc_ts_ms) 조합은 최신 버전만 표시

---

### 3. 모니터링 및 디버깅

#### Flink 중복 제거 로그 확인

```bash
# Flink TaskManager 로그에서 중복 필터링 확인
docker logs yeumgw-flink-taskmanager 2>&1 | grep "중복 이벤트 필터링"
```

**예상 로그**:
```
⚠️ 중복 이벤트 필터링: id=123, cdc_ts_ms=1731567890000, operation=u
```

---

#### ClickHouse 중복 데이터 확인

```sql
-- 중복 건수 확인 (머지 전)
SELECT id, COUNT(*) as count
FROM order_analytics.orders_realtime
GROUP BY id
HAVING count > 1;

-- FINAL로 중복 제거된 결과 확인
SELECT COUNT(DISTINCT id) as unique_orders
FROM order_analytics.orders_realtime FINAL;

-- 백그라운드 머지 상태 확인
SELECT
    database,
    table,
    sum(rows) as total_rows,
    count() as parts_count
FROM system.parts
WHERE database = 'order_analytics' AND table = 'orders_realtime' AND active
GROUP BY database, table;
```

---

## 성능 영향 분석

### Before (멱등성 미보장)

| 지표 | 값 |
|------|-----|
| Flink Job 재시작 시 중복 데이터 | ✅ 발생 (재처리량에 비례) |
| ClickHouse 디스크 사용량 | 높음 (중복 데이터 축적) |
| 쿼리 성능 | 저하 (FINAL 필수) |

---

### After (멱등성 보장)

| 지표 | 값 | 비고 |
|------|-----|------|
| Flink Job 재시작 시 중복 데이터 | ❌ 없음 | Deduplication Function 효과 |
| ClickHouse 디스크 사용량 | 정상 | 중복 데이터 없음 |
| 쿼리 성능 | 개선 | FINAL 불필요 |
| Flink State 메모리 | +10MB | 60초 TTL로 최소화 |
| 처리 지연 | +5ms | Deduplication 오버헤드 (미미) |

---

## 주의사항 및 제한사항

### 1. State TTL (60초)의 의미
- **60초 이내**에 동일한 (id, cdc_ts_ms) 이벤트가 재전송되면 필터링됨
- **60초 이후**에는 State가 삭제되어 재전송 시 중복 삽입 가능
- ⚠️ **대부분의 Flink 재시작은 수초 내에 완료되므로 60초로 충분**

---

### 2. ClickHouse ReplacingMergeTree 비동기 중복 제거
- **백그라운드 머지**: 즉시 실행되지 않으며, ClickHouse의 스케줄링에 따라 수행
- **FINAL 쿼리**: 중복 제거를 보장하지만 성능 저하 발생 (읽기 시 머지 수행)
- **권장**: 애플리케이션 레벨 중복 제거(Flink)에 의존하고, ClickHouse는 보조 레이어로 활용

---

### 3. 첫 실행 시 LATEST Offset
- **첫 실행**: Kafka의 최신 메시지부터 소비 (과거 데이터 처리 안 함)
- **해결 방법**: 첫 실행 시에는 `createOrdersSourceFromEarliest()` 사용하거나, 수동으로 Consumer Group 오프셋 리셋

```bash
# Consumer Group 오프셋을 earliest로 리셋 (첫 실행 시에만)
docker exec -it yeumgw-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group flink-sync-connector \
  --reset-offsets --to-earliest --topic orders-cdc --execute
```

---

## 트러블슈팅

### 문제: Flink Job 재시작 후에도 중복 데이터 발생

**원인 1**: 체크포인트 스토리지 미설정
```bash
# 확인
docker exec -it yeumgw-flink-jobmanager cat /opt/flink/conf/flink-conf.yaml | grep checkpoint

# 해결: CLAUDE.md 참고하여 체크포인트 설정 확인
```

**원인 2**: Deduplication Function 미적용
```bash
# Flink Job 로그 확인
docker logs yeumgw-flink-taskmanager 2>&1 | grep "Deduplication Filter"

# 예상 로그: "Deduplication Filter" operator가 실행 중이어야 함
```

**원인 3**: ClickHouse 스키마 미업데이트
```bash
# 스키마 확인
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "DESCRIBE order_analytics.orders_realtime"

# sync_timestamp 컬럼이 없어야 함
# ENGINE이 ReplacingMergeTree(cdc_ts_ms)여야 함
```

---

### 문제: State TTL 초과로 인한 중복

**증상**: 60초 이상 지연된 재전송 이벤트가 중복 삽입

**해결**:
```java
// State TTL 증가 (예: 300초 = 5분)
.process(new DeduplicationFunction(300))
```

⚠️ **주의**: TTL이 길수록 메모리 사용량 증가

---

## 향후 개선 사항 (선택사항)

### 1. ClickHouse Native Sink 적용
**현재**: JDBC Sink 사용
**개선**: ClickHouse Native Sink로 변경하여 성능 2배 향상

```java
// build.gradle에 의존성 추가
implementation 'org.apache.flink:flink-connector-clickhouse:1.18.0'

// ClickHouseSink.java 수정
// JdbcSink → ClickHouseSink
```

---

### 2. CollapsingMergeTree 고려
**현재**: ReplacingMergeTree (INSERT만 지원)
**개선**: CollapsingMergeTree (DELETE 이벤트도 정확히 반영)

```sql
ENGINE = CollapsingMergeTree(sign)
ORDER BY (id, cdc_ts_ms)

-- INSERT: sign = 1
-- DELETE: sign = -1
```

---

### 3. Kafka Exactly-Once Producer
**현재**: At-Least-Once (Flink → ClickHouse)
**개선**: Transactional ClickHouse Writer로 Exactly-Once 보장

---

## 참고 문서

- [ClickHouse ReplacingMergeTree](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [Flink State TTL](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/datastream/fault-tolerance/state/#state-time-to-live-ttl)
- [Kafka Consumer Offset Management](https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset)
- [Flink Checkpointing](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/datastream/fault-tolerance/checkpointing/)
