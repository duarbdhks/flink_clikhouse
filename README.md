# MVP 주문 서비스 - 실시간 CDC 파이프라인

## 📋 프로젝트 개요
MySQL 주문 데이터를 실시간으로 ClickHouse에 동기화하는 CDC 기반 데이터 파이프라인 MVP

**핵심 목적**: Flink CDC + Kafka + ClickHouse 연동 구성 테스트

## 🏗️ 아키텍처

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────────────┐
│   MySQL     │────▶│  Flink CDC   │────▶│    Kafka     │────▶│ Flink Sync   │────▶│  ClickHouse     │
│ (Source DB) │     │     Job      │     │  (KRaft)     │     │  Connector   │     │ (Analytics DB)  │
└─────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └─────────────────┘
     binlog             CDC Events           Stream             Transform              Real-time OLAP
```

## 🎯 기술 스택

### 데이터베이스
- **MySQL 8.0**: 주문 데이터 소스 (binlog 활성화)
- **ClickHouse 23.8**: 실시간 분석용 OLAP 데이터베이스

### 스트리밍 처리
- **Apache Flink 1.18**: CDC 및 Sync Connector Job
- **Flink CDC Connector**: MySQL binlog 실시간 캡처 (Debezium 없이 Flink만 사용)
- **ClickHouse Native Sink**: ClickHouse 공식 Flink Connector (JDBC 대비 2배 빠름)
- **Confluent Kafka 7.6**: KRaft 모드 메시지 큐 (Zookeeper 불필요)

### 애플리케이션 (Optional)
- **NestJS**: 주문 관리 API
- **HTML**: 간단한 주문 생성 폼

### 인프라
- **Docker Compose**: 전체 인프라 통합 관리

## 🚀 빠른 시작

### 1. 사전 요구사항
```bash
# Docker 및 Docker Compose 설치 확인
docker --version        # 20.10.0+
docker-compose --version  # 1.29.0+

# 최소 리소스
# - RAM: 8GB 이상
# - Disk: 10GB 여유 공간
```

### 2. 프로젝트 클론
```bash
git clone https://github.com/your-repo/flink_clickhouse.git
cd flink_clickhouse
```

### 3. 초기화 스크립트 생성
```bash
# MySQL 초기화 스크립트
mkdir -p init-scripts
cp claudedocs/infrastructure/deployment-guide.md init-scripts/README.md

# init-mysql.sql 생성 (deployment-guide.md 참조)
# init-clickhouse.sql 생성 (deployment-guide.md 참조)
```

### 4. 전체 인프라 시작
```bash
# 모든 서비스 시작
docker-compose up -d

# 서비스 상태 확인
docker-compose ps

# 로그 확인
docker-compose logs -f
```

### 5. Kafka Topic 생성
```bash
docker exec -it kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc-topic \
  --partitions 3 \
  --replication-factor 1
```

### 6. Flink Job 제출
```bash
# CDC Job 제출
docker exec -it flink-jobmanager flink run \
  -d -c com.example.cdc.MySQLCDCJob \
  /opt/flink/jobs/mysql-cdc-job.jar

# Sync Connector Job 제출
docker exec -it flink-jobmanager flink run \
  -d -c com.example.sync.KafkaToClickHouseJob \
  /opt/flink/jobs/kafka-clickhouse-sync-job.jar
```

### 7. 검증
```bash
# MySQL에 테스트 데이터 삽입
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "INSERT INTO orders (user_id, product_name, quantity, total_price) VALUES (100, 'Test Product', 1, 50.00)"

# ClickHouse에서 확인 (5초 후)
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT * FROM order_analytics.orders_realtime ORDER BY created_at DESC LIMIT 10"
```

## 📚 문서 구조

```
claudedocs/
├── pipeline/                           # 핵심 파이프라인 문서
│   ├── 01-architecture-overview.md     ⭐ 전체 아키텍처 개요
│   ├── 02-flink-cdc-mysql.md          ⭐ Flink CDC 설정
│   ├── 03-confluent-kafka.md          ⭐ Kafka 구성 (KRaft)
│   ├── 04-flink-sync-connector.md     ⭐ Kafka → ClickHouse Sync
│   └── 05-clickhouse-schema.md        ⭐ ClickHouse 스키마
├── infrastructure/
│   └── deployment-guide.md            ⭐ Docker Compose 배포 가이드
└── testing/
    └── pipeline-validation.md         ⭐ E2E 테스트 가이드
```

## 🔍 주요 문서

### 필수 읽기 (순서대로)
1. **[아키텍처 개요](claudedocs/pipeline/01-architecture-overview.md)** - 전체 구조 이해
2. **[배포 가이드](claudedocs/infrastructure/deployment-guide.md)** - 인프라 구축
3. **[E2E 테스트](claudedocs/testing/pipeline-validation.md)** - 검증 방법

### 상세 설정
4. **[Flink CDC MySQL](claudedocs/pipeline/02-flink-cdc-mysql.md)** - CDC 상세 구성
5. **[Confluent Kafka](claudedocs/pipeline/03-confluent-kafka.md)** - Kafka 설정
6. **[Flink Sync Connector](claudedocs/pipeline/04-flink-sync-connector.md)** - ClickHouse 동기화
7. **[ClickHouse 스키마](claudedocs/pipeline/05-clickhouse-schema.md)** - 분석 테이블 설계

## 🖥️ 모니터링 UI

### Web 인터페이스
- **Flink Dashboard**: http://localhost:8081
- **Kafka UI**: http://localhost:8080
- **ClickHouse Play**: http://localhost:8123/play

### CLI 접속
```bash
# MySQL 클라이언트
docker exec -it mysql mysql -u root -proot_password

# ClickHouse 클라이언트
docker exec -it clickhouse-server clickhouse-client

# Kafka Console Consumer
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc-topic \
  --from-beginning
```

## 📊 성능 메트릭

### MVP 목표 (소규모 트래픽: 일 100-1,000건)
| 메트릭 | 목표값 |
|--------|--------|
| End-to-End 지연 시간 | < 5초 |
| 처리량 | 100-1,000 TPS |
| 데이터 정합성 | 100% |
| Consumer Lag | < 100 |
| ClickHouse 쿼리 성능 | < 100ms |

## 🧪 테스트 실행

### 기본 데이터 흐름 테스트
```bash
# 1. MySQL INSERT
docker exec -it mysql mysql -u root -proot_password order_db \
  -e "INSERT INTO orders (user_id, product_name, quantity, total_price) VALUES (500, 'Laptop', 1, 1500.00)"

# 2. Kafka 확인 (2초 후)
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc-topic \
  --max-messages 1

# 3. ClickHouse 확인 (5초 후)
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT * FROM order_analytics.orders_realtime WHERE user_id = 500"
```

### 대량 데이터 테스트
```bash
# 100건 삽입
for i in {1..100}; do
  docker exec -it mysql mysql -u root -proot_password order_db \
    -e "INSERT INTO orders (user_id, product_name, quantity, total_price) VALUES ($((1000+i)), 'Product $i', 1, 100.00)"
done

# 데이터 정합성 검증 (30초 후)
# MySQL 카운트
docker exec -it mysql mysql -u root -proot_password order_db \
  -se "SELECT COUNT(*) FROM orders WHERE user_id >= 1001"

# ClickHouse 카운트
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) FROM order_analytics.orders_realtime WHERE user_id >= 1001 AND operation_type != 'DELETE'"
```

## 🛠️ 트러블슈팅

### 일반적인 문제

#### 1. 서비스 시작 실패
```bash
# 로그 확인
docker-compose logs <service-name>

# 컨테이너 재시작
docker-compose restart <service-name>

# 전체 재시작
docker-compose down
docker-compose up -d
```

#### 2. 데이터 동기화 안 됨
```bash
# Flink Job 상태 확인
docker exec -it flink-jobmanager flink list

# Kafka Consumer Lag 확인
docker exec -it kafka kafka-consumer-groups --describe \
  --bootstrap-server localhost:9092 \
  --group flink-sync-connector

# ClickHouse 연결 테스트
docker exec -it clickhouse-server clickhouse-client --query "SELECT 1"
```

#### 3. 포트 충돌
```bash
# 포트 사용 확인
lsof -i :3306   # MySQL
lsof -i :9092   # Kafka
lsof -i :8123   # ClickHouse

# docker-compose.yml에서 포트 변경
# 예: "13306:3306"
```

## 🛑 중지 및 정리

### 서비스 중지
```bash
# 중지 (데이터 유지)
docker-compose stop

# 중지 및 컨테이너 삭제 (데이터 유지)
docker-compose down

# 모든 데이터 삭제
docker-compose down -v
```

### 디스크 정리
```bash
# 사용하지 않는 리소스 정리
docker system prune -a --volumes
```

## 📈 다음 단계

### MVP 완료 후
- [ ] **프로덕션 배포**: Kubernetes 환경 마이그레이션
- [ ] **성능 최적화**: Partition 증가, Batch 튜닝
- [ ] **모니터링 강화**: Prometheus + Grafana
- [ ] **고가용성 구성**: Flink HA, Kafka 클러스터
- [ ] **백업 및 복구**: 데이터 백업 전략 수립

### 추가 기능
- [ ] **실시간 대시보드**: React + ClickHouse 연동
- [ ] **알림 시스템**: 이상 탐지 및 알림
- [ ] **데이터 품질 검증**: dbt 또는 Great Expectations
- [ ] **ML 파이프라인**: 매출 예측 모델 연동

## 🤝 기여

이 프로젝트는 MVP 테스트 목적으로 제작되었습니다. 개선 사항이나 버그는 Issue를 통해 공유해주세요.

## 📄 라이선스

MIT License

**Made with ❤️ for CDC Pipeline Testing**
