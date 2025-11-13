-- ============================================
-- Users 샘플 데이터 삽입
-- 목적: 기존 orders 테이블의 user_id(101-109)와 매핑되는 사용자 생성
-- ============================================

USE order_db;

-- 기존 샘플 데이터 삭제 (멱등성 보장)
DELETE FROM users WHERE id BETWEEN 101 AND 109;

-- AUTO_INCREMENT 조정 (ID 101부터 시작)
-- 참고: 기존 주문 데이터의 user_id(101-109)와 매핑
ALTER TABLE users AUTO_INCREMENT = 101;

-- 샘플 사용자 9명 생성
INSERT INTO users (id, username, email, phone, created_at) VALUES
  (101, 'john_doe', 'john.doe@example.com', '010-1234-5678', '2024-12-01 10:00:00'),
  (102, 'jane_smith', 'jane.smith@example.com', '010-2345-6789', '2024-12-02 11:30:00'),
  (103, 'bob_wilson', 'bob.wilson@example.com', '010-3456-7890', '2024-12-03 14:15:00'),
  (104, 'alice_brown', 'alice.brown@example.com', '010-4567-8901', '2024-12-04 09:45:00'),
  (105, 'charlie_davis', 'charlie.davis@example.com', '010-5678-9012', '2024-12-05 16:20:00'),
  (106, 'diana_miller', 'diana.miller@example.com', '010-6789-0123', '2024-12-06 13:50:00'),
  (107, 'eve_garcia', 'eve.garcia@example.com', '010-7890-1234', '2024-12-07 10:10:00'),
  (108, 'frank_rodriguez', 'frank.rodriguez@example.com', '010-8901-2345', '2024-12-08 15:30:00'),
  (109, 'grace_martinez', 'grace.martinez@example.com', '010-9012-3456', '2024-12-09 12:00:00');

-- 데이터 확인
SELECT id, username, email, phone, created_at
FROM users
ORDER BY id;

SELECT '✅ Users 샘플 데이터 삽입 완료: 9명의 사용자 생성됨' as status;
