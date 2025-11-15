# ClickHouse 스키마 설계 (Orders + Order Items 통합)

## 📋 개요
실시간 주문 및 주문 항목 데이터 분석을 위한 ClickHouse 데이터베이스 통합 스키마 설계

**데이터 소스**: MySQL CDC (orders, order_items 테이블)
**분석 목표**: 상품 분석, 고객 세그먼트, 장바구니 분석, 매출 예측

## 🎯 설계 목표

### 비즈니스 분석 영역
1. **상품 분석**: 베스트셀러, 재고 회전율, 수익성 분석
2. **고객 분석**: RFM 세그먼트, 구매 패턴, LTV 예측
3. **장바구니 분석**: 평균 상품 수, 객단가, 번들 추천
4. **시계열 분석**: 매출 트렌드, 계절성, 예측 모델
5. **실시간 대시보드**: KPI 모니터링, 알림

## 🏗️ 데이터베이스 구조

```
order_analytics (Database)
├── orders_realtime (주문 메인 테이블)
├── order_items_realtime (주문 항목 테이블)
├── product_daily_stats (상품 일별 통계)
├── customer_segments (고객 세그먼트)
├── hourly_sales_by_product (시간별 상품 매출)
└── cart_analytics (장바구니 분석)
```

---

## 📊 테이블 설계

### 1. orders_realtime (주문 메인 테이블)

#### DDL
```sql
CREATE DATABASE IF NOT EXISTS order_analytics;

USE order_analytics;

CREATE TABLE IF NOT EXISTS orders_realtime (
    id UInt64 COMMENT '주문 ID',
    user_id UInt64 COMMENT '사용자 ID',
    status LowCardinality(String) COMMENT '주문 상태 (PENDING/PROCESSING/COMPLETED/CANCELLED)',
    total_amount Decimal(10, 2) COMMENT '총 주문 금액',
    order_date DateTime COMMENT '주문 생성 일시',
    updated_at DateTime COMMENT '마지막 수정 일시',

    -- CDC 메타데이터
    cdc_op LowCardinality(String) COMMENT 'CDC 작업 타입 (c=create, u=update, d=delete)',
    cdc_ts_ms UInt64 COMMENT 'CDC 이벤트 타임스탬프 (밀리초)',
    sync_timestamp DateTime DEFAULT now() COMMENT 'ClickHouse 동기화 시각'
)
ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(order_date)
ORDER BY (id, user_id, order_date)
SETTINGS index_granularity = 8192
COMMENT '실시간 주문 데이터 (MySQL CDC 동기화)';
```

#### 설계 포인트
- **ReplacingMergeTree**: 중복 제거 (같은 order_id의 최신 레코드만 유지)
- **월별 파티션**: 오래된 데이터 삭제 용이 (`ALTER TABLE DROP PARTITION '202501'`)
- **Primary Key**: (id, user_id, order_date) → 주문 ID 기반 조회 최적화
- **LowCardinality**: status, cdc_op (카디널리티 낮은 컬럼)

---

### 2. order_items_realtime (주문 항목 테이블)

#### DDL
```sql
CREATE TABLE IF NOT EXISTS order_items_realtime (
    id UInt64 COMMENT '주문 항목 ID',
    order_id UInt64 COMMENT '주문 ID (orders.id 참조)',
    product_id UInt64 COMMENT '상품 ID',
    product_name String COMMENT '상품명',
    quantity UInt32 COMMENT '주문 수량',
    price Decimal(10, 2) COMMENT '단가',
    subtotal Decimal(10, 2) COMMENT '소계 (quantity * price)',
    created_at DateTime COMMENT '생성 일시',
    updated_at DateTime COMMENT '수정 일시',

    -- CDC 메타데이터
    cdc_op LowCardinality(String) COMMENT 'CDC 작업 타입',
    cdc_ts_ms UInt64 COMMENT 'CDC 이벤트 타임스탬프',
    sync_timestamp DateTime DEFAULT now() COMMENT 'ClickHouse 동기화 시각'
)
ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (id, order_id, product_id)
SETTINGS index_granularity = 8192
COMMENT '실시간 주문 항목 데이터';
```

#### 설계 포인트
- **order_id 인덱스**: orders 테이블 JOIN 성능 최적화
- **product_id 인덱스**: 상품별 집계 쿼리 성능 향상
- **subtotal 사전 계산**: 집계 쿼리 시 계산 부하 감소

---

## 📈 Materialized Views

### 1. product_daily_stats (상품 일별 통계)

#### 집계 테이블
```sql
CREATE TABLE IF NOT EXISTS product_daily_stats (
    sale_date Date COMMENT '판매 날짜',
    product_id UInt64 COMMENT '상품 ID',
    product_name String COMMENT '상품명',

    -- 판매 통계
    order_count UInt32 COMMENT '주문 건수',
    total_quantity UInt64 COMMENT '총 판매 수량',
    total_revenue Decimal(18, 2) COMMENT '총 매출',
    avg_price Decimal(10, 2) COMMENT '평균 단가',

    -- 고객 통계
    unique_customers UInt32 COMMENT '구매 고객 수',

    updated_at DateTime DEFAULT now()
)
ENGINE = SummingMergeTree((order_count, total_quantity, total_revenue, unique_customers))
PARTITION BY toYYYYMM(sale_date)
ORDER BY (sale_date, product_id)
SETTINGS index_granularity = 8192
COMMENT '상품별 일별 판매 통계';
```

#### Materialized View
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_product_daily_stats
TO product_daily_stats
AS
SELECT
    toDate(oi.created_at) AS sale_date,
    oi.product_id,
    any(oi.product_name) AS product_name,

    count(DISTINCT oi.order_id) AS order_count,
    sum(oi.quantity) AS total_quantity,
    sum(oi.subtotal) AS total_revenue,
    avg(oi.price) AS avg_price,

    uniq(o.user_id) AS unique_customers,

    now() AS updated_at
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
WHERE oi.cdc_op != 'd' AND o.cdc_op != 'd'
  AND o.status != 'CANCELLED'
GROUP BY sale_date, oi.product_id;
```

#### 쿼리 예시
```sql
-- 오늘 베스트셀러 Top 10
SELECT
    product_name,
    sum(total_quantity) AS quantity_sold,
    sum(total_revenue) AS revenue,
    sum(unique_customers) AS customers
FROM product_daily_stats
WHERE sale_date = today()
GROUP BY product_name
ORDER BY revenue DESC
LIMIT 10;
```

---

### 2. customer_segments (고객 세그먼트 분석)

#### 집계 테이블
```sql
CREATE TABLE IF NOT EXISTS customer_segments (
    user_id UInt64 COMMENT '사용자 ID',

    -- RFM 메트릭
    last_order_date DateTime COMMENT '최근 주문 일시',
    total_orders UInt32 COMMENT '총 주문 건수',
    total_spent Decimal(18, 2) COMMENT '총 구매 금액 (LTV)',
    avg_order_value Decimal(10, 2) COMMENT '평균 주문 금액',

    -- 상품 구매 통계
    unique_products UInt32 COMMENT '구매한 고유 상품 수',
    total_items UInt64 COMMENT '총 구매 상품 개수',
    avg_items_per_order Decimal(10, 2) COMMENT '주문당 평균 상품 수',

    -- 주문 상태 통계
    completed_orders UInt32 COMMENT '완료된 주문 수',
    cancelled_orders UInt32 COMMENT '취소된 주문 수',

    updated_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY user_id
SETTINGS index_granularity = 8192
COMMENT '고객별 구매 세그먼트';
```

#### Materialized View
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_customer_segments
TO customer_segments
AS
SELECT
    o.user_id,

    max(o.order_date) AS last_order_date,
    count(DISTINCT o.id) AS total_orders,
    sum(o.total_amount) AS total_spent,
    avg(o.total_amount) AS avg_order_value,

    uniq(oi.product_id) AS unique_products,
    sum(oi.quantity) AS total_items,
    sum(oi.quantity) / count(DISTINCT o.id) AS avg_items_per_order,

    countIf(o.status = 'COMPLETED') AS completed_orders,
    countIf(o.status = 'CANCELLED') AS cancelled_orders,

    now() AS updated_at
FROM orders_realtime o
LEFT JOIN order_items_realtime oi ON o.id = oi.order_id
WHERE o.cdc_op != 'd'
GROUP BY o.user_id;
```

#### 쿼리 예시 (RFM 세그먼트)
```sql
-- 고객 세그먼트 분류 (Hot/Warm/Cold/Churned)
SELECT
    CASE
        WHEN dateDiff('day', last_order_date, now()) <= 7 THEN 'Hot'
        WHEN dateDiff('day', last_order_date, now()) <= 30 THEN 'Warm'
        WHEN dateDiff('day', last_order_date, now()) <= 90 THEN 'Cold'
        ELSE 'Churned'
    END AS segment,

    count() AS customer_count,
    avg(total_spent) AS avg_ltv,
    avg(total_orders) AS avg_orders,
    avg(unique_products) AS avg_product_diversity
FROM customer_segments
GROUP BY segment
ORDER BY avg_ltv DESC;
```

---

### 3. hourly_sales_by_product (시간별 상품 매출)

#### 집계 테이블
```sql
CREATE TABLE IF NOT EXISTS hourly_sales_by_product (
    hour_timestamp DateTime COMMENT '시간 단위 (YYYY-MM-DD HH:00:00)',
    product_id UInt64 COMMENT '상품 ID',
    product_name String COMMENT '상품명',

    order_count AggregateFunction(count, UInt64) COMMENT '주문 건수',
    total_quantity AggregateFunction(sum, UInt64) COMMENT '판매 수량',
    total_revenue AggregateFunction(sum, Decimal(18, 2)) COMMENT '총 매출',
    avg_price AggregateFunction(avg, Decimal(10, 2)) COMMENT '평균 단가'
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(hour_timestamp)
ORDER BY (hour_timestamp, product_id)
SETTINGS index_granularity = 8192
COMMENT '시간별 상품 판매 통계';
```

#### Materialized View
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_hourly_sales_by_product
TO hourly_sales_by_product
AS
SELECT
    toStartOfHour(oi.created_at) AS hour_timestamp,
    oi.product_id,
    any(oi.product_name) AS product_name,

    countState(DISTINCT oi.order_id) AS order_count,
    sumState(oi.quantity) AS total_quantity,
    sumState(oi.subtotal) AS total_revenue,
    avgState(oi.price) AS avg_price
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
WHERE oi.cdc_op != 'd' AND o.status != 'CANCELLED'
GROUP BY hour_timestamp, oi.product_id;
```

#### 쿼리 예시
```sql
-- 최근 24시간 상품별 시간대 매출 추이
SELECT
    hour_timestamp,
    product_name,
    countMerge(order_count) AS orders,
    sumMerge(total_quantity) AS quantity,
    sumMerge(total_revenue) AS revenue
FROM hourly_sales_by_product
WHERE hour_timestamp >= now() - INTERVAL 24 HOUR
GROUP BY hour_timestamp, product_name
ORDER BY hour_timestamp DESC, revenue DESC;
```

---

### 4. cart_analytics (장바구니 분석)

#### 집계 테이블
```sql
CREATE TABLE IF NOT EXISTS cart_analytics (
    order_date Date COMMENT '주문 날짜',

    -- 장바구니 통계
    avg_items_per_order Decimal(10, 2) COMMENT '주문당 평균 상품 수',
    avg_order_value Decimal(10, 2) COMMENT '평균 주문 금액',
    avg_item_price Decimal(10, 2) COMMENT '평균 상품 단가',

    -- 주문 완료율
    total_orders UInt32 COMMENT '총 주문 수',
    completed_orders UInt32 COMMENT '완료된 주문 수',
    completion_rate Decimal(5, 2) COMMENT '주문 완료율 (%)',

    updated_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(order_date)
ORDER BY order_date
SETTINGS index_granularity = 8192
COMMENT '장바구니 및 주문 완료율 분석';
```

#### Materialized View
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_cart_analytics
TO cart_analytics
AS
SELECT
    toDate(o.order_date) AS order_date,

    avg(item_counts.item_count) AS avg_items_per_order,
    avg(o.total_amount) AS avg_order_value,
    avg(oi.price) AS avg_item_price,

    count(DISTINCT o.id) AS total_orders,
    countIf(o.status = 'COMPLETED') AS completed_orders,
    (countIf(o.status = 'COMPLETED') * 100.0 / count(DISTINCT o.id)) AS completion_rate,

    now() AS updated_at
FROM orders_realtime o
LEFT JOIN order_items_realtime oi ON o.id = oi.order_id
LEFT JOIN (
    SELECT order_id, count() AS item_count
    FROM order_items_realtime
    WHERE cdc_op != 'd'
    GROUP BY order_id
) AS item_counts ON o.id = item_counts.order_id
WHERE o.cdc_op != 'd'
GROUP BY order_date;
```

#### 쿼리 예시
```sql
-- 최근 7일 장바구니 트렌드
SELECT
    order_date,
    avg_items_per_order,
    avg_order_value,
    completion_rate
FROM cart_analytics
WHERE order_date >= today() - INTERVAL 7 DAY
ORDER BY order_date DESC;
```

---

## 🔍 실시간 대시보드 쿼리

### 1. 실시간 베스트셀러 (최근 1시간)
```sql
SELECT
    oi.product_name,
    count(DISTINCT oi.order_id) AS order_count,
    sum(oi.quantity) AS quantity_sold,
    sum(oi.subtotal) AS revenue,
    avg(oi.price) AS avg_price
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
WHERE oi.created_at >= now() - INTERVAL 1 HOUR
  AND oi.cdc_op != 'd'
  AND o.status != 'CANCELLED'
GROUP BY oi.product_name
ORDER BY revenue DESC
LIMIT 10;
```

### 2. 오늘 매출 KPI
```sql
SELECT
    count(DISTINCT o.id) AS total_orders,
    sum(o.total_amount) AS total_revenue,
    avg(o.total_amount) AS avg_order_value,
    uniq(o.user_id) AS unique_customers,

    sum(oi.quantity) AS total_items_sold,
    uniq(oi.product_id) AS unique_products_sold,

    (countIf(o.status = 'COMPLETED') * 100.0 / count(DISTINCT o.id)) AS completion_rate
FROM orders_realtime o
LEFT JOIN order_items_realtime oi ON o.id = oi.order_id
WHERE toDate(o.order_date) = today()
  AND o.cdc_op != 'd';
```

### 3. 시간대별 주문 패턴 (오늘)
```sql
SELECT
    toHour(o.order_date) AS hour,
    count(DISTINCT o.id) AS order_count,
    sum(o.total_amount) AS revenue,
    avg(oi_counts.item_count) AS avg_items_per_order
FROM orders_realtime o
LEFT JOIN (
    SELECT order_id, count() AS item_count
    FROM order_items_realtime
    WHERE toDate(created_at) = today() AND cdc_op != 'd'
    GROUP BY order_id
) AS oi_counts ON o.id = oi_counts.order_id
WHERE toDate(o.order_date) = today()
  AND o.cdc_op != 'd'
GROUP BY hour
ORDER BY hour;
```

### 4. 상품 카테고리별 매출 (상품명 패턴 기반)
```sql
-- 상품명에서 카테고리 추출 (예: "Laptop Pro" → "Laptop")
SELECT
    splitByChar(' ', product_name)[1] AS category,
    count(DISTINCT order_id) AS order_count,
    sum(quantity) AS total_quantity,
    sum(subtotal) AS revenue,
    avg(price) AS avg_price
FROM order_items_realtime
WHERE toDate(created_at) = today()
  AND cdc_op != 'd'
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;
```

---

## 📊 비즈니스 분석 쿼리

### 1. 상품 재구매율 분석
```sql
SELECT
    oi.product_name,
    count(DISTINCT o.user_id) AS total_customers,

    countIf(purchase_counts.purchase_count > 1) AS repeat_customers,
    (countIf(purchase_counts.purchase_count > 1) * 100.0 / count(DISTINCT o.user_id)) AS repeat_rate,

    avg(purchase_counts.purchase_count) AS avg_purchase_frequency
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
LEFT JOIN (
    SELECT
        oi.product_id,
        o.user_id,
        count(DISTINCT o.id) AS purchase_count
    FROM order_items_realtime oi
    INNER JOIN orders_realtime o ON oi.order_id = o.id
    WHERE oi.cdc_op != 'd' AND o.cdc_op != 'd'
    GROUP BY oi.product_id, o.user_id
) AS purchase_counts ON oi.product_id = purchase_counts.product_id AND o.user_id = purchase_counts.user_id
WHERE oi.cdc_op != 'd' AND o.cdc_op != 'd'
GROUP BY oi.product_name
HAVING total_customers >= 5
ORDER BY repeat_rate DESC
LIMIT 20;
```

### 2. 함께 구매된 상품 분석 (장바구니 연관 분석)
```sql
-- 같은 주문에서 함께 구매된 상품 쌍
SELECT
    a.product_name AS product_a,
    b.product_name AS product_b,
    count(DISTINCT a.order_id) AS co_purchase_count,
    avg(a.subtotal + b.subtotal) AS avg_bundle_revenue
FROM order_items_realtime a
INNER JOIN order_items_realtime b ON a.order_id = b.order_id AND a.id < b.id
WHERE a.cdc_op != 'd' AND b.cdc_op != 'd'
  AND a.created_at >= now() - INTERVAL 30 DAY
GROUP BY product_a, product_b
HAVING co_purchase_count >= 3
ORDER BY co_purchase_count DESC
LIMIT 20;
```

### 3. 고객 LTV 예측 (코호트 분석)
```sql
WITH cohort_data AS (
    SELECT
        user_id,
        toStartOfMonth(min(order_date)) AS cohort_month,
        dateDiff('month', min(order_date), max(order_date)) AS customer_age_months,
        count(DISTINCT id) AS total_orders,
        sum(total_amount) AS total_revenue
    FROM orders_realtime
    WHERE cdc_op != 'd' AND status = 'COMPLETED'
    GROUP BY user_id
)
SELECT
    cohort_month,
    customer_age_months,
    count() AS customers_in_cohort,
    avg(total_revenue) AS avg_ltv,
    avg(total_orders) AS avg_orders
FROM cohort_data
WHERE cohort_month >= toStartOfMonth(now() - INTERVAL 6 MONTH)
GROUP BY cohort_month, customer_age_months
ORDER BY cohort_month DESC, customer_age_months ASC;
```

### 4. 매출 트렌드 및 성장률 (주별)
```sql
WITH weekly_revenue AS (
    SELECT
        toMonday(order_date) AS week_start,
        sum(total_amount) AS revenue,
        count(DISTINCT id) AS order_count
    FROM orders_realtime
    WHERE cdc_op != 'd'
      AND status = 'COMPLETED'
      AND order_date >= now() - INTERVAL 12 WEEK
    GROUP BY week_start
)
SELECT
    week_start,
    revenue,
    order_count,

    lagInFrame(revenue, 1) OVER (ORDER BY week_start) AS prev_week_revenue,
    ((revenue - lagInFrame(revenue, 1) OVER (ORDER BY week_start)) / lagInFrame(revenue, 1) OVER (ORDER BY week_start)) * 100 AS growth_rate_percent
FROM weekly_revenue
ORDER BY week_start DESC;
```

### 5. 상품 판매 속도 분석 (재고 회전율 예측)
```sql
-- 일별 평균 판매량 기반 재고 소진 예측
SELECT
    product_name,
    sum(total_quantity) AS total_sold_30d,
    sum(total_quantity) / 30.0 AS avg_daily_sales,

    -- 가상 재고 1000개 기준 소진 예상 일수
    1000 / (sum(total_quantity) / 30.0) AS days_until_stockout,

    sum(total_revenue) AS revenue_30d
FROM product_daily_stats
WHERE sale_date >= today() - INTERVAL 30 DAY
GROUP BY product_name
HAVING avg_daily_sales > 0
ORDER BY avg_daily_sales DESC
LIMIT 20;
```

---

## 🎯 예측 분석 쿼리

### 1. 선형 회귀를 이용한 매출 예측 (다음 7일)
```sql
WITH daily_revenue AS (
    SELECT
        toDate(order_date) AS date,
        sum(total_amount) AS revenue
    FROM orders_realtime
    WHERE order_date >= now() - INTERVAL 30 DAY
      AND cdc_op != 'd'
      AND status = 'COMPLETED'
    GROUP BY date
)
SELECT
    date,
    revenue AS actual_revenue,

    -- 7일 이동 평균
    avg(revenue) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS moving_avg_7d,

    -- 선형 회귀 예측
    linearRegression(toUInt32(date), revenue) OVER (ORDER BY date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS predicted_revenue
FROM daily_revenue
ORDER BY date DESC
LIMIT 30;
```

### 2. 주문량 시계열 분해 (트렌드 + 계절성)
```sql
SELECT
    toDate(order_date) AS date,
    count() AS daily_orders,

    -- 7일 이동 평균 (트렌드)
    avg(count()) OVER (ORDER BY toDate(order_date) ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS trend_7d,

    -- 요일별 계절성 (같은 요일 평균)
    avgIf(count(), toDayOfWeek(order_date) = toDayOfWeek(today())) OVER () AS seasonal_pattern
FROM orders_realtime
WHERE order_date >= now() - INTERVAL 60 DAY
  AND cdc_op != 'd'
GROUP BY date
ORDER BY date DESC;
```

---

## 🔧 테이블 관리

### 데이터 중복 제거 (ReplacingMergeTree)
```sql
-- 강제로 중복 제거 실행
OPTIMIZE TABLE orders_realtime FINAL;
OPTIMIZE TABLE order_items_realtime FINAL;

-- 최신 레코드만 조회 (자동 중복 제거)
SELECT * FROM orders_realtime FINAL WHERE id = 1001;
SELECT * FROM order_items_realtime FINAL WHERE order_id = 1001;
```

### 파티션 관리
```sql
-- 파티션 목록 확인
SELECT
    partition,
    name,
    rows,
    formatReadableSize(bytes_on_disk) AS size
FROM system.parts
WHERE database = 'order_analytics'
  AND table IN ('orders_realtime', 'order_items_realtime')
  AND active = 1
ORDER BY table, partition DESC;

-- 오래된 파티션 삭제 (6개월 이전)
ALTER TABLE orders_realtime DROP PARTITION '202406';
ALTER TABLE order_items_realtime DROP PARTITION '202406';
```

### 테이블 통계 확인
```sql
SELECT
    table,
    formatReadableSize(sum(bytes_on_disk)) AS total_size,
    formatReadableQuantity(sum(rows)) AS total_rows,
    count() AS parts_count
FROM system.parts
WHERE database = 'order_analytics'
  AND active = 1
GROUP BY table
ORDER BY sum(bytes_on_disk) DESC;
```

---

## 🧪 테스트 쿼리

### 샘플 데이터 삽입
```sql
-- orders 샘플
INSERT INTO orders_realtime
(id, user_id, status, total_amount, order_date, updated_at, cdc_op, cdc_ts_ms)
VALUES
    (1001, 101, 'COMPLETED', 1580.00, now() - INTERVAL 1 HOUR, now(), 'c', toUnixTimestamp(now()) * 1000),
    (1002, 102, 'PENDING', 75.00, now() - INTERVAL 30 MINUTE, now(), 'c', toUnixTimestamp(now()) * 1000),
    (1003, 103, 'COMPLETED', 160.00, now() - INTERVAL 15 MINUTE, now(), 'c', toUnixTimestamp(now()) * 1000);

-- order_items 샘플
INSERT INTO order_items_realtime
(id, order_id, product_id, product_name, quantity, price, subtotal, created_at, updated_at, cdc_op, cdc_ts_ms)
VALUES
    (1, 1001, 1001, 'Laptop Pro', 1, 1500.00, 1500.00, now() - INTERVAL 1 HOUR, now(), 'c', toUnixTimestamp(now()) * 1000),
    (2, 1001, 1002, 'Mouse Wireless', 2, 40.00, 80.00, now() - INTERVAL 1 HOUR, now(), 'c', toUnixTimestamp(now()) * 1000),
    (3, 1002, 1003, 'Keyboard Mechanical', 1, 75.00, 75.00, now() - INTERVAL 30 MINUTE, now(), 'c', toUnixTimestamp(now()) * 1000),
    (4, 1003, 1001, 'Laptop Pro', 1, 1500.00, 1500.00, now() - INTERVAL 15 MINUTE, now(), 'c', toUnixTimestamp(now()) * 1000),
    (5, 1003, 1004, 'USB Cable', 4, 15.00, 60.00, now() - INTERVAL 15 MINUTE, now(), 'c', toUnixTimestamp(now()) * 1000);
```

### 데이터 검증
```sql
-- 전체 레코드 수 확인
SELECT 'Orders' AS table_name, COUNT(*) AS record_count FROM orders_realtime
UNION ALL
SELECT 'Order Items', COUNT(*) FROM order_items_realtime;

-- JOIN 테스트
SELECT
    o.id AS order_id,
    o.status,
    o.total_amount,
    count(oi.id) AS item_count,
    sum(oi.subtotal) AS calculated_total
FROM orders_realtime o
LEFT JOIN order_items_realtime oi ON o.id = oi.order_id
WHERE o.cdc_op != 'd'
GROUP BY o.id, o.status, o.total_amount
ORDER BY o.id DESC
LIMIT 10;
```

---

## 📊 성능 최적화 팁

### 1. 쿼리 실행 계획 확인
```sql
EXPLAIN SYNTAX
SELECT
    oi.product_name,
    sum(oi.subtotal) AS revenue
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
WHERE toDate(oi.created_at) = today()
GROUP BY oi.product_name
ORDER BY revenue DESC;
```

### 2. 인덱스 활용 확인
```sql
-- Primary Key 활용 여부 확인
EXPLAIN indexes = 1
SELECT * FROM orders_realtime WHERE id = 1001;
```

### 3. Materialized View 갱신 모니터링
```sql
-- View 데이터 확인
SELECT
    database,
    name AS view_name,
    engine,
    total_rows
FROM system.tables
WHERE database = 'order_analytics'
  AND engine LIKE '%MaterializedView%';
```

---

## 🚨 트러블슈팅

### 문제 1: JOIN 성능 저하
```sql
-- 해결: order_id 기준 사전 집계 후 JOIN
WITH order_summary AS (
    SELECT
        order_id,
        count() AS item_count,
        sum(subtotal) AS total
    FROM order_items_realtime
    WHERE cdc_op != 'd'
    GROUP BY order_id
)
SELECT
    o.id,
    o.status,
    os.item_count,
    os.total
FROM orders_realtime o
INNER JOIN order_summary os ON o.id = os.order_id
WHERE o.cdc_op != 'd';
```

### 문제 2: Materialized View 데이터 불일치
```sql
-- 해결: View 재생성
DROP VIEW IF EXISTS mv_product_daily_stats;
CREATE MATERIALIZED VIEW mv_product_daily_stats TO product_daily_stats AS ...;

-- 기존 데이터 재계산
INSERT INTO product_daily_stats
SELECT ... FROM order_items_realtime oi INNER JOIN orders_realtime o ...;
```

---

## 🗑️ Soft Delete 처리 가이드

### 개요
**Soft Delete**는 데이터를 물리적으로 삭제하지 않고 논리적으로 삭제 표시하는 방식으로, 데이터 복구 및 감사 추적을 가능하게 합니다.

### 구현 전략

#### 1. MySQL Schema (deleted_at 컬럼)
모든 테이블에 `deleted_at` 컬럼을 추가하여 soft delete 구현:

```sql
-- orders 테이블
ALTER TABLE orders ADD COLUMN deleted_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Soft Delete 일시 (NULL=활성)';
CREATE INDEX idx_deleted_at ON orders(deleted_at);

-- order_items 테이블
ALTER TABLE order_items ADD COLUMN deleted_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Soft Delete 일시 (NULL=활성)';
CREATE INDEX idx_deleted_at ON order_items(deleted_at);

-- users, products 테이블도 동일하게 적용
```

#### 2. NestJS Entity (TypeORM DeleteDateColumn)
TypeORM의 `@DeleteDateColumn` 데코레이터를 사용하여 자동 처리:

```typescript
import { DeleteDateColumn } from 'typeorm';

@Entity('orders')
export class Order {
  // ... 기존 필드들 ...

  @ApiProperty({
    description: 'Soft Delete 일시 (NULL=활성)',
    example: null,
    required: false,
  })
  @DeleteDateColumn({ type: 'timestamp', name: 'deleted_at', nullable: true })
  deletedAt: Date | null;
}
```

**사용 방법**:
```typescript
// Soft Delete 실행
await orderRepository.softRemove(order);

// Soft Delete된 데이터 포함 조회
const orders = await orderRepository.find({ withDeleted: true });

// Soft Delete된 데이터만 조회
const deletedOrders = await orderRepository.find({
  where: { deletedAt: Not(IsNull()) }
});

// Soft Delete 복구
await orderRepository.recover(order);
```

#### 3. CDC 이벤트 처리
Debezium은 soft delete를 **UPDATE 이벤트**로 인식합니다 (deleted_at 컬럼 변경):

```json
{
  "op": "u",
  "before": {
    "id": 1001,
    "deleted_at": null
  },
  "after": {
    "id": 1001,
    "deleted_at": "2025-01-16T10:30:00Z"
  }
}
```

**주의사항**:
- Hard Delete는 `"op": "d"` 이벤트 발생
- Soft Delete는 `"op": "u"` 이벤트 발생
- 두 가지 모두 처리 필요

#### 4. ClickHouse Schema (deleted_at 필터링)
ClickHouse 테이블에 `deleted_at` 컬럼 추가 및 Materialized View 필터 적용:

```sql
-- orders_realtime 테이블
CREATE TABLE IF NOT EXISTS orders_realtime (
    -- ... 기존 필드들 ...
    deleted_at Nullable(DateTime) COMMENT 'Soft Delete 일시 (NULL=활성)',
    -- ... CDC 메타데이터 ...
)
ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(order_date)
ORDER BY (id, user_id, order_date);

-- Materialized View WHERE 절에 soft delete 필터 추가
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_product_daily_stats
TO product_daily_stats
AS
SELECT
    -- ... 집계 필드들 ...
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
WHERE oi.cdc_op != 'd'
  AND o.cdc_op != 'd'
  AND oi.deleted_at IS NULL  -- ✅ Soft Delete 필터
  AND o.deleted_at IS NULL   -- ✅ Soft Delete 필터
  AND o.status != 'CANCELLED'
GROUP BY sale_date, oi.product_id;
```

### 운영 쿼리

#### Soft Delete된 데이터 확인
```sql
-- 삭제된 주문 목록
SELECT
    id,
    user_id,
    status,
    total_amount,
    order_date,
    deleted_at
FROM orders_realtime
WHERE deleted_at IS NOT NULL
ORDER BY deleted_at DESC
LIMIT 100;

-- 삭제된 데이터 통계
SELECT
    toDate(deleted_at) AS delete_date,
    count() AS deleted_orders,
    sum(total_amount) AS lost_revenue
FROM orders_realtime
WHERE deleted_at IS NOT NULL
GROUP BY delete_date
ORDER BY delete_date DESC;
```

#### 활성 데이터만 조회
```sql
-- 활성 주문만 조회 (deleted_at IS NULL)
SELECT
    id,
    user_id,
    status,
    total_amount
FROM orders_realtime
WHERE cdc_op != 'd'
  AND deleted_at IS NULL
ORDER BY order_date DESC;
```

### Hard Delete vs Soft Delete 비교

**중요**: 두 방식 모두 **"삭제된 데이터"**를 의미하며, 통계에서 제외되어야 합니다. 차이점은 **구현 방식**과 **데이터 복구 가능성**입니다.

| 항목 | Hard Delete | Soft Delete (우리 시스템) |
|------|-------------|---------------------------|
| **의미** | 🗑️ 삭제된 데이터 | 🗑️ 삭제된 데이터 |
| **MySQL 동작** | `DELETE FROM orders WHERE id = 1001` | `UPDATE orders SET deleted_at = NOW() WHERE id = 1001` |
| **CDC 이벤트** | `"op": "d"` | `"op": "u"` (deleted_at 변경) |
| **ClickHouse 저장** | `cdc_op = 'd'` | `cdc_op = 'u'` + `deleted_at IS NOT NULL` |
| **통계 반영** | ❌ 제외 (`cdc_op != 'd'`) | ❌ 제외 (`deleted_at IS NULL`) |
| **데이터 복구** | ❌ 불가능 (binlog 백업 필요) | ✅ 가능 (`UPDATE SET deleted_at = NULL`) |
| **감사 추적** | ❌ 삭제 기록만 남음 | ✅ 삭제 시점 및 이력 유지 |
| **이력 분석** | ❌ 데이터 영구 제거 | ✅ 삭제 시점 기준 분석 가능 |
| **성능** | ✅ 디스크 절약 | ⚠️ 인덱스 필터 필요 |

### Best Practices

1. **인덱스 추가 필수**:
   ```sql
   CREATE INDEX idx_deleted_at ON orders(deleted_at);
   ```
   - 활성 데이터 조회 성능 향상

2. **Materialized View 필터 표준화** (중요):
   ```sql
   -- Hard Delete와 Soft Delete 모두 제외
   WHERE table.cdc_op != 'd'           -- Hard Delete 제외
     AND table.deleted_at IS NULL      -- Soft Delete 제외
   ```
   - **Hard Delete** (`cdc_op = 'd'`): 물리적 삭제 데이터
   - **Soft Delete** (`deleted_at IS NOT NULL`): 논리적 삭제 데이터
   - **둘 다 "삭제"**를 의미하므로 통계에서 제외

3. **통계 쿼리 표준화**:
   ```sql
   -- MySQL: 활성 데이터만 조회
   SELECT count(*) FROM orders
   WHERE deleted_at IS NULL;

   -- ClickHouse: Hard Delete와 Soft Delete 모두 제외
   SELECT count(*) FROM orders_realtime
   WHERE cdc_op != 'd'
     AND deleted_at IS NULL;
   ```

4. **복구 프로시저** (Soft Delete만 가능):
   ```sql
   -- Soft Delete 복구
   UPDATE orders
   SET deleted_at = NULL, updated_at = NOW()
   WHERE id = 1001;

   -- Hard Delete는 복구 불가능 (binlog 백업 필요)
   ```

5. **정기적인 물리 삭제** (Optional):
   ```sql
   -- 6개월 이상 soft delete된 데이터 완전 삭제
   DELETE FROM orders
   WHERE deleted_at < NOW() - INTERVAL 6 MONTH;
   ```

---

## 📚 참고 자료
- [ClickHouse 공식 문서](https://clickhouse.com/docs/en/)
- [ReplacingMergeTree 엔진](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [Materialized View 가이드](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)
- [AggregatingMergeTree 사용법](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/aggregatingmergetree)

---

## 🔍 다음 단계
- [Docker Compose 전체 구성](../infrastructure/deployment-guide.md)
- [파이프라인 E2E 테스트](../testing/pipeline-validation.md)
- [Flink Sync Job 설정](./04-flink-sync-connector.md)
