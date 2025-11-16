# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

MySQL 데이터를 실시간으로 ClickHouse에 동기화하는 CDC 기반 데이터 파이프라인 MVP 프로젝트입니다.

**핵심 아키텍처**: MySQL → Flink CDC → Kafka → Flink Sync → ClickHouse

## 개발 환경 설정

### 필수 요구사항
- Docker & Docker Compose (20.10.0+)
- Node.js 18+ (NestJS API 개발용)
- Java 11+ & Gradle 8+ (Flink Jobs 개발용)

### 초기 설정
```bash
# 전체 시스템 원스톱 초기화
bash docker/init/setup-all.sh

# 또는 수동 초기화
docker-compose up -d mysql clickhouse kafka
docker exec -i mysql mysql -uroot -ptest123 < docker/init/sql/init-mysql.sql
docker exec -i clickhouse clickhouse-client --multiquery < docker/init/sql/init-clickhouse.sql
bash docker/init/kafka/create-topics.sh
```

## 프로젝트 구조

### NestJS Platform Service (`platform-service/`)
주문 데이터를 관리하는 REST API 서버 (완성됨)

**주요 모듈**:
- `orders/`: 주문 생성/조회 (Orders, OrderItems 엔티티)
- `users/`: 사용자 관리
- `products/`: 상품 관리
- `database/`: TypeORM MySQL 연결 설정

**실행 명령어**:
```bash
cd platform-service
npm install
npm run start:dev      # 개발 모드 (핫 리로드)
npm run start:prod     # 프로덕션 모드
npm run lint           # ESLint 검사
npm run format         # Prettier 포맷팅
```

**API 문서**: http://localhost:3000/api/docs (Swagger)

### Flink Jobs (`flink-jobs/`)
Gradle 멀티모듈 프로젝트 (구현 완료)

**모듈 구조**:
- `common/`: 공통 유틸리티 (현재 사용 안 함)
- `flink-cdc-job/`: MySQL CDC → Kafka Job (구현 완료)
- `flink-sync-job/`: Kafka → ClickHouse Sync Job (구현 완료)

**빌드 명령어**:
```bash
cd flink-jobs
./gradlew build                              # 전체 빌드
./gradlew :flink-cdc-job:shadowJar          # CDC Job Fat JAR 생성
./gradlew :flink-sync-job:shadowJar         # Sync Job Fat JAR 생성
./gradlew test                              # 테스트 실행
```

**Job 제출**:
```bash
# CDC Job 제출
docker exec -it yeumgw-flink-jobmanager flink run -d \
  -c com.flink.cdc.job.MySQLCDCJob \
  /opt/flink/jobs/jars/flink-cdc-job.jar

# Sync Job 제출
docker exec -it yeumgw-flink-jobmanager flink run -d \
  -c com.flink.sync.job.KafkaToClickHouseJob \
  /opt/flink/jobs/jars/flink-sync-job.jar
```

## 아키텍처 핵심 개념

### CDC 파이프라인 흐름
1. **MySQL binlog → Flink CDC**: MySQL의 변경사항을 실시간 캡처 (Debezium 기반)
2. **Flink CDC → Kafka**: CDC 이벤트를 테이블별 토픽으로 라우팅
   - 토픽: `orders-cdc`, `order_items-cdc`, `users-cdc`, `products-cdc`
3. **Kafka → Flink Sync**: Kafka 메시지를 구독하여 변환
4. **Flink Sync → ClickHouse**: ClickHouse Native Sink로 실시간 삽입

### 주요 기술 선택 이유
- **Flink CDC Connector 3.0.1**: Debezium 기반으로 MySQL binlog 실시간 읽기 지원
- **ClickHouse Native Sink**: JDBC 대비 2배 빠른 성능
- **Confluent Kafka KRaft 모드**: Zookeeper 불필요, 단순한 구성
- **TypeORM + NestJS**: 타입 안전성과 빠른 API 개발

## 데이터베이스 스키마

### MySQL (`order_db`)
- `users`: 사용자 (id, name, email)
- `products`: 상품 (id, name, price, stock)
- `orders`: 주문 (id, user_id, status, total_amount)
- `order_items`: 주문 상품 (id, order_id, product_id, quantity, price)

### ClickHouse (`order_analytics`)

#### 스키마 설계 원칙
1. **Raw 데이터**: 모든 CDC 이벤트 저장 (deleted_at 포함)
2. **Aggregation**: 전체 데이터 집계 (MV에서 deleted_at 필터링 안 함)
3. **Query**: 조회 시점에 Active View로 deleted_at 필터링

#### Raw 테이블 (ReplacingMergeTree)
- `orders_realtime`: 주문 실시간 데이터
  - 엔진: `ReplacingMergeTree(cdc_ts_ms)`
  - ORDER BY: `(id)` - id 기반 중복 제거
  - 파티션: `toYYYYMM(created_at)`
  - CDC 메타데이터: `cdc_op`, `cdc_ts_ms`, `deleted_at`

- `order_items_realtime`: 주문 항목 실시간 데이터
  - 엔진: `ReplacingMergeTree(cdc_ts_ms)`
  - ORDER BY: `(id)`
  - 파티션: `toYYYYMM(created_at)`

#### 집계 테이블 (MergeTree Variants)
- `product_daily_stats`: 상품 일별 판매 통계
  - 엔진: `SummingMergeTree((order_count, total_quantity, total_revenue, unique_customers))`
  - ORDER BY: `(sale_date, product_id)`

- `customer_segments`: 고객 세그먼트 분석
  - 엔진: `AggregatingMergeTree()` (State/Merge 함수 사용)
  - ORDER BY: `(user_id)`
  - 컬럼 타입: `AggregateFunction(count|sum|countIf, ...)`

- `cart_analytics`: 장바구니 분석
  - 엔진: `SummingMergeTree((total_orders, completed_orders))`
  - ORDER BY: `(created_at)`

- `hourly_sales_by_product`: 시간별 상품 매출
  - 엔진: `AggregatingMergeTree()`
  - ORDER BY: `(hour_timestamp, product_id)`
  - 집계 함수: `countState`, `sumState`, `avgState`

#### Materialized Views
- `mv_product_daily_stats`: orders + order_items 조인하여 일별 통계 생성
- `mv_customer_segments`: 고객별 구매 패턴 집계
- `mv_hourly_sales_by_product`: 시간별 판매 데이터 집계
- `mv_cart_analytics`: 주문 완료율 분석

#### Active View 레이어 (deleted_at 필터링)
**⚠️ 중요**: 쿼리 시 반드시 `*_active` View를 사용하세요!

- `active_orders_realtime`: 삭제되지 않은 주문만 조회
- `active_order_items_realtime`: 삭제되지 않은 주문 항목만 조회
- `product_daily_stats_active`: 활성 주문 기반 상품 통계 (avg_price 계산 포함)
- `customer_segments_active`: 활성 고객 세그먼트
  - `*Merge()` 함수로 AggregateFunction 결과 추출
  - avg_order_value, avg_items_per_order 자동 계산
- `hourly_sales_active`: 시간별 판매 통계 (집계 함수 머지)
- `cart_analytics_active`: 장바구니 분석 (completion_rate 계산 포함)

**Active View가 필요한 이유**:
- MySQL에서 soft delete (UPDATE deleted_at) 시 Materialized View는 반응하지 않음
- Raw 집계 테이블에는 삭제된 데이터도 포함됨
- 쿼리 시점에 deleted_at 필터링으로 정확한 통계 제공

## 테스트 및 검증

### End-to-End 테스트
```bash
# 1. API를 통한 주문 생성
curl -X POST http://localhost:3000/api/orders \
  -H "Content-Type: application/json" \
  -d '{"userId": 100, "items": [{"productId": 1001, "productName": "Test", "quantity": 1, "price": 50.00}]}'

# 2. MySQL 확인
docker exec -it yeumgw-mysql mysql -uroot -ptest123 order_db \
  -e "SELECT * FROM orders ORDER BY id DESC LIMIT 1"

# 3. Kafka 확인 (2-3초 후)
docker exec -it yeumgw-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc --max-messages 1

# 4. ClickHouse 확인 (5초 후)
# Raw 테이블 확인 (deleted_at 포함)
docker exec -it yeumgw-clickhouse-server clickhouse-client \
  --query "SELECT * FROM order_analytics.orders_realtime ORDER BY created_at DESC LIMIT 5"

# Active View 확인 (deleted_at 필터링, 프로덕션 권장)
docker exec -it yeumgw-clickhouse-server clickhouse-client \
  --query "SELECT * FROM order_analytics.active_orders_realtime ORDER BY created_at DESC LIMIT 5"
```

### 모니터링
- **Flink Dashboard**: http://localhost:8081
- **Kafka UI**: http://localhost:8080
- **ClickHouse Play**: http://localhost:8123/play
- **API Swagger**: http://localhost:3000/api/docs

## 코드 수정 시 주의사항

### NestJS (platform-service)
- **엔티티 수정**: `*.entity.ts` 변경 시 TypeORM 자동 동기화 (`synchronize: true`)
- **DTO 검증**: `class-validator` 데코레이터로 요청 검증 필수
- **Swagger**: `@ApiProperty()` 데코레이터로 API 문서 자동 생성
- **에러 처리**: NestJS 내장 예외 사용 (`NotFoundException`, `BadRequestException`)

### Flink Jobs (Java)
- **CDC 소스 테이블 추가**: `CDCSourceConfig.java`에 테이블 목록 추가
- **토픽 라우팅**: `TableRouter.java`의 `OperationTableRouter` 구현 확인
- **ClickHouse 스키마 변경**: `ClickHouseSink.java`의 `OrdersStatementBuilder` 수정
- **설정 변경**: `application.properties`에서 DB/Kafka 연결 정보 관리

### ClickHouse (스키마 및 쿼리)
- **Raw 테이블 수정**: `init-clickhouse.sql`에서 `orders_realtime`, `order_items_realtime` 스키마 변경
- **집계 테이블 엔진**:
  - 증분 합산: `SummingMergeTree((컬럼1, 컬럼2, ...))` 사용
  - 집계 함수: `AggregatingMergeTree()` + `*State()`, `*Merge()` 함수
  - 중복 제거: `ReplacingMergeTree(버전컬럼)` 사용
- **⚠️ 쿼리 필수 규칙**: 프로덕션 쿼리는 반드시 `*_active` View 사용
  - ✅ 올바름: `SELECT * FROM active_orders_realtime`
  - ❌ 잘못됨: `SELECT * FROM orders_realtime WHERE deleted_at IS NULL`
- **Materialized View 수정**: deleted_at 필터링 제거, cdc_op != 'd' 필터만 유지

### Docker Compose
- **MySQL binlog 필수**: `--log-bin`, `--binlog-format=ROW` 설정 유지
- **포트 충돌**: 로컬 MySQL/Kafka와 충돌 시 포트 변경 (예: `13306:3306`)
- **볼륨 초기화**: 데이터 전체 삭제 시 `docker-compose down -v`

## 멱등성 보장 (Idempotency)

이 프로젝트는 **다층 멱등성 보장** 시스템을 구현하여 Flink Job 재시작 시 중복 데이터 발생을 방지합니다.

### ⚠️ 중요: Checkpoint Storage 필수 설정

**CDC Job과 Sync Job 모두 파일 기반 체크포인트 스토리지를 사용해야 합니다!**

- **CDC Job**: `MySQLCDCJob.java:112` - MySQL binlog 위치 저장
  - 이 설정 없으면 docker restart 시 binlog를 처음부터 다시 읽어 Kafka에 모든 데이터 재전송
- **Sync Job**: `KafkaToClickHouseJob.java:113` - Kafka offset 저장
  - 이 설정 없으면 Job restart 시 Kafka 메시지를 처음부터 다시 읽어 ClickHouse에 중복 삽입

```java
// 두 Job 모두 필수 설정
checkpointConfig.setCheckpointStorage("file:///tmp/flink-checkpoints");
```

**Docker 볼륨**: `./docker/volumes/flink-checkpoints:/tmp/flink-checkpoints`

### 멱등성 레이어

**Layer 1: Kafka Offset 관리**
- CDC Job: MySQL binlog 위치를 checkpoint에 저장하여 재시작 시 정확한 위치부터 재개
- Sync Job: Kafka offset을 checkpoint에 저장 (Exactly-Once)
- 파일 시스템 체크포인트 스토리지: `./docker/volumes/flink-checkpoints`
- Offset Reset Strategy: `LATEST` (재시작 시 과거 메시지 재처리 방지)

**Layer 2: 애플리케이션 레벨 필터링**
- Flink `DeduplicationFunction`: (id, cdc_ts_ms) 조합으로 중복 필터링
- State TTL 60초로 메모리 효율성 보장
- ClickHouse 삽입 전 필터링으로 불필요한 I/O 방지

**Layer 3: ClickHouse 저장소 레벨**
- **Raw 테이블**: `ReplacingMergeTree(cdc_ts_ms)` - CDC 타임스탬프 기반 버전 관리
  - `ORDER BY (id)`: id 기반 중복 그룹화 (cdc_ts_ms는 버전 선택 기준)
  - 백그라운드 머지로 비동기 중복 데이터 제거 (최신 cdc_ts_ms 유지)
- **집계 테이블**:
  - `SummingMergeTree`: 자동 합산으로 증분 데이터 집계 (`product_daily_stats`, `cart_analytics`)
  - `AggregatingMergeTree`: 집계 함수 state 저장 및 머지 (`customer_segments`, `hourly_sales_by_product`)
  - ⚠️ `AggregatingMergeTree`는 user_id별 중복 없이 정확한 증분 집계 보장
- **Active View 레이어**: 쿼리 시점 deleted_at 필터링으로 정확한 통계 제공

### 중복 데이터 검증

```bash
# 1. Raw 테이블 중복 확인 (머지 전 임시 중복 가능)
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "SELECT id, COUNT(*) as count FROM order_analytics.orders_realtime GROUP BY id HAVING count > 1"

# 2. Active View 데이터 정합성 확인
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "SELECT COUNT(*) FROM order_analytics.active_orders_realtime"

# 3. 집계 테이블 중복 확인
# SummingMergeTree (cart_analytics)
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "SELECT created_at, COUNT(*) as count FROM order_analytics.cart_analytics GROUP BY created_at HAVING count > 1"
# 예상 결과: 빈 결과 (중복 없음)

# AggregatingMergeTree (customer_segments) - user_id 중복 확인
docker exec -it yeumgw-clickhouse-server clickhouse-client --query \
  "SELECT user_id, COUNT(*) as count FROM order_analytics.customer_segments GROUP BY user_id HAVING count > 1"
# 예상 결과: 빈 결과 (user_id별 1행만 존재)

# 4. Flink 중복 제거 로그 확인
docker logs yeumgw-flink-taskmanager 2>&1 | grep "중복 이벤트 필터링"
```

**상세 가이드**: `IDEMPOTENCY_GUIDE.md` 참조

---

## 트러블슈팅

### Flink Job 실패
```bash
# Job 상태 확인
docker exec -it yeumgw-flink-jobmanager flink list

# Job 로그 확인
docker logs yeumgw-flink-taskmanager

# Job 취소 후 재시작
docker exec -it yeumgw-flink-jobmanager flink cancel <job-id>
```

### Kafka Consumer Lag
```bash
# Consumer Group 상태 확인
docker exec -it yeumgw-kafka kafka-consumer-groups \
  --describe --bootstrap-server localhost:9092 \
  --group flink-sync-connector
```

### ClickHouse 연결 실패
```bash
# ClickHouse 연결 테스트
docker exec -it yeumgw-clickhouse-server clickhouse-client --query "SELECT 1"

# 테이블 존재 확인
docker exec -it yeumgw-clickhouse-server clickhouse-client \
  --query "SHOW TABLES FROM order_analytics"
```

## 참고 문서

상세한 기술 문서는 `claudedocs/` 디렉토리 참조:
- `pipeline/01-architecture-overview.md`: 전체 아키텍처 개요
- `pipeline/02-flink-cdc-mysql.md`: Flink CDC 상세 설정
- `pipeline/03-confluent-kafka.md`: Kafka 구성
- `pipeline/04-flink-sync-connector.md`: ClickHouse 동기화
- `pipeline/05-clickhouse-schema.md`: 분석 테이블 설계
- `infrastructure/deployment-guide.md`: Docker Compose 배포
- `testing/pipeline-validation.md`: E2E 테스트 가이드
- **`IDEMPOTENCY_GUIDE.md`: 멱등성 보장 가이드 (중요!)**

## 성능 목표 (MVP)
- End-to-End 지연시간: < 5초
- 처리량: 100-1,000 TPS
- 데이터 정합성: 100%
- ClickHouse 쿼리: < 100ms
