-- ============================================
-- ClickHouse 초기화 스크립트 (Orders + Order Items 통합)
-- 목적: 실시간 OLAP 분석을 위한 테이블 및 Materialized Views 생성
-- ============================================

-- ============================================
-- 데이터베이스 하드 삭제 및 재생성
-- ============================================

-- 기존 데이터베이스 완전 삭제
DROP DATABASE IF EXISTS order_analytics;

-- 데이터베이스 생성
CREATE DATABASE order_analytics;

USE order_analytics;

-- ============================================
-- 메인 테이블 1: orders_realtime
-- 엔진: ReplacingMergeTree (중복 제거 지원)
-- ============================================

CREATE TABLE IF NOT EXISTS orders_realtime (
  id             UInt64 COMMENT '주문 ID',
  user_id        UInt64 COMMENT '사용자 ID',
  status         LowCardinality(String) COMMENT '주문 상태 (PENDING/PROCESSING/COMPLETED/CANCELLED)',
  total_amount   Decimal(10, 2) COMMENT '총 주문 금액',
  created_at     DateTime64(3) COMMENT '주문 생성 일시 (밀리초 정밀도)',
  updated_at     DateTime64(3) COMMENT '마지막 수정 일시 (밀리초 정밀도)',
  deleted_at     Nullable(DateTime64(3)) COMMENT 'Soft Delete 일시 (NULL=활성)',
  cdc_op         LowCardinality(String) COMMENT 'CDC 작업 타입 (c=create, u=update, d=delete)',
  cdc_ts_ms      UInt64 COMMENT 'CDC 타임스탬프 (밀리초) - 버전 관리용'
)
  ENGINE = ReplacingMergeTree(cdc_ts_ms) PARTITION BY toYYYYMM(created_at)
    ORDER BY (id)
    SETTINGS index_granularity = 8192
    COMMENT '실시간 주문 데이터 (CDC 동기화) - id 기반 중복 제거, cdc_ts_ms 버전 관리';

-- ============================================
-- 메인 테이블 2: order_items_realtime
-- 엔진: ReplacingMergeTree (중복 제거 지원)
-- ============================================

CREATE TABLE IF NOT EXISTS order_items_realtime (
  id             UInt64 COMMENT '주문 항목 ID',
  order_id       UInt64 COMMENT '주문 ID (orders.id 참조)',
  product_id     UInt64 COMMENT '상품 ID',
  product_name   String COMMENT '상품명',
  quantity       UInt32 COMMENT '주문 수량',
  price          Decimal(10, 2) COMMENT '단가',
  subtotal       Decimal(10, 2) COMMENT '소계 (quantity * price)',
  created_at     DateTime64(3) COMMENT '생성 일시 (밀리초 정밀도)',
  updated_at     DateTime64(3) COMMENT '수정 일시 (밀리초 정밀도)',
  deleted_at     Nullable(DateTime64(3)) COMMENT 'Soft Delete 일시 (NULL=활성)',
  cdc_op         LowCardinality(String) COMMENT 'CDC 작업 타입',
  cdc_ts_ms      UInt64 COMMENT 'CDC 타임스탬프 (밀리초) - 버전 관리용'
)
  ENGINE = ReplacingMergeTree(cdc_ts_ms) PARTITION BY toYYYYMM(created_at)
    ORDER BY (id)
    SETTINGS index_granularity = 8192
    COMMENT '실시간 주문 항목 데이터 - id 기반 중복 제거, cdc_ts_ms 버전 관리';

-- ============================================
-- Materialized View 1: 상품 일별 통계
-- 엔진: SummingMergeTree (자동 합산)
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS product_daily_stats (
  sale_date        Date COMMENT '판매 날짜',
  product_id       UInt64 COMMENT '상품 ID',
  product_name     String COMMENT '상품명',
  order_count      UInt32 COMMENT '주문 건수',
  total_quantity   UInt64 COMMENT '총 판매 수량',
  total_revenue    Decimal(18, 2) COMMENT '총 매출',
  avg_price        Decimal(10, 2) COMMENT '평균 단가',
  unique_customers UInt32 COMMENT '구매 고객 수',
  updated_at       DateTime DEFAULT now()
)
  ENGINE = SummingMergeTree((order_count, total_quantity, total_revenue, unique_customers)) PARTITION BY toYYYYMM(sale_date)
    ORDER BY (sale_date, product_id)
    SETTINGS index_granularity = 8192
    COMMENT '상품별 일별 판매 통계';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_product_daily_stats
  TO product_daily_stats
AS
SELECT toDate(oi.created_at)       AS sale_date,
       oi.product_id,
       any(oi.product_name)        AS product_name,
       count(DISTINCT oi.order_id) AS order_count,
       sum(oi.quantity)            AS total_quantity,
       sum(oi.subtotal)            AS total_revenue,
       avg(oi.price)               AS avg_price,
       uniq(o.user_id)             AS unique_customers,
       now()                       AS updated_at
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
WHERE oi.cdc_op != 'd'
  AND o.cdc_op != 'd'
  AND oi.deleted_at IS NULL
  AND o.deleted_at IS NULL
  AND o.status != 'CANCELLED'
GROUP BY sale_date, oi.product_id;

-- ============================================
-- Materialized View 2: 고객 세그먼트 분석
-- 엔진: ReplacingMergeTree
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS customer_segments (
  user_id             UInt64 COMMENT '사용자 ID',
  last_created_at     DateTime COMMENT '최근 주문 생성 일시',
  total_orders        UInt32 COMMENT '총 주문 건수',
  total_spent         Decimal(18, 2) COMMENT '총 구매 금액 (LTV)',
  avg_order_value     Decimal(10, 2) COMMENT '평균 주문 금액',
  unique_products     UInt32 COMMENT '구매한 고유 상품 수',
  total_items         UInt64 COMMENT '총 구매 상품 개수',
  avg_items_per_order Decimal(10, 2) COMMENT '주문당 평균 상품 수',
  completed_orders    UInt32 COMMENT '완료된 주문 수',
  cancelled_orders    UInt32 COMMENT '취소된 주문 수',
  updated_at          DateTime DEFAULT now()
)
  ENGINE = ReplacingMergeTree(updated_at)
    ORDER BY user_id SETTINGS index_granularity = 8192
    COMMENT '고객별 구매 세그먼트';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_customer_segments
  TO customer_segments
AS
SELECT o.user_id,
       max(o.created_at)                       AS last_created_at,
       count(DISTINCT o.id)                    AS total_orders,
       sum(o.total_amount)                     AS total_spent,
       avg(o.total_amount)                     AS avg_order_value,
       uniq(oi.product_id)                     AS unique_products,
       sum(oi.quantity)                        AS total_items,
       sum(oi.quantity) / count(DISTINCT o.id) AS avg_items_per_order,
       countIf(o.status = 'COMPLETED')         AS completed_orders,
       countIf(o.status = 'CANCELLED')         AS cancelled_orders,
       now()                                   AS updated_at
FROM orders_realtime o
LEFT JOIN order_items_realtime oi ON o.id = oi.order_id AND oi.deleted_at IS NULL
WHERE o.cdc_op != 'd'
  AND o.deleted_at IS NULL
GROUP BY o.user_id;

-- ============================================
-- Materialized View 3: 시간별 상품 매출
-- 엔진: AggregatingMergeTree (집계 함수 지원)
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS hourly_sales_by_product (
  hour_timestamp DateTime COMMENT '시간 단위 (YYYY-MM-DD HH:00:00)',
  product_id     UInt64 COMMENT '상품 ID',
  product_name   String COMMENT '상품명',
  order_count    AggregateFunction(count, UInt64) COMMENT '주문 건수',
  total_quantity AggregateFunction(sum, UInt32) COMMENT '판매 수량',
  total_revenue  AggregateFunction(sum, Decimal(18, 2)) COMMENT '총 매출',
  avg_price      AggregateFunction(avg, Decimal(10, 2)) COMMENT '평균 단가'
)
  ENGINE = AggregatingMergeTree() PARTITION BY toYYYYMM(hour_timestamp)
    ORDER BY (hour_timestamp, product_id)
    SETTINGS index_granularity = 8192
    COMMENT '시간별 상품 판매 통계';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_hourly_sales_by_product
  TO hourly_sales_by_product
AS
SELECT toStartOfHour(oi.created_at)     AS hour_timestamp,
       oi.product_id,
       any(oi.product_name)             AS product_name,
       countState(DISTINCT oi.order_id) AS order_count,
       sumState(oi.quantity)            AS total_quantity,
       sumState(oi.subtotal)            AS total_revenue,
       avgState(oi.price)               AS avg_price
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
WHERE oi.cdc_op != 'd'
  AND oi.deleted_at IS NULL
  AND o.deleted_at IS NULL
  AND o.status != 'CANCELLED'
GROUP BY hour_timestamp, oi.product_id;

-- ============================================
-- Materialized View 4: 장바구니 분석
-- 엔진: ReplacingMergeTree
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS cart_analytics (
  created_at          Date COMMENT '주문 생성 날짜',
  avg_items_per_order Decimal(10, 2) COMMENT '주문당 평균 상품 수',
  avg_order_value     Decimal(10, 2) COMMENT '평균 주문 금액',
  avg_item_price      Decimal(10, 2) COMMENT '평균 상품 단가',
  total_orders        UInt32 COMMENT '총 주문 수',
  completed_orders    UInt32 COMMENT '완료된 주문 수',
  completion_rate     Decimal(5, 2) COMMENT '주문 완료율 (%)',
  updated_at          DateTime DEFAULT now()
)
  ENGINE = ReplacingMergeTree(updated_at) PARTITION BY toYYYYMM(created_at)
    ORDER BY created_at SETTINGS index_granularity = 8192
    COMMENT '장바구니 및 주문 완료율 분석';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_cart_analytics
  TO cart_analytics
AS
SELECT toDate(o.created_at)                                             AS created_at,
       avg(item_counts.item_count)                                      AS avg_items_per_order,
       avg(o.total_amount)                                              AS avg_order_value,
       avg(oi.price)                                                    AS avg_item_price,
       count(DISTINCT o.id)                                             AS total_orders,
       countIf(o.status = 'COMPLETED')                                  AS completed_orders,
       (countIf(o.status = 'COMPLETED') * 100.0 / count(DISTINCT o.id)) AS completion_rate,
       now()                                                            AS updated_at
FROM orders_realtime o
LEFT JOIN order_items_realtime oi ON o.id = oi.order_id AND oi.deleted_at IS NULL
LEFT JOIN (SELECT order_id, count() AS item_count
           FROM order_items_realtime
           WHERE cdc_op != 'd'
             AND deleted_at IS NULL
           GROUP BY order_id) AS item_counts ON o.id = item_counts.order_id
WHERE o.cdc_op != 'd'
  AND o.deleted_at IS NULL
GROUP BY created_at;

-- ============================================
-- 샘플 쿼리 (테스트 및 검증용)
-- ============================================

-- 1. 실시간 베스트셀러 (최근 1시간)
-- SELECT
--     oi.product_name,
--     count(DISTINCT oi.order_id) AS order_count,
--     sum(oi.quantity) AS quantity_sold,
--     sum(oi.subtotal) AS revenue,
--     avg(oi.price) AS avg_price
-- FROM order_items_realtime oi
-- INNER JOIN orders_realtime o ON oi.order_id = o.id
-- WHERE oi.created_at >= now() - INTERVAL 1 HOUR
--   AND oi.cdc_op != 'd'
--   AND o.status != 'CANCELLED'
-- GROUP BY oi.product_name
-- ORDER BY revenue DESC
-- LIMIT 10;

-- 2. 오늘 매출 KPI
-- SELECT
--     count(DISTINCT o.id) AS total_orders,
--     sum(o.total_amount) AS total_revenue,
--     avg(o.total_amount) AS avg_order_value,
--     uniq(o.user_id) AS unique_customers,
--     sum(oi.quantity) AS total_items_sold,
--     uniq(oi.product_id) AS unique_products_sold,
--     (countIf(o.status = 'COMPLETED') * 100.0 / count(DISTINCT o.id)) AS completion_rate
-- FROM orders_realtime o
-- LEFT JOIN order_items_realtime oi ON o.id = oi.order_id
-- WHERE toDate(o.created_at) = today()
--   AND o.cdc_op != 'd';

-- 3. 고객 세그먼트 분류 (Hot/Warm/Cold/Churned)
-- SELECT
--     CASE
--         WHEN dateDiff('day', last_created_at, now()) <= 7 THEN 'Hot'
--         WHEN dateDiff('day', last_created_at, now()) <= 30 THEN 'Warm'
--         WHEN dateDiff('day', last_created_at, now()) <= 90 THEN 'Cold'
--         ELSE 'Churned'
--     END AS segment,
--     count() AS customer_count,
--     avg(total_spent) AS avg_ltv,
--     avg(total_orders) AS avg_orders,
--     avg(unique_products) AS avg_product_diversity
-- FROM customer_segments
-- GROUP BY segment
-- ORDER BY avg_ltv DESC;

-- 4. 시간별 상품 매출 (최근 24시간)
-- SELECT
--     hour_timestamp,
--     product_name,
--     countMerge(order_count) AS orders,
--     sumMerge(total_quantity) AS quantity,
--     sumMerge(total_revenue) AS revenue
-- FROM hourly_sales_by_product
-- WHERE hour_timestamp >= now() - INTERVAL 24 HOUR
-- GROUP BY hour_timestamp, product_name
-- ORDER BY hour_timestamp DESC, revenue DESC;

-- 5. 장바구니 트렌드 (최근 7일)
-- SELECT
--     created_at,
--     avg_items_per_order,
--     avg_order_value,
--     completion_rate
-- FROM cart_analytics
-- WHERE created_at >= today() - INTERVAL 7 DAY
-- ORDER BY created_at DESC;

-- ============================================
-- 테이블 정보 확인
-- ============================================

SELECT '✅ ClickHouse 초기화 완료 (Orders + Order Items 통합)' AS status;

SELECT database,
       name                            AS table_name,
       engine,
       formatReadableSize(total_bytes) AS size,
       total_rows
FROM system.tables
WHERE database = 'order_analytics'
ORDER BY name;

SELECT '📊 Materialized Views 목록' AS info;

SELECT database,
       name AS view_name,
       engine,
       as_select
FROM system.tables
WHERE database = 'order_analytics'
  AND engine LIKE '%MaterializedView%'
ORDER BY name;
