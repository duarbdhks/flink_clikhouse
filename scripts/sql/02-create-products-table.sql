-- ============================================
-- Products 테이블 생성
-- 목적: 상품 정보 저장 및 재고 관리
-- ============================================

USE order_db;

-- products 테이블
CREATE TABLE IF NOT EXISTS products (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '상품 ID',
  name        VARCHAR(255) NOT NULL COMMENT '상품명',
  category    VARCHAR(50) COMMENT '카테고리',
  price       DECIMAL(10, 2) NOT NULL COMMENT '판매 가격',
  stock       INT NOT NULL DEFAULT 0 COMMENT '재고 수량',
  description TEXT COMMENT '상품 설명',
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '상품 등록 일시',
  updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '마지막 수정 일시',
  INDEX idx_category (category),
  INDEX idx_price (price),
  INDEX idx_name (name)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT ='상품 정보 테이블';

SELECT '✅ Products 테이블 생성 완료' as status;
