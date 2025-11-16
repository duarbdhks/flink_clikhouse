# 배포 가이드 (Docker Compose)

## 📋 개요
전체 데이터 파이프라인을 Docker Compose로 로컬 환경에 배포하는 가이드

## 🎯 배포 구성
```
MySQL (Source DB)
    ↓
Flink CDC Job
    ↓
Kafka (KRaft Mode)
    ↓
Flink Sync Connector Job
    ↓
ClickHouse (Analytics DB)
```

## 📦 사전 요구사항

### 1. 소프트웨어 설치
```bash
# Docker 및 Docker Compose 설치 확인
docker --version       # Docker version 20.10.0+
docker-compose --version  # docker-compose version 1.29.0+

# 메모리 확인 (최소 8GB 권장)
free -h

# 디스크 공간 확인 (최소 10GB 여유 공간)
df -h
```

### 2. 프로젝트 구조
```
flink_clickhouse/
├── docker-compose.yml
├── init-scripts/
│   ├── init-mysql.sql
│   └── init-clickhouse.sql
├── flink-jobs/
│   ├── mysql-cdc-job.jar
│   └── kafka-clickhouse-sync-job.jar
└── claudedocs/
    ├── pipeline/
    └── infrastructure/
```

## 🚀 배포 단계

### Step 1: 초기화 스크립트 준비

#### init-mysql.sql 생성
```bash
mkdir -p init-scripts
cat > init-scripts/init-mysql.sql << 'EOF'
-- CDC 사용자 생성
CREATE USER 'cdc'@'%' IDENTIFIED BY 'cdc_password_123';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT
ON *.* TO 'cdc'@'%';
FLUSH PRIVILEGES;

-- 주문 데이터베이스 및 테이블 생성
USE order_db;

CREATE TABLE orders (
    order_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    quantity INT NOT NULL,
    total_price DECIMAL(10, 2) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE order_items (
    item_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    subtotal DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    INDEX idx_order_id (order_id),
    INDEX idx_product_id (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 샘플 데이터 삽입
INSERT INTO orders (user_id, product_name, quantity, total_price, status)
VALUES
    (100, 'Laptop', 1, 1500.00, 'pending'),
    (101, 'Mouse', 2, 50.00, 'completed'),
    (102, 'Keyboard', 1, 80.00, 'pending'),
    (103, 'Monitor', 1, 300.00, 'completed'),
    (104, 'Headphones', 1, 120.00, 'pending');
EOF
```

#### init-clickhouse.sql 생성
```bash
cat > init-scripts/init-clickhouse.sql << 'EOF'
CREATE DATABASE IF NOT EXISTS order_analytics;

USE order_analytics;

CREATE TABLE IF NOT EXISTS orders_realtime (
    order_id UInt64,
    user_id UInt64,
    product_name String,
    quantity UInt32,
    total_price Decimal(10, 2),
    status LowCardinality(String),
    created_at DateTime,
    updated_at DateTime,
    operation_type LowCardinality(String),
    event_timestamp UInt64,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(event_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (order_id, event_timestamp)
SETTINGS index_granularity = 8192;

-- 일별 집계 뷰
CREATE MATERIALIZED VIEW orders_daily_summary
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(sale_date)
ORDER BY (sale_date, status)
AS
SELECT
    toDate(created_at) AS sale_date,
    status,
    count() AS order_count,
    sum(total_price) AS daily_revenue,
    avg(total_price) AS avg_order_value,
    uniq(user_id) AS unique_customers
FROM orders_realtime
WHERE operation_type != 'DELETE'
GROUP BY sale_date, status;

-- 시간대별 통계 뷰
CREATE MATERIALIZED VIEW orders_hourly_stats
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(order_hour)
ORDER BY (order_hour, status)
AS
SELECT
    toStartOfHour(created_at) AS order_hour,
    status,
    countState() AS order_count,
    sumState(total_price) AS hourly_revenue,
    avgState(total_price) AS avg_order_value,
    uniqState(user_id) AS unique_customers
FROM orders_realtime
WHERE operation_type != 'DELETE'
GROUP BY order_hour, status;
EOF
```

### Step 2: Kafka Topic 생성 스크립트

```bash
cat > init-scripts/create-kafka-topics.sh << 'EOF'
#!/bin/bash

# Kafka가 준비될 때까지 대기
sleep 10

# Topic 생성
docker exec -it kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=604800000

docker exec -it kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic order-items-cdc \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=604800000

echo "✅ Kafka Topics created successfully"
EOF

chmod +x init-scripts/create-kafka-topics.sh
```

### Step 3: 인프라 시작

#### 3.1 전체 서비스 시작
```bash
# 백그라운드에서 모든 서비스 시작
docker-compose up -d

# 로그 확인
docker-compose logs -f
```

#### 3.2 개별 서비스 시작 (선택적)
```bash
# 데이터베이스만 먼저 시작
docker-compose up -d mysql clickhouse kafka

# 상태 확인
docker-compose ps

# Flink 나중에 시작
docker-compose up -d flink-jobmanager flink-taskmanager
```

### Step 4: 헬스체크 확인

```bash
# 모든 서비스 상태 확인
docker-compose ps

# 개별 서비스 헬스체크
docker exec -it mysql mysqladmin ping -h localhost
docker exec -it clickhouse-server clickhouse-client --query "SELECT 1"
docker exec -it kafka kafka-broker-api-versions --bootstrap-server localhost:9092
curl http://localhost:8081  # Flink Web UI
```

### Step 5: Kafka Topic 생성

```bash
# Topic 생성 스크립트 실행
./init-scripts/create-kafka-topics.sh

# Topic 확인
docker exec -it kafka kafka-topics --list --bootstrap-server localhost:9092
```

### Step 6: Flink Job 배포

#### 6.1 CDC Job 제출
```bash
# Flink Job 디렉토리에 JAR 파일 복사
cp /path/to/mysql-cdc-job.jar ./flink-jobs/

# JobManager에 Job 제출
docker exec -it flink-jobmanager flink run \
  -d \
  -c com.example.cdc.MySQLCDCJob \
  /opt/flink/jobs/mysql-cdc-job.jar

# Job 상태 확인
docker exec -it flink-jobmanager flink list
```

#### 6.2 Sync Connector Job 제출
```bash
# Sync Connector JAR 복사
cp /path/to/kafka-clickhouse-sync-job.jar ./flink-jobs/

# Job 제출
docker exec -it flink-jobmanager flink run \
  -d \
  -c com.example.sync.KafkaToClickHouseJob \
  /opt/flink/jobs/kafka-clickhouse-sync-job.jar

# Job 목록 확인
docker exec -it flink-jobmanager flink list
```

## 🔍 검증

### 1. MySQL 데이터 확인
```bash
docker exec -it mysql mysql -u root -p
# Password: test123

USE order_db;
SELECT * FROM orders LIMIT 5;
```

### 2. Kafka Topic 메시지 확인
```bash
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc \
  --from-beginning \
  --max-messages 5
```

### 3. ClickHouse 데이터 확인
```bash
docker exec -it clickhouse-server clickhouse-client

SELECT * FROM order_analytics.orders_realtime
ORDER BY created_at DESC
LIMIT 10;
```

### 4. End-to-End 테스트
```bash
# 1. MySQL에 새 주문 삽입
docker exec -it mysql mysql -u root -p order_db \
  -e "INSERT INTO orders (user_id, product_name, quantity, total_price) VALUES (200, 'Test Product', 1, 100.00);"

# 2. Kafka에서 CDC 이벤트 확인 (1-2초 후)
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc \
  --max-messages 1

# 3. ClickHouse에서 데이터 확인 (3-7초 후)
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT * FROM order_analytics.orders_realtime WHERE user_id = 200"
```

## 📊 모니터링

### Web UI 접속
- **Flink Dashboard**: http://localhost:8081
- **Kafka UI**: http://localhost:8080
- **ClickHouse**: http://localhost:8123/play

### 로그 확인
```bash
# 전체 로그
docker-compose logs -f

# 특정 서비스 로그
docker-compose logs -f mysql
docker-compose logs -f kafka
docker-compose logs -f flink-jobmanager
docker-compose logs -f clickhouse
```

### 리소스 사용량 확인
```bash
# 컨테이너 리소스 모니터링
docker stats

# 특정 컨테이너 상세 정보
docker inspect flink-jobmanager
```

## 🛑 중지 및 재시작

### 서비스 중지
```bash
# 모든 서비스 중지 (데이터 유지)
docker-compose stop

# 모든 서비스 중지 및 제거
docker-compose down

# 볼륨까지 모두 삭제 (데이터 삭제)
docker-compose down -v
```

### 서비스 재시작
```bash
# 전체 재시작
docker-compose restart

# 특정 서비스만 재시작
docker-compose restart kafka
docker-compose restart flink-jobmanager
```

## 🧹 클린업

### 전체 정리
```bash
# 컨테이너, 네트워크, 볼륨 모두 삭제
docker-compose down -v

# 사용하지 않는 이미지 정리
docker image prune -a

# 사용하지 않는 볼륨 정리
docker volume prune
```

## 🚨 트러블슈팅

### 문제 1: 포트 충돌
```bash
# 포트 사용 확인
lsof -i :3306  # MySQL
lsof -i :9092  # Kafka
lsof -i :8123  # ClickHouse
lsof -i :8081  # Flink

# 해결: docker-compose.yml에서 포트 변경
# 예: "13306:3306" (호스트:컨테이너)
```

### 문제 2: 메모리 부족
```bash
# Docker 메모리 설정 확인
docker info | grep Memory

# 해결: Docker Desktop 설정에서 메모리 증가
# Docker Desktop → Preferences → Resources → Memory: 8GB+
```

### 문제 3: Flink Job 실패
```bash
# Job 로그 확인
docker-compose logs flink-jobmanager
docker-compose logs flink-taskmanager

# Job 상태 확인
docker exec -it flink-jobmanager flink list

# Job 취소
docker exec -it flink-jobmanager flink cancel <JOB_ID>
```

### 문제 4: Kafka 연결 실패
```bash
# Kafka 상태 확인
docker exec -it kafka kafka-broker-api-versions --bootstrap-server localhost:9092

# 네트워크 확인
docker network inspect flink_clickhouse_cdc-network

# 해결: 컨테이너 재시작
docker-compose restart kafka
```

## 📈 성능 튜닝

### Flink 성능 최적화
```yaml
# docker-compose.yml에서 TaskManager 리소스 증가
flink-taskmanager:
  environment:
    FLINK_PROPERTIES: |
      taskmanager.numberOfTaskSlots: 8
      taskmanager.memory.process.size: 2048m
  scale: 2  # TaskManager 개수 증가
```

### Kafka 처리량 증가
```yaml
kafka:
  environment:
    KAFKA_NUM_PARTITIONS: 6  # Partition 수 증가
    KAFKA_HEAP_OPTS: "-Xmx1G -Xms1G"
```

### ClickHouse 최적화
```yaml
clickhouse:
  environment:
    CLICKHOUSE_MAX_MEMORY_USAGE: 4000000000  # 4GB
```

## 🔐 보안 설정 (프로덕션 환경)

### 비밀번호 변경
```bash
# .env 파일 생성
cat > .env << EOF
MYSQL_ROOT_PASSWORD=your_secure_password
MYSQL_PASSWORD=your_app_password
CLICKHOUSE_PASSWORD=your_clickhouse_password
EOF

# docker-compose.yml에서 환경변수 참조
# ${MYSQL_ROOT_PASSWORD}
```

### 네트워크 격리
```yaml
networks:
  cdc-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.25.0.0/16
```

## 📚 다음 단계
- [파이프라인 E2E 테스트](../testing/pipeline-validation.md)
- [NestJS Order Service 설정](../order-service/api-spec.md)
- [프로덕션 배포 가이드](./production-deployment.md)
