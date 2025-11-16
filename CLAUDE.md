# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

MySQL 데이터를 실시간으로 ClickHouse에 동기화하는 CDC 기반 데이터 파이프라인 MVP 프로젝트입니다.

**핵심 아키텍처**: MySQL → Flink CDC → Kafka → Flink Sync → ClickHouse

## 개발 환경 설정

### 필수 요구사항
- Docker & Docker Compose (20.10.0+)
- Node.js 18+ (NestJS API 개발용)
- Java 11+ & Gradle 8+ (Flink Jobs 개발용)

### 초기 설정
```bash
# 전체 시스템 원스톱 초기화
bash docker/init/setup-all.sh

# 또는 수동 초기화
docker-compose up -d mysql clickhouse kafka
docker exec -i mysql mysql -uroot -ptest123 < docker/init/sql/init-mysql.sql
docker exec -i clickhouse clickhouse-client --multiquery < docker/init/sql/init-clickhouse.sql
bash docker/init/kafka/create-topics.sh
```

## 프로젝트 구조

### NestJS Platform Service (`platform-service/`)
주문 데이터를 관리하는 REST API 서버 (완성됨)

**주요 모듈**:
- `orders/`: 주문 생성/조회 (Orders, OrderItems 엔티티)
- `users/`: 사용자 관리
- `products/`: 상품 관리
- `database/`: TypeORM MySQL 연결 설정

**실행 명령어**:
```bash
cd platform-service
npm install
npm run start:dev      # 개발 모드 (핫 리로드)
npm run start:prod     # 프로덕션 모드
npm run lint           # ESLint 검사
npm run format         # Prettier 포맷팅
```

**API 문서**: http://localhost:3000/api/docs (Swagger)

### Flink Jobs (`flink-jobs/`)
Gradle 멀티모듈 프로젝트 (구현 완료)

**모듈 구조**:
- `common/`: 공통 유틸리티 (현재 사용 안 함)
- `flink-cdc-job/`: MySQL CDC → Kafka Job (구현 완료)
- `flink-sync-job/`: Kafka → ClickHouse Sync Job (구현 완료)

**빌드 명령어**:
```bash
cd flink-jobs
./gradlew build                              # 전체 빌드
./gradlew :flink-cdc-job:shadowJar          # CDC Job Fat JAR 생성
./gradlew :flink-sync-job:shadowJar         # Sync Job Fat JAR 생성
./gradlew test                              # 테스트 실행
```

**Job 제출**:
```bash
# CDC Job 제출
docker exec -it yeumgw-flink-jobmanager flink run -d \
  -c com.flink.cdc.job.MySQLCDCJob \
  /opt/flink/jobs/jars/flink-cdc-job.jar

# Sync Job 제출
docker exec -it yeumgw-flink-jobmanager flink run -d \
  -c com.flink.sync.job.KafkaToClickHouseJob \
  /opt/flink/jobs/jars/flink-sync-job.jar
```

## 아키텍처 핵심 개념

### CDC 파이프라인 흐름
1. **MySQL binlog → Flink CDC**: MySQL의 변경사항을 실시간 캡처 (Debezium 기반)
2. **Flink CDC → Kafka**: CDC 이벤트를 테이블별 토픽으로 라우팅
   - 토픽: `orders-cdc`, `order_items-cdc`, `users-cdc`, `products-cdc`
3. **Kafka → Flink Sync**: Kafka 메시지를 구독하여 변환
4. **Flink Sync → ClickHouse**: ClickHouse Native Sink로 실시간 삽입

### 주요 기술 선택 이유
- **Flink CDC Connector 3.0.1**: Debezium 기반으로 MySQL binlog 실시간 읽기 지원
- **ClickHouse Native Sink**: JDBC 대비 2배 빠른 성능
- **Confluent Kafka KRaft 모드**: Zookeeper 불필요, 단순한 구성
- **TypeORM + NestJS**: 타입 안전성과 빠른 API 개발

## 데이터베이스 스키마

### MySQL (`order_db`)
- `users`: 사용자 (id, name, email)
- `products`: 상품 (id, name, price, stock)
- `orders`: 주문 (id, user_id, status, total_amount)
- `order_items`: 주문 상품 (id, order_id, product_id, quantity, price)

### ClickHouse (`order_analytics`)
- `orders_realtime`: 주문 실시간 분석 테이블 (MergeTree)
  - CDC 메타데이터 포함: `operation_type`, `event_time`
  - Materialized View로 집계 뷰 지원

## 테스트 및 검증

### End-to-End 테스트
```bash
# 1. API를 통한 주문 생성
curl -X POST http://localhost:3000/api/orders \
  -H "Content-Type: application/json" \
  -d '{"userId": 100, "items": [{"productId": 1001, "productName": "Test", "quantity": 1, "price": 50.00}]}'

# 2. MySQL 확인
docker exec -it yeumgw-mysql mysql -uroot -ptest123 order_db \
  -e "SELECT * FROM orders ORDER BY id DESC LIMIT 1"

# 3. Kafka 확인 (2-3초 후)
docker exec -it yeumgw-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc --max-messages 1

# 4. ClickHouse 확인 (5초 후)
docker exec -it yeumgw-clickhouse-server clickhouse-client \
  --query "SELECT * FROM order_analytics.orders_realtime ORDER BY created_at DESC LIMIT 5"
```

### 모니터링
- **Flink Dashboard**: http://localhost:8081
- **Kafka UI**: http://localhost:8080
- **ClickHouse Play**: http://localhost:8123/play
- **API Swagger**: http://localhost:3000/api/docs

## 코드 수정 시 주의사항

### NestJS (platform-service)
- **엔티티 수정**: `*.entity.ts` 변경 시 TypeORM 자동 동기화 (`synchronize: true`)
- **DTO 검증**: `class-validator` 데코레이터로 요청 검증 필수
- **Swagger**: `@ApiProperty()` 데코레이터로 API 문서 자동 생성
- **에러 처리**: NestJS 내장 예외 사용 (`NotFoundException`, `BadRequestException`)

### Flink Jobs (Java)
- **CDC 소스 테이블 추가**: `CDCSourceConfig.java`에 테이블 목록 추가
- **토픽 라우팅**: `TableRouter.java`의 `OperationTableRouter` 구현 확인
- **ClickHouse 스키마 변경**: `ClickHouseSink.java`의 `OrdersStatementBuilder` 수정
- **설정 변경**: `application.properties`에서 DB/Kafka 연결 정보 관리

### Docker Compose
- **MySQL binlog 필수**: `--log-bin`, `--binlog-format=ROW` 설정 유지
- **포트 충돌**: 로컬 MySQL/Kafka와 충돌 시 포트 변경 (예: `13306:3306`)
- **볼륨 초기화**: 데이터 전체 삭제 시 `docker-compose down -v`

## 트러블슈팅

### Flink Job 실패
```bash
# Job 상태 확인
docker exec -it yeumgw-flink-jobmanager flink list

# Job 로그 확인
docker logs yeumgw-flink-taskmanager

# Job 취소 후 재시작
docker exec -it yeumgw-flink-jobmanager flink cancel <job-id>
```

### Kafka Consumer Lag
```bash
# Consumer Group 상태 확인
docker exec -it yeumgw-kafka kafka-consumer-groups \
  --describe --bootstrap-server localhost:9092 \
  --group flink-sync-connector
```

### ClickHouse 연결 실패
```bash
# ClickHouse 연결 테스트
docker exec -it yeumgw-clickhouse-server clickhouse-client --query "SELECT 1"

# 테이블 존재 확인
docker exec -it yeumgw-clickhouse-server clickhouse-client \
  --query "SHOW TABLES FROM order_analytics"
```

## 참고 문서

상세한 기술 문서는 `claudedocs/` 디렉토리 참조:
- `pipeline/01-architecture-overview.md`: 전체 아키텍처 개요
- `pipeline/02-flink-cdc-mysql.md`: Flink CDC 상세 설정
- `pipeline/03-confluent-kafka.md`: Kafka 구성
- `pipeline/04-flink-sync-connector.md`: ClickHouse 동기화
- `pipeline/05-clickhouse-schema.md`: 분석 테이블 설계
- `infrastructure/deployment-guide.md`: Docker Compose 배포
- `testing/pipeline-validation.md`: E2E 테스트 가이드

## 성능 목표 (MVP)
- End-to-End 지연시간: < 5초
- 처리량: 100-1,000 TPS
- 데이터 정합성: 100%
- ClickHouse 쿼리: < 100ms
