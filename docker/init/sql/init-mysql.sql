-- ============================================
-- MySQL 초기화 스크립트
-- 목적: orders, order_item 테이블 생성 및 샘플 데이터 삽입
-- ============================================

-- UTF-8 인코딩 설정 (한글 깨짐 방지)
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

-- ============================================
-- CDC 사용자 생성 및 권한 부여
-- ============================================

-- CDC 전용 사용자 생성 (모든 호스트에서 접속 가능)
CREATE USER IF NOT EXISTS 'cdc'@'%' IDENTIFIED BY 'test123';

-- Binlog 읽기 권한 (CDC에 필수)
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'cdc'@'%';

-- order_db 데이터베이스 읽기 권한
GRANT SELECT ON order_db.* TO 'cdc'@'%';

-- 권한 즉시 적용
FLUSH PRIVILEGES;

-- ============================================
-- 데이터베이스 하드 삭제 및 재생성
-- ============================================

-- 기존 데이터베이스 완전 삭제
DROP DATABASE IF EXISTS order_db;

-- 데이터베이스 생성
CREATE DATABASE order_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE order_db;

-- ============================================
-- 테이블 생성
-- ============================================

-- users 테이블
CREATE TABLE IF NOT EXISTS users (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '사용자 ID',
  username   VARCHAR(50)  NOT NULL UNIQUE COMMENT '사용자명 (고유)',
  email      VARCHAR(100) NOT NULL UNIQUE COMMENT '이메일 (고유)',
  phone      VARCHAR(20) COMMENT '전화번호',
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '계정 생성 일시',
  updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '마지막 수정 일시',
  deleted_at TIMESTAMP    NULL     DEFAULT NULL COMMENT 'Soft Delete 일시 (NULL=활성)',
  INDEX idx_email (email),
  INDEX idx_username (username),
  INDEX idx_deleted_at (deleted_at)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT ='사용자 정보 테이블';

-- products 테이블
CREATE TABLE IF NOT EXISTS products (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '상품 ID',
  name        VARCHAR(255)   NOT NULL COMMENT '상품명',
  category    VARCHAR(50) COMMENT '카테고리',
  price       DECIMAL(10, 2) NOT NULL COMMENT '판매 가격',
  stock       INT            NOT NULL DEFAULT 0 COMMENT '재고 수량',
  description TEXT COMMENT '상품 설명',
  created_at  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '상품 등록 일시',
  updated_at  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '마지막 수정 일시',
  deleted_at  TIMESTAMP      NULL     DEFAULT NULL COMMENT 'Soft Delete 일시 (NULL=활성)',
  INDEX idx_category (category),
  INDEX idx_price (price),
  INDEX idx_name (name),
  INDEX idx_deleted_at (deleted_at)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT ='상품 정보 테이블';

-- orders 테이블
CREATE TABLE IF NOT EXISTS orders (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '주문 ID',
  user_id      BIGINT         NOT NULL COMMENT '사용자 ID',
  status       VARCHAR(20)    NOT NULL DEFAULT 'PENDING' COMMENT '주문 상태 (PENDING, PROCESSING, COMPLETED, CANCELLED)',
  total_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00 COMMENT '총 주문 금액',
  created_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '주문 생성 일시',
  updated_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '마지막 수정 일시',
  deleted_at   TIMESTAMP      NULL     DEFAULT NULL COMMENT 'Soft Delete 일시 (NULL=활성)',
  INDEX idx_user_id (user_id),
  INDEX idx_status (status),
  INDEX idx_created_at (created_at),
  INDEX idx_deleted_at (deleted_at)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT ='주문 마스터 테이블';

-- order_items 테이블
CREATE TABLE IF NOT EXISTS order_items (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '주문 항목 ID',
  order_id     BIGINT         NOT NULL COMMENT '주문 ID (FK)',
  product_id   BIGINT         NOT NULL COMMENT '상품 ID',
  product_name VARCHAR(255)   NOT NULL COMMENT '상품명',
  quantity     INT            NOT NULL DEFAULT 1 COMMENT '수량',
  price        DECIMAL(10, 2) NOT NULL COMMENT '단가',
  subtotal     DECIMAL(10, 2) NOT NULL COMMENT '소계 (quantity * price)',
  created_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 일시',
  updated_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '마지막 수정 일시',
  deleted_at   TIMESTAMP      NULL     DEFAULT NULL COMMENT 'Soft Delete 일시 (NULL=활성)',
  FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
  INDEX idx_order_id (order_id),
  INDEX idx_product_id (product_id),
  INDEX idx_deleted_at (deleted_at)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT ='주문 상세 항목 테이블';

-- ============================================
-- 샘플 데이터 삽입
-- ============================================

-- ============================================
-- Users 샘플 데이터 (9명)
-- ============================================
INSERT INTO users (id, username, email, phone, created_at)
VALUES (101, 'john_doe', 'john.doe@example.com', '010-1234-5678', '2024-12-01 10:00:00'),
       (102, 'jane_smith', 'jane.smith@example.com', '010-2345-6789', '2024-12-02 11:30:00'),
       (103, 'bob_wilson', 'bob.wilson@example.com', '010-3456-7890', '2024-12-03 14:15:00'),
       (104, 'alice_brown', 'alice.brown@example.com', '010-4567-8901', '2024-12-04 09:45:00'),
       (105, 'charlie_davis', 'charlie.davis@example.com', '010-5678-9012', '2024-12-05 16:20:00'),
       (106, 'diana_miller', 'diana.miller@example.com', '010-6789-0123', '2024-12-06 13:50:00'),
       (107, 'eve_garcia', 'eve.garcia@example.com', '010-7890-1234', '2024-12-07 10:10:00'),
       (108, 'frank_rodriguez', 'frank.rodriguez@example.com', '010-8901-2345', '2024-12-08 15:30:00'),
       (109, 'grace_martinez', 'grace.martinez@example.com', '010-9012-3456', '2024-12-09 12:00:00');

-- ============================================
-- Products 샘플 데이터 (20개)
-- ============================================
INSERT INTO products (id, name, category, price, stock, description, created_at)
VALUES
  -- 전자제품
  (1001, '삼성 갤럭시 S24', '전자제품', 1299000.00, 50, '최신 삼성 플래그십 스마트폰', '2024-11-01 09:00:00'),
  (1002, '갤럭시 버즈 프로', '전자제품', 250000.00, 100, '노이즈 캔슬링 무선 이어폰', '2024-11-01 09:00:00'),
  (1003, '무선충전기', '전자제품', 50000.00, 200, '고속 무선 충전 패드', '2024-11-01 09:00:00'),
  (2001, 'MacBook Air M3', '전자제품', 1690000.00, 30, 'Apple M3 칩 탑재 노트북', '2024-11-02 10:00:00'),
  (2002, '맥북 파우치', '액세서리', 50000.00, 150, '프리미엄 가죽 맥북 케이스', '2024-11-02 10:00:00'),
  (2003, 'USB-C 허브', '전자제품', 150000.00, 80, '다기능 USB-C 어댑터', '2024-11-02 10:00:00'),
  (4001, 'LG 스탠바이미', '가전제품', 456000.00, 20, '무선 이동형 터치스크린', '2024-11-04 11:00:00'),
  -- 의류
  (3001, '겨울 패딩 점퍼', '의류', 189000.00, 60, '프리미엄 다운 패딩', '2024-11-03 14:00:00'),
  (3002, '기모 맨투맨', '의류', 50000.00, 120, '따뜻한 기모 안감', '2024-11-03 14:00:00'),
  -- 도서
  (5001, 'Effective Java 3판', '도서', 36000.00, 100, '자바 프로그래밍 바이블', '2024-11-05 09:00:00'),
  (5002, 'Clean Code', '도서', 33000.00, 80, '클린 코드의 정석', '2024-11-05 09:00:00'),
  (5003, 'HTTP 완벽 가이드', '도서', 18500.00, 90, 'HTTP 프로토콜 심화 학습', '2024-11-05 09:00:00'),
  -- 생활용품
  (6001, '다이슨 청소기', '생활용품', 135000.00, 40, '무선 핸디형 청소기', '2024-11-06 13:00:00'),
  -- 스포츠
  (7001, '나이키 운동화', '스포츠', 149000.00, 70, '에어맥스 러닝화', '2024-11-07 15:00:00'),
  (7002, '요가매트', '스포츠', 45000.00, 100, 'NBR 요가 매트', '2024-11-07 15:00:00'),
  (7003, '덤벨 세트', '스포츠', 40000.00, 50, '2kg~10kg 덤벨 세트', '2024-11-07 15:00:00'),
  -- 화장품
  (8001, '에스티로더 세럼', '화장품', 89000.00, 60, '안티에이징 세럼', '2024-11-08 10:00:00'),
  (8002, '설화수 토너', '화장품', 89000.00, 55, '자음생 에센스', '2024-11-08 10:00:00'),
  -- 식품
  (9001, '한우 세트', '식품', 52000.00, 30, '1등급 한우 세트', '2024-11-09 08:00:00'),
  -- 가구
  (10001, '허먼밀러 의자', '가구', 899000.00, 15, '에어론 리마스터드', '2024-11-10 11:00:00');

-- ============================================
-- Orders 샘플 데이터 (10개 주문)
-- ============================================

-- 주문 1: 전자제품 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (101, 'COMPLETED', 1799000.00, '2025-01-10 09:15:30');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 1001, '삼성 갤럭시 S24', 1, 1299000.00, 1299000.00),
       (LAST_INSERT_ID(), 1002, '갤럭시 버즈 프로', 1, 250000.00, 250000.00),
       (LAST_INSERT_ID(), 1003, '무선충전기', 1, 50000.00, 50000.00);

-- 주문 2: 노트북 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (102, 'PROCESSING', 2190000.00, '2025-01-10 10:22:15');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 2001, 'MacBook Air M3', 1, 1690000.00, 1690000.00),
       (LAST_INSERT_ID(), 2002, '맥북 파우치', 1, 50000.00, 50000.00),
       (LAST_INSERT_ID(), 2003, 'USB-C 허브', 1, 150000.00, 150000.00);

-- 주문 3: 의류 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (103, 'PENDING', 289000.00, '2025-01-10 11:45:20');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 3001, '겨울 패딩 점퍼', 1, 189000.00, 189000.00),
       (LAST_INSERT_ID(), 3002, '기모 맨투맨', 2, 50000.00, 100000.00);

-- 주문 4: 가전제품 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (104, 'COMPLETED', 456000.00, '2025-01-10 13:10:05');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 4001, 'LG 스탠바이미', 1, 456000.00, 456000.00);

-- 주문 5: 도서 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (105, 'COMPLETED', 87500.00, '2025-01-10 14:35:40');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 5001, 'Effective Java 3판', 1, 36000.00, 36000.00),
       (LAST_INSERT_ID(), 5002, 'Clean Code', 1, 33000.00, 33000.00),
       (LAST_INSERT_ID(), 5003, 'HTTP 완벽 가이드', 1, 18500.00, 18500.00);

-- 주문 6: 생활용품 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (106, 'PROCESSING', 135000.00, '2025-01-10 15:20:18');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 6001, '다이슨 청소기', 1, 135000.00, 135000.00);

-- 주문 7: 스포츠용품 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (101, 'COMPLETED', 234000.00, '2025-01-10 16:05:50');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 7001, '나이키 운동화', 1, 149000.00, 149000.00),
       (LAST_INSERT_ID(), 7002, '요가매트', 1, 45000.00, 45000.00),
       (LAST_INSERT_ID(), 7003, '덤벨 세트', 1, 40000.00, 40000.00);

-- 주문 8: 화장품 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (107, 'PENDING', 178000.00, '2025-01-10 17:40:22');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 8001, '에스티로더 세럼', 1, 89000.00, 89000.00),
       (LAST_INSERT_ID(), 8002, '설화수 토너', 1, 89000.00, 89000.00);

-- 주문 9: 식품 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (108, 'CANCELLED', 52000.00, '2025-01-10 18:15:30');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 9001, '한우 세트', 1, 52000.00, 52000.00);

-- 주문 10: 가구 구매
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (109, 'PROCESSING', 899000.00, '2025-01-10 19:30:45');

INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 10001, '허먼밀러 의자', 1, 899000.00, 899000.00);

-- ============================================
-- 데이터 확인 쿼리
-- ============================================

-- 사용자 수 확인
SELECT COUNT(*) as total_users
FROM users;

-- 상품 수 확인 (카테고리별)
SELECT category, COUNT(*) as product_count, SUM(stock) as total_stock
FROM products
GROUP BY category
ORDER BY category;

-- 주문 건수 확인 (상태별)
SELECT status,
       COUNT(*)          as order_count,
       SUM(total_amount) as total_revenue
FROM orders
GROUP BY status
ORDER BY status;

-- 총 주문 항목 수 확인
SELECT COUNT(*) as total_items
FROM order_items;

-- 최근 주문 목록 (사용자, 주문 항목 정보 포함)
SELECT o.id as order_id,
       u.username,
       u.email,
       o.status,
       o.total_amount,
       o.created_at,
       oi.product_name,
       oi.quantity,
       oi.price,
       oi.subtotal
FROM orders o
INNER JOIN users u ON o.user_id = u.id
INNER JOIN order_items oi ON o.id = oi.order_id
ORDER BY o.created_at DESC
LIMIT 20;

SELECT '✅ MySQL 초기화 완료: 9명 사용자, 20개 상품, 10개 주문, 18개 주문항목 생성됨' as status;
