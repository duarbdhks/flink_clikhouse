-- ============================================
-- ClickHouse 초기화 스크립트
-- 목적: 실시간 OLAP 분석을 위한 테이블 및 Materialized Views 생성
-- ============================================

-- 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS order_analytics;

-- ============================================
-- 메인 테이블: orders_realtime
-- 엔진: ReplacingMergeTree (중복 제거 지원)
-- ============================================

CREATE TABLE IF NOT EXISTS order_analytics.orders_realtime (
  id             UInt64 COMMENT '주문 ID',
  user_id        UInt64 COMMENT '사용자 ID',
  status         String COMMENT '주문 상태',
  total_amount   Decimal(10, 2) COMMENT '총 주문 금액',
  order_date     DateTime COMMENT '주문 생성 일시',
  updated_at     DateTime COMMENT '마지막 수정 일시',
  cdc_op         String COMMENT 'CDC 작업 타입 (c=create, u=update, d=delete)',
  cdc_ts_ms      UInt64 COMMENT 'CDC 타임스탬프 (밀리초)',
  sync_timestamp DateTime DEFAULT now() COMMENT '동기화 타임스탬프'
)
  ENGINE = ReplacingMergeTree(updated_at) PARTITION BY toYYYYMM(order_date)
    ORDER BY (id, user_id, order_date)
    SETTINGS index_granularity = 8192
    COMMENT '실시간 주문 데이터 (CDC 동기화)';

-- ============================================
-- Materialized View 1: 일별 주문 집계
-- 엔진: SummingMergeTree (자동 합산)
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS order_analytics.orders_daily_summary (
  order_date      Date COMMENT '주문 날짜',
  status          String COMMENT '주문 상태',
  order_count     UInt64 COMMENT '주문 건수',
  total_revenue   Decimal(18, 2) COMMENT '총 매출',
  avg_order_value Decimal(10, 2) COMMENT '평균 주문 금액'
)
  ENGINE = SummingMergeTree((order_count, total_revenue)) PARTITION BY toYYYYMM(order_date)
    ORDER BY (order_date, status)
    SETTINGS index_granularity = 8192
    COMMENT '일별 주문 요약 집계';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS order_analytics.mv_orders_daily_summary
  TO order_analytics.orders_daily_summary
AS
SELECT toDate(order_date) AS order_date,
       status,
       count(*)           AS order_count,
       sum(total_amount)  AS total_revenue,
       avg(total_amount)  AS avg_order_value
FROM order_analytics.orders_realtime
WHERE cdc_op != 'd' -- DELETE 이벤트 제외
GROUP BY order_date, status;

-- ============================================
-- Materialized View 2: 시간별 주문 통계
-- 엔진: AggregatingMergeTree (집계 함수 지원)
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS order_analytics.orders_hourly_stats (
  hour_timestamp   DateTime COMMENT '시간 단위 (YYYY-MM-DD HH:00:00)',
  status           String COMMENT '주문 상태',
  order_count      AggregateFunction(count, UInt64) COMMENT '주문 건수 (집계)',
  total_revenue    AggregateFunction(sum, Decimal(18, 2)) COMMENT '총 매출 (집계)',
  max_order_amount AggregateFunction(max, Decimal(10, 2)) COMMENT '최대 주문 금액 (집계)',
  min_order_amount AggregateFunction(min, Decimal(10, 2)) COMMENT '최소 주문 금액 (집계)'
)
  ENGINE = AggregatingMergeTree() PARTITION BY toYYYYMM(hour_timestamp)
    ORDER BY (hour_timestamp, status)
    SETTINGS index_granularity = 8192
    COMMENT '시간별 주문 통계';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS order_analytics.mv_orders_hourly_stats
  TO order_analytics.orders_hourly_stats
AS
SELECT toStartOfHour(order_date) AS hour_timestamp,
       status,
       countState(*)             AS order_count,
       sumState(total_amount)    AS total_revenue,
       maxState(total_amount)    AS max_order_amount,
       minState(total_amount)    AS min_order_amount
FROM order_analytics.orders_realtime
WHERE cdc_op != 'd' -- DELETE 이벤트 제외
GROUP BY hour_timestamp, status;

-- ============================================
-- Materialized View 3: 사용자별 구매 이력
-- 엔진: ReplacingMergeTree
-- ============================================

-- 집계 테이블 생성
CREATE TABLE IF NOT EXISTS order_analytics.user_purchase_history (
  user_id          UInt64 COMMENT '사용자 ID',
  first_order_date DateTime COMMENT '첫 구매 일시',
  last_order_date  DateTime COMMENT '최근 구매 일시',
  total_orders     UInt32 COMMENT '총 주문 건수',
  total_spent      Decimal(18, 2) COMMENT '총 구매 금액',
  avg_order_value  Decimal(10, 2) COMMENT '평균 주문 금액',
  completed_orders UInt32 COMMENT '완료된 주문 건수',
  cancelled_orders UInt32 COMMENT '취소된 주문 건수',
  updated_at       DateTime DEFAULT now() COMMENT '업데이트 시각'
)
  ENGINE = ReplacingMergeTree(updated_at)
    ORDER BY user_id SETTINGS index_granularity = 8192
    COMMENT '사용자별 구매 이력 요약';

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS order_analytics.mv_user_purchase_history
  TO order_analytics.user_purchase_history
AS
SELECT user_id,
       min(order_date)               AS first_order_date,
       max(order_date)               AS last_order_date,
       count(*)                      AS total_orders,
       sum(total_amount)             AS total_spent,
       avg(total_amount)             AS avg_order_value,
       countIf(status = 'COMPLETED') AS completed_orders,
       countIf(status = 'CANCELLED') AS cancelled_orders,
       now()                         AS updated_at
FROM order_analytics.orders_realtime
WHERE cdc_op != 'd' -- DELETE 이벤트 제외
GROUP BY user_id;

-- ============================================
-- 인덱스 생성 (쿼리 성능 최적화)
-- 참고: 인덱스가 이미 존재하면 에러가 발생하지만, 스크립트는 계속 실행됩니다
-- ============================================

-- ============================================
-- 샘플 쿼리 (테스트 및 검증용)
-- ============================================

-- 1. 실시간 주문 현황 조회
-- SELECT
--     status,
--     count(*) AS order_count,
--     sum(total_amount) AS total_revenue,
--     avg(total_amount) AS avg_order_value
-- FROM order_analytics.orders_realtime
-- WHERE toDate(order_date) = today()
-- GROUP BY status
-- ORDER BY order_count DESC;

-- 2. 시간별 주문 통계 조회 (AggregatingMergeTree 읽기)
-- SELECT
--     hour_timestamp,
--     status,
--     countMerge(order_count) AS orders,
--     sumMerge(total_revenue) AS revenue,
--     maxMerge(max_order_amount) AS max_amount,
--     minMerge(min_order_amount) AS min_amount
-- FROM order_analytics.orders_hourly_stats
-- WHERE hour_timestamp >= toStartOfHour(now() - INTERVAL 24 HOUR)
-- GROUP BY hour_timestamp, status
-- ORDER BY hour_timestamp DESC, orders DESC;

-- 3. 일별 주문 요약 조회
-- SELECT
--     order_date,
--     status,
--     sum(order_count) AS total_orders,
--     sum(total_revenue) AS total_revenue,
--     avg(avg_order_value) AS avg_value
-- FROM order_analytics.orders_daily_summary
-- WHERE order_date >= today() - INTERVAL 7 DAY
-- GROUP BY order_date, status
-- ORDER BY order_date DESC, status;

-- 4. 사용자별 구매 이력 조회 (Top 10 VIP)
-- SELECT
--     user_id,
--     total_orders,
--     total_spent,
--     avg_order_value,
--     completed_orders,
--     cancelled_orders,
--     dateDiff('day', first_order_date, last_order_date) AS customer_lifetime_days
-- FROM order_analytics.user_purchase_history
-- ORDER BY total_spent DESC
-- LIMIT 10;

-- 5. 최근 1시간 주문 현황 (실시간 모니터링)
-- SELECT
--     toStartOfMinute(order_date) AS minute,
--     count(*) AS orders_per_minute,
--     sum(total_amount) AS revenue_per_minute
-- FROM order_analytics.orders_realtime
-- WHERE order_date >= now() - INTERVAL 1 HOUR
-- GROUP BY minute
-- ORDER BY minute DESC;

-- ============================================
-- 테이블 정보 확인
-- ============================================

SELECT '✅ ClickHouse 초기화 완료' AS status;

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
