-- ============================================
-- ClickHouse 초기화 스크립트 (Orders + Order Items 통합)
-- 목적: 실시간 OLAP 분석을 위한 테이블 및 Materialized Views 생성
-- 설계 원칙:
--   1. Raw 데이터: 모든 CDC 이벤트 저장 (deleted_at 포함)
--   2. Aggregation: 전체 데이터 집계 (MV에서 deleted_at 필터링 안 함)
--   3. Query: 조회 시점에 Active View로 deleted_at 필터링
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
  unique_customers UInt32 COMMENT '구매 고객 수'
)
  ENGINE = SummingMergeTree((order_count, total_quantity, total_revenue, unique_customers)) PARTITION BY toYYYYMM(sale_date)
    ORDER BY (sale_date, product_id)
    SETTINGS index_granularity = 8192
    COMMENT '상품별 일별 판매 통계 (삭제된 데이터 포함, 조회 시 필터링 필요)';

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
       uniq(o.user_id)             AS unique_customers
FROM order_items_realtime oi
INNER JOIN orders_realtime o ON oi.order_id = o.id
WHERE oi.cdc_op != 'd'
  AND o.cdc_op != 'd'
  AND o.status != 'CANCELLED'
GROUP BY sale_date, oi.product_id;

-- ============================================
-- Materialized View 2: 고객 세그먼트 분석
-- 엔진: SummingMergeTree (수정됨)
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS customer_segments (
  user_id             UInt64 COMMENT '사용자 ID',
  total_orders        AggregateFunction(uniq, UInt64) COMMENT '총 주문 건수 (State)',
  total_spent         AggregateFunction(sum, Int64) COMMENT '총 구매 금액 센트 단위 (LTV, State)',
  total_items         AggregateFunction(sum, UInt32) COMMENT '총 구매 상품 개수 (State)',
  completed_orders    AggregateFunction(sum, UInt8) COMMENT '완료된 주문 수 (State)',
  cancelled_orders    AggregateFunction(sum, UInt8) COMMENT '취소된 주문 수 (State)'
)
  ENGINE = AggregatingMergeTree()
    ORDER BY user_id SETTINGS index_granularity = 8192
    COMMENT '고객별 구매 세그먼트 (AggregatingMergeTree - State/Merge 함수 사용)';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_customer_segments
  TO customer_segments
AS
SELECT o.user_id,
       uniqState(o.id)                                         AS total_orders,
       sumState(toInt64(o.total_amount * 100))                 AS total_spent,
       sumState(oi.quantity)                                   AS total_items,
       sumState(if(o.status = 'COMPLETED', 1, 0))              AS completed_orders,
       sumState(if(o.status = 'CANCELLED', 1, 0))              AS cancelled_orders
FROM orders_realtime o
LEFT JOIN order_items_realtime oi ON o.id = oi.order_id AND oi.cdc_op != 'd'
WHERE o.cdc_op != 'd'
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
    COMMENT '시간별 상품 판매 통계 (삭제된 데이터 포함, 조회 시 필터링 필요)';

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
  AND o.cdc_op != 'd'
  AND o.status != 'CANCELLED'
GROUP BY hour_timestamp, oi.product_id;

-- ============================================
-- Materialized View 4: 장바구니 분석
-- 엔진: SummingMergeTree (수정됨)
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS cart_analytics (
  created_at       Date COMMENT '주문 생성 날짜',
  total_orders     UInt32 COMMENT '총 주문 수',
  completed_orders UInt32 COMMENT '완료된 주문 수'
)
  ENGINE = SummingMergeTree((total_orders, completed_orders)) PARTITION BY toYYYYMM(created_at)
    ORDER BY created_at SETTINGS index_granularity = 8192
    COMMENT '장바구니 및 주문 완료율 분석 (삭제된 데이터 포함, 조회 시 필터링 필요)';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_cart_analytics
  TO cart_analytics
AS
SELECT toDate(o.created_at)             AS created_at,
       count(DISTINCT o.id)             AS total_orders,
       countIf(o.status = 'COMPLETED')  AS completed_orders
FROM orders_realtime o
WHERE o.cdc_op != 'd'
GROUP BY created_at;

-- ============================================
-- Active View 레이어 (deleted_at 필터링)
-- 목적: 삭제되지 않은 Active 데이터만 조회
-- ============================================

-- Active 주문 View
CREATE VIEW IF NOT EXISTS active_orders_realtime AS
SELECT * FROM orders_realtime
WHERE deleted_at IS NULL
  AND cdc_op != 'd';

-- Active 주문 항목 View
CREATE VIEW IF NOT EXISTS active_order_items_realtime AS
SELECT * FROM order_items_realtime
WHERE deleted_at IS NULL
  AND cdc_op != 'd';

-- Active 상품 일별 통계 View
-- 주의: MV는 deleted_at을 포함하여 집계하므로, 정확한 필터링이 필요한 경우
--      애플리케이션 레벨에서 active_order_items_realtime을 사용하여 재집계하세요
CREATE VIEW IF NOT EXISTS product_daily_stats_active AS
SELECT
  sale_date,
  product_id,
  product_name,
  order_count,
  total_quantity,
  total_revenue,
  unique_customers,
  total_revenue / total_quantity AS avg_price
FROM product_daily_stats;

-- Active 고객 세그먼트 View
CREATE VIEW IF NOT EXISTS customer_segments_active AS
SELECT
  cs.user_id,
  uniqMerge(cs.total_orders) AS total_orders,
  sumMerge(cs.total_spent) / 100.0 AS total_spent,
  sumMerge(cs.total_items) AS total_items,
  (sumMerge(cs.total_spent) / 100.0) / uniqMerge(cs.total_orders) AS avg_order_value,
  sumMerge(cs.total_items) / uniqMerge(cs.total_orders) AS avg_items_per_order,
  sumMerge(cs.completed_orders) AS completed_orders,
  sumMerge(cs.cancelled_orders) AS cancelled_orders
FROM customer_segments cs
GROUP BY cs.user_id;

-- Active 시간별 매출 View
CREATE VIEW IF NOT EXISTS hourly_sales_active AS
SELECT
  hour_timestamp,
  product_name,
  countMerge(order_count) AS orders,
  sumMerge(total_quantity) AS quantity,
  sumMerge(total_revenue) AS revenue,
  avgMerge(avg_price) AS avg_price
FROM hourly_sales_by_product
GROUP BY hour_timestamp, product_name;

-- Active 장바구니 분석 View
CREATE VIEW IF NOT EXISTS cart_analytics_active AS
SELECT
  created_at,
  total_orders,
  completed_orders,
  (completed_orders * 100.0 / total_orders) AS completion_rate
FROM cart_analytics
WHERE total_orders > 0;

-- ============================================
-- 샘플 쿼리 (테스트 및 검증용)
-- ============================================

-- 1. 실시간 베스트셀러 (최근 1시간) - Active 데이터만
-- SELECT
--     product_name,
--     orders,
--     quantity,
--     revenue
-- FROM hourly_sales_active
-- WHERE hour_timestamp >= now() - INTERVAL 1 HOUR
-- ORDER BY revenue DESC
-- LIMIT 10;

-- 2. 오늘 매출 KPI - Active 데이터만
-- SELECT
--     count(DISTINCT id) AS total_orders,
--     sum(total_amount) AS total_revenue,
--     avg(total_amount) AS avg_order_value,
--     uniq(user_id) AS unique_customers
-- FROM active_orders_realtime
-- WHERE toDate(created_at) = today();

-- 3. 고객 세그먼트 분류 - Active 데이터만
-- SELECT
--     user_id,
--     total_spent AS ltv,
--     total_orders,
--     avg_order_value,
--     avg_items_per_order
-- FROM customer_segments_active
-- ORDER BY total_spent DESC
-- LIMIT 100;

-- 4. 상품 일별 통계 - Active 데이터만
-- SELECT
--     sale_date,
--     product_name,
--     total_revenue,
--     total_quantity,
--     avg_price
-- FROM product_daily_stats_active
-- WHERE sale_date >= today() - INTERVAL 7 DAY
-- ORDER BY total_revenue DESC;

-- 5. 장바구니 트렌드 (최근 7일) - Active 데이터만
-- SELECT
--     created_at,
--     total_orders,
--     completed_orders,
--     completion_rate
-- FROM cart_analytics_active
-- WHERE created_at >= today() - INTERVAL 7 DAY
-- ORDER BY created_at DESC;

-- ============================================
-- 테이블 정보 확인
-- ============================================

SELECT '✅ ClickHouse 초기화 완료 (Orders + Order Items 통합 - Active View 레이어 추가)' AS status;

SELECT database,
       name                            AS table_name,
       engine,
       formatReadableSize(total_bytes) AS size,
       total_rows
FROM system.tables
WHERE database = 'order_analytics'
ORDER BY name;

SELECT '📊 Materialized Views 및 Active Views 목록' AS info;

SELECT database,
       name   AS view_name,
       engine,
       CASE
           WHEN engine LIKE '%MaterializedView%' THEN 'Materialized View (Raw 데이터 집계)'
           WHEN engine = 'View' THEN 'Active View (deleted_at 필터링)'
           ELSE engine
           END AS view_type
FROM system.tables
WHERE database = 'order_analytics'
  AND (engine LIKE '%MaterializedView%' OR engine = 'View')
ORDER BY engine, name;
