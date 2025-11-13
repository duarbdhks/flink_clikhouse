-- ============================================
-- MySQL 초기화 스크립트
-- 목적: orders, order_item 테이블 생성 및 샘플 데이터 삽입
-- ============================================

-- UTF-8 인코딩 설정 (한글 깨짐 방지)
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

-- 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS order_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE order_db;

-- ============================================
-- 테이블 생성
-- ============================================

-- order 테이블
CREATE TABLE IF NOT EXISTS orders (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '주문 ID',
  user_id      BIGINT         NOT NULL COMMENT '사용자 ID',
  status       VARCHAR(20)    NOT NULL DEFAULT 'PENDING' COMMENT '주문 상태 (PENDING, PROCESSING, COMPLETED, CANCELLED)',
  total_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00 COMMENT '총 주문 금액',
  order_date   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '주문 생성 일시',
  updated_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '마지막 수정 일시',
  INDEX idx_user_id (user_id),
  INDEX idx_status (status),
  INDEX idx_order_date (order_date)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT ='주문 마스터 테이블';

-- order_item 테이블
CREATE TABLE IF NOT EXISTS order_item (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '주문 항목 ID',
  order_id     BIGINT         NOT NULL COMMENT '주문 ID (FK)',
  product_id   BIGINT         NOT NULL COMMENT '상품 ID',
  product_name VARCHAR(255)   NOT NULL COMMENT '상품명',
  quantity     INT            NOT NULL DEFAULT 1 COMMENT '수량',
  price        DECIMAL(10, 2) NOT NULL COMMENT '단가',
  subtotal     DECIMAL(10, 2) NOT NULL COMMENT '소계 (quantity * price)',
  created_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 일시',
  FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
  INDEX idx_order_id (order_id),
  INDEX idx_product_id (product_id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT ='주문 상세 항목 테이블';

-- ============================================
-- CDC 사용자 생성 및 권한 부여
-- ============================================

-- Flink CDC 전용 사용자 생성
CREATE USER IF NOT EXISTS 'flink_cdc'@'%' IDENTIFIED BY 'flink_cdc_password';

-- CDC에 필요한 권한 부여
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'flink_cdc'@'%';

-- order_db에 대한 모든 권한 부여
GRANT ALL PRIVILEGES ON order_db.* TO 'flink_cdc'@'%';

FLUSH PRIVILEGES;

-- ============================================
-- 샘플 데이터 삽입 (10개 주문)
-- 멱등성 보장: 기존 데이터 삭제 후 재삽입
-- ============================================

-- 기존 샘플 데이터 삭제 (멱등성 보장)
DELETE FROM order_item WHERE order_id IN (SELECT id FROM orders WHERE user_id IN (101, 102, 103, 104, 105, 106, 107, 108, 109));
DELETE FROM orders WHERE user_id IN (101, 102, 103, 104, 105, 106, 107, 108, 109);

-- AUTO_INCREMENT 초기화 (선택적)
ALTER TABLE orders AUTO_INCREMENT = 1;
ALTER TABLE order_item AUTO_INCREMENT = 1;

-- 주문 1: 전자제품 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (101, 'COMPLETED', 1799000.00, '2025-01-10 09:15:30');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 1001, '삼성 갤럭시 S24', 1, 1299000.00, 1299000.00),
       (LAST_INSERT_ID(), 1002, '갤럭시 버즈 프로', 1, 250000.00, 250000.00),
       (LAST_INSERT_ID(), 1003, '무선충전기', 1, 50000.00, 50000.00);

-- 주문 2: 노트북 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (102, 'PROCESSING', 2190000.00, '2025-01-10 10:22:15');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 2001, 'MacBook Air M3', 1, 1690000.00, 1690000.00),
       (LAST_INSERT_ID(), 2002, '맥북 파우치', 1, 50000.00, 50000.00),
       (LAST_INSERT_ID(), 2003, 'USB-C 허브', 1, 150000.00, 150000.00);

-- 주문 3: 의류 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (103, 'PENDING', 289000.00, '2025-01-10 11:45:20');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 3001, '겨울 패딩 점퍼', 1, 189000.00, 189000.00),
       (LAST_INSERT_ID(), 3002, '기모 맨투맨', 2, 50000.00, 100000.00);

-- 주문 4: 가전제품 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (104, 'COMPLETED', 456000.00, '2025-01-10 13:10:05');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 4001, 'LG 스탠바이미', 1, 456000.00, 456000.00);

-- 주문 5: 도서 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (105, 'COMPLETED', 87500.00, '2025-01-10 14:35:40');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 5001, 'Effective Java 3판', 1, 36000.00, 36000.00),
       (LAST_INSERT_ID(), 5002, 'Clean Code', 1, 33000.00, 33000.00),
       (LAST_INSERT_ID(), 5003, 'HTTP 완벽 가이드', 1, 18500.00, 18500.00);

-- 주문 6: 생활용품 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (106, 'PROCESSING', 135000.00, '2025-01-10 15:20:18');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 6001, '다이슨 청소기', 1, 135000.00, 135000.00);

-- 주문 7: 스포츠용품 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (101, 'COMPLETED', 234000.00, '2025-01-10 16:05:50');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 7001, '나이키 운동화', 1, 149000.00, 149000.00),
       (LAST_INSERT_ID(), 7002, '요가매트', 1, 45000.00, 45000.00),
       (LAST_INSERT_ID(), 7003, '덤벨 세트', 1, 40000.00, 40000.00);

-- 주문 8: 화장품 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (107, 'PENDING', 178000.00, '2025-01-10 17:40:22');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 8001, '에스티로더 세럼', 1, 89000.00, 89000.00),
       (LAST_INSERT_ID(), 8002, '설화수 토너', 1, 89000.00, 89000.00);

-- 주문 9: 식품 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (108, 'CANCELLED', 52000.00, '2025-01-10 18:15:30');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 9001, '한우 세트', 1, 52000.00, 52000.00);

-- 주문 10: 가구 구매
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (109, 'PROCESSING', 899000.00, '2025-01-10 19:30:45');

INSERT INTO order_item (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 10001, '허먼밀러 의자', 1, 899000.00, 899000.00);

-- ============================================
-- 데이터 확인 쿼리
-- ============================================

-- 주문 건수 확인
SELECT status,
       COUNT(*)          as order_count,
       SUM(total_amount) as total_revenue
FROM orders
GROUP BY status
ORDER BY status;

-- 총 주문 항목 수 확인
SELECT COUNT(*) as total_items
FROM order_item;

-- 최근 주문 목록 (주문 항목 포함)
SELECT o.id as order_id,
       o.user_id,
       o.status,
       o.total_amount,
       o.order_date,
       oi.product_name,
       oi.quantity,
       oi.price,
       oi.subtotal
FROM orders o
INNER JOIN order_item oi ON o.id = oi.order_id
ORDER BY o.order_date DESC
LIMIT 20;

SELECT '✅ MySQL 초기화 완료: 10개 주문, 18개 항목 삽입됨' as status;
