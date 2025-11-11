# 파이프라인 E2E 테스트 가이드

## 📋 개요
전체 데이터 파이프라인의 정상 동작을 검증하는 End-to-End 테스트 가이드

## 🎯 테스트 목표
- **데이터 흐름 검증**: MySQL → Flink CDC → Kafka → Flink Sync → ClickHouse
- **데이터 정합성 검증**: 소스 데이터와 타겟 데이터 일치 확인
- **실시간 동기화 검증**: 지연 시간 및 처리량 측정
- **장애 복구 검증**: 컴포넌트 장애 시 복구 능력 확인

## 🔧 사전 준비

### 1. 전체 인프라 시작
```bash
# 모든 서비스 시작
docker-compose up -d

# 서비스 상태 확인
docker-compose ps

# 모든 컨테이너가 healthy 상태인지 확인
# NAME                  STATUS
# mysql                 Up (healthy)
# kafka                 Up (healthy)
# clickhouse-server     Up (healthy)
# flink-jobmanager      Up (healthy)
# flink-taskmanager     Up
```

### 2. Kafka Topic 생성
```bash
# Topic 생성
docker exec -it kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc-topic \
  --partitions 3 \
  --replication-factor 1

# Topic 확인
docker exec -it kafka kafka-topics --list --bootstrap-server localhost:9092
```

### 3. ClickHouse 테이블 확인
```bash
docker exec -it clickhouse-server clickhouse-client \
  --query "SHOW TABLES FROM order_analytics"

# 예상 출력:
# orders_realtime
# orders_daily_summary
# orders_hourly_stats
```

## 🧪 테스트 시나리오

### Test 1: 기본 데이터 흐름 검증

#### 목적
MySQL INSERT → ClickHouse INSERT 전체 흐름 확인

#### 테스트 실행
```bash
# 1. MySQL 초기 카운트 확인
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "SELECT COUNT(*) AS mysql_count FROM orders"

# 2. ClickHouse 초기 카운트 확인
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) AS ch_count FROM order_analytics.orders_realtime"

# 3. MySQL에 새 주문 삽입
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "INSERT INTO orders (user_id, product_name, quantity, total_price, status) VALUES (500, 'Test Laptop', 1, 1200.00, 'pending')"

# 4. Kafka에서 CDC 이벤트 확인 (1-2초 대기)
sleep 2
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc-topic \
  --max-messages 1 \
  --timeout-ms 5000

# 5. ClickHouse에서 데이터 확인 (3-7초 대기)
sleep 5
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT * FROM order_analytics.orders_realtime WHERE user_id = 500 ORDER BY event_timestamp DESC LIMIT 1"

# 6. 최종 카운트 비교
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "SELECT COUNT(*) AS mysql_count FROM orders"

docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) AS ch_count FROM order_analytics.orders_realtime WHERE operation_type != 'DELETE'"
```

#### 예상 결과
```
✅ Kafka에 CDC 이벤트 수신됨
✅ ClickHouse에 레코드 삽입됨
✅ MySQL 카운트 = ClickHouse 카운트
```

### Test 2: UPDATE 이벤트 처리

#### 목적
UPDATE 작업이 ClickHouse에 정상 반영되는지 확인

#### 테스트 실행
```bash
# 1. 특정 주문 조회
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "SELECT order_id, status FROM orders WHERE user_id = 500"

# 2. 상태 업데이트 (pending → completed)
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "UPDATE orders SET status = 'completed' WHERE user_id = 500"

# 3. ClickHouse에서 UPDATE 이벤트 확인 (5초 대기)
sleep 5
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT order_id, status, operation_type, event_timestamp FROM order_analytics.orders_realtime WHERE user_id = 500 ORDER BY event_timestamp DESC LIMIT 2"
```

#### 예상 결과
```
✅ 2개의 레코드 조회됨 (INSERT, UPDATE)
✅ 최신 레코드의 status = 'completed'
✅ operation_type = 'UPDATE'
```

### Test 3: DELETE 이벤트 처리

#### 목적
DELETE 작업이 논리적 삭제로 처리되는지 확인

#### 테스트 실행
```bash
# 1. 주문 삭제
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "DELETE FROM orders WHERE user_id = 500"

# 2. ClickHouse에서 DELETE 이벤트 확인 (5초 대기)
sleep 5
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT order_id, status, operation_type FROM order_analytics.orders_realtime WHERE user_id = 500 ORDER BY event_timestamp DESC LIMIT 3"
```

#### 예상 결과
```
✅ 3개의 레코드 조회됨 (INSERT, UPDATE, DELETE)
✅ 최신 레코드의 operation_type = 'DELETE'
✅ before 데이터가 ClickHouse에 저장됨
```

### Test 4: 대량 데이터 처리

#### 목적
처리량(Throughput) 및 지연 시간(Latency) 측정

#### 테스트 실행
```bash
# 1. 시작 시간 기록
START_TIME=$(date +%s)

# 2. 100건의 주문 생성
for i in {1..100}; do
  docker exec -it mysql mysql -u root -proot_password order_db \
    -e "INSERT INTO orders (user_id, product_name, quantity, total_price) VALUES ($((1000+i)), 'Product $i', 1, $((100+i)).00)"
done

# 3. 종료 시간 기록
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "✅ 100건 INSERT 완료 (소요 시간: ${DURATION}초)"

# 4. MySQL 최종 카운트
MYSQL_COUNT=$(docker exec -it mysql mysql -u root -proot_password order_db \
  -se "SELECT COUNT(*) FROM orders WHERE user_id >= 1001 AND user_id <= 1100")

# 5. 30초 대기 (파이프라인 처리 시간)
echo "⏳ 30초 대기 중..."
sleep 30

# 6. ClickHouse 최종 카운트
CH_COUNT=$(docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) FROM order_analytics.orders_realtime WHERE user_id >= 1001 AND user_id <= 1100 AND operation_type != 'DELETE'")

# 7. 결과 비교
echo "MySQL 카운트: ${MYSQL_COUNT}"
echo "ClickHouse 카운트: ${CH_COUNT}"

if [ "$MYSQL_COUNT" -eq "$CH_COUNT" ]; then
  echo "✅ 데이터 정합성 검증 성공"
else
  echo "❌ 데이터 불일치 발견"
fi
```

#### 예상 결과
```
✅ 100건 INSERT 완료 (소요 시간: 15-30초)
✅ MySQL 카운트: 100
✅ ClickHouse 카운트: 100
✅ 데이터 정합성 검증 성공
```

### Test 5: 지연 시간 측정

#### 목적
End-to-End 지연 시간(Latency) 측정

#### 테스트 실행
```bash
cat > test_latency.sh << 'EOF'
#!/bin/bash

# 테스트 횟수
TEST_COUNT=10

echo "지연 시간 측정 시작 (${TEST_COUNT}회)"
echo "=========================================="

TOTAL_LATENCY=0

for i in $(seq 1 $TEST_COUNT); do
  # 1. MySQL INSERT 시작 시간
  INSERT_START=$(date +%s%3N)  # 밀리초

  # 2. 주문 삽입
  ORDER_ID=$(docker exec -it mysql mysql -u root -proot_password order_db \
    -se "INSERT INTO orders (user_id, product_name, quantity, total_price) VALUES ($((2000+i)), 'Latency Test $i', 1, 100.00); SELECT LAST_INSERT_ID();")

  # 3. ClickHouse에서 대기 및 확인
  while true; do
    COUNT=$(docker exec -it clickhouse-server clickhouse-client \
      --query "SELECT COUNT(*) FROM order_analytics.orders_realtime WHERE order_id = ${ORDER_ID}")

    if [ "$COUNT" -ge 1 ]; then
      INSERT_END=$(date +%s%3N)
      LATENCY=$((INSERT_END - INSERT_START))
      TOTAL_LATENCY=$((TOTAL_LATENCY + LATENCY))
      echo "Test $i: ${LATENCY}ms"
      break
    fi

    sleep 0.1
  done
done

AVG_LATENCY=$((TOTAL_LATENCY / TEST_COUNT))
echo "=========================================="
echo "평균 지연 시간: ${AVG_LATENCY}ms"
EOF

chmod +x test_latency.sh
./test_latency.sh
```

#### 예상 결과
```
✅ 평균 지연 시간: 2000-5000ms (2-5초)
MVP 목표: < 5초
```

### Test 6: Flink Job 재시작 (장애 복구)

#### 목적
Flink Job 재시작 후 데이터 일관성 유지 확인

#### 테스트 실행
```bash
# 1. 초기 카운트 기록
INITIAL_COUNT=$(docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) FROM order_analytics.orders_realtime")

echo "초기 ClickHouse 카운트: ${INITIAL_COUNT}"

# 2. Flink JobManager 재시작
docker restart flink-jobmanager

echo "⏳ Flink 재시작 중... (30초 대기)"
sleep 30

# 3. Job 상태 확인
docker exec -it flink-jobmanager flink list

# 4. MySQL에 새 데이터 삽입
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "INSERT INTO orders (user_id, product_name, quantity, total_price) VALUES (3000, 'Recovery Test', 1, 100.00)"

# 5. ClickHouse 확인 (10초 대기)
sleep 10
FINAL_COUNT=$(docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) FROM order_analytics.orders_realtime")

echo "최종 ClickHouse 카운트: ${FINAL_COUNT}"

# 6. 증가량 확인
DIFF=$((FINAL_COUNT - INITIAL_COUNT))
echo "증가량: ${DIFF}"

if [ "$DIFF" -eq 1 ]; then
  echo "✅ 장애 복구 후 데이터 동기화 성공"
else
  echo "❌ 데이터 동기화 실패"
fi
```

#### 예상 결과
```
✅ Flink Job 정상 재시작됨
✅ Checkpoint에서 복구됨
✅ 증가량: 1
✅ 장애 복구 후 데이터 동기화 성공
```

## 📊 성능 메트릭 수집

### Flink 메트릭 확인
```bash
# Flink Web UI 접속
open http://localhost:8081

# 확인 항목:
# - Records Sent (Kafka로 전송)
# - Records Received (Kafka에서 수신)
# - Backpressure (역압 상태)
# - Checkpoint Duration (체크포인트 시간)
```

### Kafka Consumer Lag 확인
```bash
docker exec -it kafka kafka-consumer-groups --describe \
  --bootstrap-server localhost:9092 \
  --group flink-sync-connector

# 출력 예시:
# TOPIC              PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# orders-cdc-topic   0          1500            1500            0
# orders-cdc-topic   1          1500            1500            0
# orders-cdc-topic   2          1500            1500            0

# ✅ LAG = 0 (이상적)
# ⚠️ LAG > 100 (처리 지연)
```

### ClickHouse 쿼리 성능
```sql
-- 쿼리 실행 시간 측정
SELECT
    toDate(created_at) AS date,
    count() AS orders,
    sum(total_price) AS revenue
FROM order_analytics.orders_realtime
WHERE created_at >= now() - INTERVAL 7 DAY
  AND operation_type != 'DELETE'
GROUP BY date
ORDER BY date DESC;

-- 실행 시간 확인
-- ✅ < 100ms (최적)
-- ⚠️ 100-500ms (보통)
-- ❌ > 500ms (최적화 필요)
```

## 🔍 데이터 정합성 검증

### 자동화 스크립트
```bash
cat > validate_data_consistency.sh << 'EOF'
#!/bin/bash

echo "=========================================="
echo "데이터 정합성 검증 시작"
echo "=========================================="

# 1. MySQL 전체 카운트
MYSQL_TOTAL=$(docker exec -it mysql mysql -u root -proot_password order_db \
  -se "SELECT COUNT(*) FROM orders")

# 2. ClickHouse 전체 카운트 (DELETE 제외)
CH_TOTAL=$(docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) FROM order_analytics.orders_realtime WHERE operation_type != 'DELETE'")

echo "MySQL 전체 레코드: ${MYSQL_TOTAL}"
echo "ClickHouse 전체 레코드: ${CH_TOTAL}"

# 3. 차이 계산
DIFF=$((MYSQL_TOTAL - CH_TOTAL))

if [ "$DIFF" -eq 0 ]; then
  echo "✅ 데이터 정합성 검증 성공"
  exit 0
elif [ "$DIFF" -le 10 ]; then
  echo "⚠️ 경미한 불일치 (${DIFF}건) - 파이프라인 지연 가능성"
  exit 1
else
  echo "❌ 심각한 불일치 (${DIFF}건) - 조사 필요"
  exit 2
fi
EOF

chmod +x validate_data_consistency.sh
./validate_data_consistency.sh
```

## 🚨 트러블슈팅

### 문제 1: ClickHouse에 데이터 미동기화
```bash
# 1. Flink CDC Job 상태 확인
docker exec -it flink-jobmanager flink list

# 2. Kafka Topic 메시지 확인
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc-topic \
  --from-beginning \
  --max-messages 1

# 3. Flink Sync Job 로그 확인
docker logs flink-taskmanager | grep ERROR

# 4. ClickHouse 연결 테스트
docker exec -it clickhouse-server clickhouse-client --query "SELECT 1"
```

### 문제 2: Consumer Lag 증가
```bash
# 1. Lag 확인
docker exec -it kafka kafka-consumer-groups --describe \
  --bootstrap-server localhost:9092 \
  --group flink-sync-connector

# 2. 원인 분석
# - ClickHouse INSERT 속도 < Kafka Produce 속도
# - Flink Sync Batch 크기 너무 작음
# - TaskManager 리소스 부족

# 3. 해결 방법
# - Batch 크기 증가 (1000 → 5000)
# - Batch Interval 증가 (5초 → 10초)
# - TaskManager 병렬도 증가
```

### 문제 3: 데이터 중복
```bash
# 1. 중복 확인
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT order_id, COUNT(*) AS cnt FROM order_analytics.orders_realtime GROUP BY order_id HAVING cnt > 1"

# 2. 강제 중복 제거 (ReplacingMergeTree)
docker exec -it clickhouse-server clickhouse-client \
  --query "OPTIMIZE TABLE order_analytics.orders_realtime FINAL"

# 3. 최신 레코드만 조회
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT * FROM order_analytics.orders_realtime FINAL WHERE order_id = 1001"
```

## 📈 벤치마크 결과 (MVP 환경)

### 성능 목표
| 메트릭 | 목표 | 실측 |
|--------|------|------|
| End-to-End 지연 | < 5초 | 2-5초 |
| 처리량 | 100-1,000 TPS | 100-500 TPS |
| 데이터 정합성 | 100% | 99.9%+ |
| Consumer Lag | < 100 | 0-50 |
| ClickHouse 쿼리 | < 100ms | 50-100ms |

## 🔄 지속적 모니터링

### Cron Job 설정 (선택적)
```bash
# 매 5분마다 데이터 정합성 검증
*/5 * * * * /path/to/validate_data_consistency.sh >> /var/log/data-validation.log 2>&1

# 매 10분마다 Consumer Lag 확인
*/10 * * * * docker exec kafka kafka-consumer-groups --describe --bootstrap-server localhost:9092 --group flink-sync-connector >> /var/log/kafka-lag.log 2>&1
```

## 📚 다음 단계
- [프로덕션 배포 가이드](../infrastructure/production-deployment.md)
- [성능 최적화 가이드](../infrastructure/performance-tuning.md)
- [장애 대응 매뉴얼](../infrastructure/incident-response.md)
