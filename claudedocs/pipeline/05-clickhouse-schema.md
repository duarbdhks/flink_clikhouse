# ClickHouse 스키마 설계

## 📋 개요
실시간 주문 데이터 분석을 위한 ClickHouse 데이터베이스 및 테이블 스키마 설계

## 🎯 설계 목표
- **실시간 대시보드**: 주문 현황, 매출 통계
- **비즈니스 분석**: 상품별, 고객별, 시간대별 분석
- **예측 분석**: 트렌드 및 매출 예측

## 🏗️ 데이터베이스 구조
```
order_analytics (Database)
├── orders_realtime (Main Table)
├── orders_daily_summary (Aggregated View)
├── orders_hourly_stats (Materialized View)
└── user_purchase_history (Aggregated View)
```

## 📊 테이블 설계

### 1. orders_realtime (메인 테이블)

#### 테이블 생성 DDL
```sql
CREATE DATABASE IF NOT EXISTS order_analytics;

USE order_analytics;

CREATE TABLE IF NOT EXISTS orders_realtime (
    order_id UInt64,
    user_id UInt64,
    status LowCardinality(String),
    total_amount Decimal(10, 2),
    order_date DateTime,
    updated_at DateTime,
    operation_type LowCardinality(String),  -- INSERT, UPDATE, DELETE
    event_timestamp UInt64,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(event_timestamp)
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_id, event_timestamp)
SETTINGS index_granularity = 8192;

-- order_items_realtime 테이블 (주문 항목)
CREATE TABLE IF NOT EXISTS order_items_realtime (
    item_id UInt64,
    order_id UInt64,
    product_id UInt64,
    product_name String,
    quantity UInt32,
    price Decimal(10, 2),
    subtotal Decimal(10, 2),
    created_at DateTime,
    operation_type LowCardinality(String),
    event_timestamp UInt64,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(event_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (item_id, event_timestamp)
SETTINGS index_granularity = 8192;
```

#### 테이블 설계 설명

**Engine: ReplacingMergeTree**
- **목적**: 중복 제거 (같은 order_id의 최신 이벤트만 유지)
- **버전 컬럼**: `event_timestamp` (높은 값이 최신)
- **동작**: OPTIMIZE TABLE 실행 시 중복 제거

**Partition: toYYYYMM(order_date)**
- **월별 파티션**: 2025-01, 2025-02, ...
- **이점**: 오래된 데이터 삭제 용이 (`ALTER TABLE DROP PARTITION`)
- **쿼리 최적화**: 특정 월 쿼리 시 해당 파티션만 스캔

**컬럼 구성**:
- `order_id`: 주문 고유 ID
- `user_id`: 사용자 ID (users 테이블 참조)
- `status`: 주문 상태 (PENDING, PROCESSING, COMPLETED, CANCELLED)
- `total_amount`: 총 주문 금액
- `order_date`: 주문 생성 일시
- `updated_at`: 마지막 수정 일시

**Order By: (order_id, event_timestamp)**
- **Primary Key**: (order_id, event_timestamp)
- **정렬 순서**: order_id 오름차순 → event_timestamp 오름차순
- **쿼리 최적화**: order_id 기반 조회 성능 향상

**컬럼 타입 최적화**
- **LowCardinality(String)**: status, operation_type (카디널리티 낮음)
- **UInt64**: order_id, user_id (음수 불필요)
- **Decimal(10, 2)**: 정확한 금액 계산

### 2. orders_daily_summary (일별 집계 뷰)

```sql
CREATE MATERIALIZED VIEW orders_daily_summary
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_date, status)
AS
SELECT
    toDate(order_date) AS date,
    status,
    count() AS order_count,
    sum(total_amount) AS daily_revenue,
    avg(total_amount) AS avg_order_value,
    uniq(user_id) AS unique_customers
FROM orders_realtime
WHERE operation_type != 'DELETE'
GROUP BY date, status;
```

**특징**:
- **자동 집계**: orders_realtime에 데이터 INSERT 시 자동 업데이트
- **SummingMergeTree**: 동일 키의 숫자 컬럼 자동 합산
- **쿼리 성능**: 일별 통계 쿼리 시 원본 테이블 대비 10-100배 빠름

### 3. orders_hourly_stats (시간대별 통계)

```sql
CREATE MATERIALIZED VIEW orders_hourly_stats
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(order_hour)
ORDER BY (order_hour, status)
AS
SELECT
    toStartOfHour(order_date) AS order_hour,
    status,
    countState() AS order_count,
    sumState(total_amount) AS hourly_revenue,
    avgState(total_amount) AS avg_order_value,
    uniqState(user_id) AS unique_customers
FROM orders_realtime
WHERE operation_type != 'DELETE'
GROUP BY order_hour, status;
```

**AggregatingMergeTree 사용**:
- **State 함수**: countState(), sumState() 사용
- **Merge 함수**: 쿼리 시 countMerge(), sumMerge() 사용
- **증분 집계**: 효율적인 실시간 집계

**쿼리 예시**:
```sql
SELECT
    order_hour,
    status,
    countMerge(order_count) AS total_orders,
    sumMerge(hourly_revenue) AS revenue
FROM orders_hourly_stats
WHERE order_hour >= now() - INTERVAL 24 HOUR
GROUP BY order_hour, status
ORDER BY order_hour DESC;
```

### 4. user_purchase_history (사용자별 구매 이력)

```sql
CREATE MATERIALIZED VIEW user_purchase_history
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(last_order_date)
ORDER BY user_id
AS
SELECT
    user_id,
    maxState(order_date) AS last_order_date,
    countState() AS total_orders,
    sumState(total_amount) AS lifetime_value,
    avgState(total_amount) AS avg_order_value
FROM orders_realtime
WHERE operation_type != 'DELETE'
GROUP BY user_id;
```

**쿼리 예시**:
```sql
SELECT
    user_id,
    maxMerge(last_order_date) AS last_order,
    countMerge(total_orders) AS orders,
    sumMerge(lifetime_value) AS ltv,
    avgMerge(avg_order_value) AS aov
FROM user_purchase_history
WHERE user_id = 500;
```

## 🔍 실시간 대시보드 쿼리

### 1. 실시간 주문 현황 (최근 10분)
```sql
SELECT
    toStartOfMinute(order_date) AS minute,
    status,
    count() AS order_count,
    sum(total_amount) AS revenue
FROM orders_realtime
WHERE order_date >= now() - INTERVAL 10 MINUTE
  AND operation_type != 'DELETE'
GROUP BY minute, status
ORDER BY minute DESC, status;
```

### 2. 오늘 매출 통계
```sql
SELECT
    count() AS total_orders,
    sum(total_amount) AS total_revenue,
    avg(total_amount) AS avg_order_value,
    uniq(user_id) AS unique_customers
FROM orders_realtime
WHERE toDate(order_date) = today()
  AND operation_type != 'DELETE';
```

### 3. 상위 10개 상품 (매출 기준) - order_items 테이블 사용
```sql
SELECT
    product_name,
    count() AS order_count,
    sum(quantity) AS total_quantity,
    sum(subtotal) AS revenue,
    avg(price) AS avg_price
FROM order_items_realtime
WHERE toDate(created_at) = today()
  AND operation_type != 'DELETE'
GROUP BY product_name
ORDER BY revenue DESC
LIMIT 10;
```

### 4. 시간대별 주문 패턴 (오늘)
```sql
SELECT
    toHour(order_date) AS hour,
    count() AS order_count,
    sum(total_amount) AS revenue
FROM orders_realtime
WHERE toDate(order_date) = today()
  AND operation_type != 'DELETE'
GROUP BY hour
ORDER BY hour;
```

### 5. 주문 상태별 분포
```sql
SELECT
    status,
    count() AS order_count,
    sum(total_amount) AS revenue,
    (count() * 100.0 / (SELECT count() FROM orders_realtime WHERE toDate(order_date) = today())) AS percentage
FROM orders_realtime
WHERE toDate(order_date) = today()
  AND operation_type != 'DELETE'
GROUP BY status
ORDER BY order_count DESC;
```

## 📈 비즈니스 분석 쿼리

### 1. 월별 매출 트렌드
```sql
SELECT
    toStartOfMonth(order_date) AS month,
    count() AS orders,
    sum(total_amount) AS revenue,
    avg(total_amount) AS aov
FROM orders_realtime
WHERE order_date >= now() - INTERVAL 6 MONTH
  AND operation_type != 'DELETE'
GROUP BY month
ORDER BY month DESC;
```

### 2. 주별 성장률
```sql
WITH weekly_data AS (
    SELECT
        toMonday(order_date) AS week,
        sum(total_amount) AS revenue
    FROM orders_realtime
    WHERE order_date >= now() - INTERVAL 12 WEEK
      AND operation_type != 'DELETE'
    GROUP BY week
)
SELECT
    week,
    revenue,
    lagInFrame(revenue, 1) OVER (ORDER BY week) AS prev_week_revenue,
    ((revenue - lagInFrame(revenue, 1) OVER (ORDER BY week)) / lagInFrame(revenue, 1) OVER (ORDER BY week)) * 100 AS growth_rate
FROM weekly_data
ORDER BY week DESC;
```

### 3. 고객 세그먼트 분석 (RFM)
```sql
SELECT
    CASE
        WHEN days_since_last_order <= 7 THEN 'Hot'
        WHEN days_since_last_order <= 30 THEN 'Warm'
        WHEN days_since_last_order <= 90 THEN 'Cold'
        ELSE 'Churned'
    END AS segment,
    count() AS customer_count,
    avg(lifetime_value) AS avg_ltv,
    avg(total_orders) AS avg_orders
FROM (
    SELECT
        user_id,
        dateDiff('day', max(order_date), today()) AS days_since_last_order,
        count() AS total_orders,
        sum(total_amount) AS lifetime_value
    FROM orders_realtime
    WHERE operation_type != 'DELETE'
    GROUP BY user_id
)
GROUP BY segment
ORDER BY avg_ltv DESC;
```

### 4. 상품 재구매율 - order_items 테이블 사용
```sql
SELECT
    product_name,
    count(DISTINCT oi.user_id) AS total_customers,
    countIf(order_count > 1) AS repeat_customers,
    (countIf(order_count > 1) * 100.0 / count(DISTINCT oi.user_id)) AS repeat_rate
FROM (
    SELECT
        oi.product_name,
        o.user_id,
        count() AS order_count
    FROM order_items_realtime oi
    JOIN orders_realtime o ON oi.order_id = o.order_id
    WHERE oi.operation_type != 'DELETE' AND o.operation_type != 'DELETE'
    GROUP BY oi.product_name, o.user_id
) AS subquery
GROUP BY product_name
HAVING total_customers >= 10
ORDER BY repeat_rate DESC
LIMIT 20;
```

## 🎯 예측 분석 쿼리

### 1. 선형 회귀를 이용한 매출 예측
```sql
WITH daily_revenue AS (
    SELECT
        toDate(order_date) AS date,
        sum(total_amount) AS revenue
    FROM orders_realtime
    WHERE order_date >= now() - INTERVAL 30 DAY
      AND operation_type != 'DELETE'
    GROUP BY date
)
SELECT
    date,
    revenue AS actual_revenue,
    simpleLinearRegression(toUInt32(date), revenue) OVER (ORDER BY date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS predicted_revenue
FROM daily_revenue
ORDER BY date DESC;
```

### 2. 주문량 이동 평균 (7일)
```sql
SELECT
    toDate(order_date) AS date,
    count() AS daily_orders,
    avg(count()) OVER (ORDER BY toDate(order_date) ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS moving_avg_7days
FROM orders_realtime
WHERE order_date >= now() - INTERVAL 30 DAY
  AND operation_type != 'DELETE'
GROUP BY date
ORDER BY date DESC;
```

## 🔧 테이블 관리

### 데이터 중복 제거 (ReplacingMergeTree)
```sql
-- 강제로 중복 제거 실행
OPTIMIZE TABLE orders_realtime FINAL;

-- 최신 레코드만 조회 (자동 중복 제거)
SELECT *
FROM orders_realtime FINAL
WHERE order_id = 1001;
```

### 파티션 관리
```sql
-- 파티션 목록 확인
SELECT
    partition,
    name,
    rows,
    bytes_on_disk
FROM system.parts
WHERE table = 'orders_realtime'
  AND active = 1
ORDER BY partition DESC;

-- 오래된 파티션 삭제 (6개월 이전)
ALTER TABLE orders_realtime
DROP PARTITION '202406';
```

### 테이블 통계 확인
```sql
-- 테이블 크기 및 레코드 수
SELECT
    table,
    formatReadableSize(sum(bytes_on_disk)) AS size,
    sum(rows) AS rows,
    count() AS parts
FROM system.parts
WHERE database = 'order_analytics'
  AND active = 1
GROUP BY table
ORDER BY sum(bytes_on_disk) DESC;
```

## 🧪 테스트 쿼리

### 1. 샘플 데이터 삽입
```sql
-- orders 테이블
INSERT INTO orders_realtime
(order_id, user_id, status, total_amount, order_date, updated_at, operation_type, event_timestamp)
VALUES
    (1001, 101, 'PENDING', 1500.00, now(), now(), 'INSERT', toUnixTimestamp(now())),
    (1002, 102, 'COMPLETED', 50.00, now(), now(), 'INSERT', toUnixTimestamp(now())),
    (1003, 103, 'PENDING', 80.00, now(), now(), 'INSERT', toUnixTimestamp(now()));

-- order_items 테이블
INSERT INTO order_items_realtime
(item_id, order_id, product_id, product_name, quantity, price, subtotal, created_at, operation_type, event_timestamp)
VALUES
    (1, 1001, 1001, 'Laptop', 1, 1500.00, 1500.00, now(), 'INSERT', toUnixTimestamp(now())),
    (2, 1002, 1002, 'Mouse', 2, 25.00, 50.00, now(), 'INSERT', toUnixTimestamp(now())),
    (3, 1003, 1003, 'Keyboard', 1, 80.00, 80.00, now(), 'INSERT', toUnixTimestamp(now()));
```

### 2. 데이터 확인
```sql
-- 전체 레코드 수
SELECT COUNT(*) FROM orders_realtime;

-- 최근 10개 주문
SELECT * FROM orders_realtime
ORDER BY created_at DESC
LIMIT 10;

-- 상태별 통계
SELECT status, COUNT(*) AS cnt
FROM orders_realtime
WHERE operation_type != 'DELETE'
GROUP BY status;
```

### 3. 성능 테스트
```sql
-- 쿼리 실행 시간 측정
EXPLAIN SYNTAX
SELECT
    toDate(created_at) AS date,
    count() AS orders,
    sum(total_price) AS revenue
FROM orders_realtime
WHERE created_at >= now() - INTERVAL 7 DAY
GROUP BY date
ORDER BY date DESC;

-- 실행 계획 확인
EXPLAIN
SELECT * FROM orders_realtime
WHERE order_id = 1001;
```

## 📊 Docker Compose 설정

```yaml
services:
  clickhouse:
    image: clickhouse/clickhouse-server:23.8
    container_name: clickhouse-server
    hostname: clickhouse
    ports:
      - "8123:8123"  # HTTP 인터페이스
      - "9000:9000"  # Native 클라이언트
    volumes:
      - clickhouse-data:/var/lib/clickhouse
      - ./init-clickhouse.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      CLICKHOUSE_DB: order_analytics
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
    networks:
      - cdc-network
    ulimits:
      nofile:
        soft: 262144
        hard: 262144

volumes:
  clickhouse-data:
    driver: local

networks:
  cdc-network:
    driver: bridge
```

## 🔍 모니터링 쿼리

### 시스템 메트릭
```sql
-- 쿼리 실행 통계
SELECT
    query_duration_ms,
    read_rows,
    read_bytes,
    result_rows,
    formatReadableSize(memory_usage) AS memory
FROM system.query_log
WHERE type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY query_duration_ms DESC
LIMIT 10;

-- 테이블별 쿼리 빈도
SELECT
    tables[1] AS table_name,
    count() AS query_count,
    avg(query_duration_ms) AS avg_duration_ms
FROM system.query_log
WHERE type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 1 HOUR
GROUP BY table_name
ORDER BY query_count DESC;
```

## 🚨 트러블슈팅

### 문제 1: 중복 데이터
```sql
-- 중복 확인
SELECT
    order_id,
    count() AS duplicates
FROM orders_realtime
GROUP BY order_id
HAVING duplicates > 1;

-- 해결: OPTIMIZE 실행
OPTIMIZE TABLE orders_realtime FINAL;
```

### 문제 2: 쿼리 성능 저하
```sql
-- 인덱스 확인
SELECT
    table,
    name,
    type,
    expr
FROM system.columns
WHERE database = 'order_analytics'
  AND table = 'orders_realtime';

-- 해결: ORDER BY 키 최적화
```

### 문제 3: 디스크 용량 부족
```sql
-- 파티션별 크기 확인
SELECT
    partition,
    formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE table = 'orders_realtime'
  AND active = 1
GROUP BY partition
ORDER BY partition DESC;

-- 해결: 오래된 파티션 삭제
ALTER TABLE orders_realtime DROP PARTITION '202401';
```

## 📚 참고 자료
- [ClickHouse 공식 문서](https://clickhouse.com/docs/en/)
- [ReplacingMergeTree 엔진](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [Materialized View 가이드](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)

## 🔍 다음 단계
- [Docker Compose 전체 구성](../infrastructure/docker-compose.yml)
- [파이프라인 E2E 테스트](../testing/pipeline-validation.md)
