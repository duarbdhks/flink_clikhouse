-- ============================================
-- Users 테이블 생성
-- 목적: 사용자 정보 저장 및 주문과의 관계 설정
-- ============================================

USE order_db;

-- users 테이블
CREATE TABLE IF NOT EXISTS users (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '사용자 ID',
  username   VARCHAR(50)  NOT NULL UNIQUE COMMENT '사용자명 (고유)',
  email      VARCHAR(100) NOT NULL UNIQUE COMMENT '이메일 (고유)',
  phone      VARCHAR(20) COMMENT '전화번호',
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '계정 생성 일시',
  INDEX idx_email (email),
  INDEX idx_username (username)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT ='사용자 정보 테이블';

SELECT '✅ Users 테이블 생성 완료' as status;
