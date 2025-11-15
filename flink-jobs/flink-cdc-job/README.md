# Flink CDC Job - MySQL to Kafka

MySQL binlog 변경사항을 실시간으로 캡처하여 Kafka로 전송하는 Flink CDC Job입니다.

## 📋 개요

**데이터 흐름:**
```
MySQL binlog → Flink CDC Source → Table Router → Kafka Sink
                                   ↓
                          orders / order_items
                                   ↓
                    orders-cdc-topic / order-items-cdc-topic
```

**주요 기능:**
- MySQL binlog 실시간 변경 캡처 (Debezium 기반)
- 테이블별 라우팅 (orders, order_items)
- Kafka로 CDC 이벤트 전송
- EXACTLY_ONCE 보장 (Checkpoint + Kafka Transaction)
- 장애 자동 복구 (Restart Strategy)

## 🏗️ 아키텍처

### 컴포넌트 구조

```
MySQLCDCJob (Main)
├── CDCSourceConfig      # MySQL CDC Source 설정
├── KafkaSinkConfig      # Kafka Sink 설정
└── TableRouter          # 테이블별 라우팅 필터
```

### CDC 이벤트 구조

```json
{
  "source": {
    "table": "orders",
    "db": "order_db"
  },
  "op": "c",
  "before": null,
  "after": {
    "id": 1,
    "user_id": 100,
    "total_amount": 50000
  }
}
```

## 🚀 빌드 및 실행

### 1. 빌드

```bash
# 프로젝트 루트에서
cd /Users/yeumgw/develop/flink_clickhouse/flink-jobs

# Fat JAR 빌드 (모든 의존성 포함)
./gradlew :flink-cdc-job:shadowJar

# 생성된 JAR 확인
ls -lh flink-cdc-job/build/libs/flink-cdc-job-1.0.0.jar
```

### 2. 로컬 실행 (개발/테스트)

```bash
# Flink standalone 실행
flink run \
  --class com.flink.cdc.job.MySQLCDCJob \
  flink-cdc-job/build/libs/flink-cdc-job-1.0.0.jar
```

### 3. Flink 클러스터 실행 (프로덕션)

```bash
# Detached 모드로 실행
flink run \
  --detached \
  --class com.flink.cdc.job.MySQLCDCJob \
  flink-cdc-job/build/libs/flink-cdc-job-1.0.0.jar

# Job 상태 확인
flink list

# Job 취소
flink cancel <job-id>
```

### 4. Docker Compose 환경 실행

```bash
# 실행 스크립트 사용
./run-cdc-job.sh
```

## ⚙️ 설정

### application.properties

주요 설정값은 `src/main/resources/application.properties`에서 관리합니다.

```properties
# MySQL 연결 정보
mysql.hostname=mysql
mysql.port=3306
mysql.username=flink_cdc
mysql.password=flink_cdc_password

# Kafka 연결 정보
kafka.bootstrap.servers=kafka:9092
kafka.topic.orders=orders-cdc-topic
kafka.topic.order.items=order-items-cdc-topic

# Flink Job 설정
flink.parallelism=2
flink.checkpoint.interval=60000
```

### 환경변수 오버라이드

환경변수로 설정값을 오버라이드할 수 있습니다:

```bash
export MYSQL_HOSTNAME=localhost
export MYSQL_PORT=3306
export KAFKA_BOOTSTRAP_SERVERS=localhost:9092
export FLINK_PARALLELISM=4
```

## 🧪 테스트

### 단위 테스트 실행

```bash
# 전체 테스트 실행
./gradlew :flink-cdc-job:test

# 특정 테스트 클래스 실행
./gradlew :flink-cdc-job:test --tests TableRouterTest

# 테스트 리포트 확인
open flink-cdc-job/build/reports/tests/test/index.html
```

### 코드 품질 검사

```bash
# Checkstyle 실행
./gradlew :flink-cdc-job:checkstyleMain

# 전체 검증 (테스트 + Checkstyle)
./gradlew :flink-cdc-job:check
```

## 📊 모니터링

### Flink Web UI

Flink 클러스터가 실행 중일 때:
```
http://localhost:8081
```

**확인 사항:**
- Job 상태 (RUNNING, FAILED, CANCELED)
- Checkpoint 성공률
- 백프레셔 (Backpressure) 지표
- Task Manager 리소스 사용률

### 로그 확인

```bash
# 애플리케이션 로그
tail -f logs/flink-cdc-job.log

# 에러 로그
tail -f logs/flink-cdc-job-error.log

# Flink TaskManager 로그
tail -f $FLINK_HOME/log/flink-*-taskexecutor-*.log
```

## 🔧 트러블슈팅

### 자주 발생하는 문제

#### 1. MySQL 연결 실패
```
Error: Could not connect to MySQL
```
**해결책:**
- MySQL이 실행 중인지 확인
- flink_cdc 사용자 권한 확인: `GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'flink_cdc'@'%';`
- binlog 활성화 확인: `show variables like 'log_bin';`

#### 2. Kafka 연결 실패
```
Error: Failed to send data to Kafka
```
**해결책:**
- Kafka가 실행 중인지 확인
- 토픽이 생성되어 있는지 확인: `kafka-topics.sh --list`
- 네트워크 연결 확인

#### 3. Checkpoint 실패
```
Error: Checkpoint expired before completing
```
**해결책:**
- Checkpoint timeout 증가: `flink.checkpoint.timeout=900000` (15분)
- 병렬도 감소: `flink.parallelism=1`
- Kafka transaction timeout 증가: `kafka.transaction.timeout.ms=900000`

#### 4. OOM (Out of Memory)
```
Error: java.lang.OutOfMemoryError
```
**해결책:**
- TaskManager 메모리 증가
- 병렬도 감소
- State 크기 모니터링

## 📦 의존성

주요 라이브러리 버전:

- **Flink**: 1.18.0
- **Flink CDC MySQL Connector**: 3.0.1
- **Kafka Connector**: 3.0.2-1.18
- **Jackson**: 2.15.0
- **Log4j**: 2.20.0

## 🔐 보안 고려사항

1. **MySQL 사용자 권한 최소화**
   - REPLICATION SLAVE, REPLICATION CLIENT만 부여
   - 특정 데이터베이스로 제한

2. **Kafka 보안**
   - SASL/SSL 설정 (프로덕션 환경)
   - ACL 설정으로 토픽 접근 제어

3. **민감 정보 관리**
   - 패스워드 환경변수 또는 Secret Manager 사용
   - application.properties에 평문 저장 금지

## 📚 참고 문서

- [Flink CDC Connectors](https://github.com/ververica/flink-cdc-connectors)
- [Flink Kafka Connector](https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/datastream/kafka/)
- [Debezium MySQL Connector](https://debezium.io/documentation/reference/stable/connectors/mysql.html)

## 👥 개발자 정보

**Package:** `com.flink.cdc`

**Main Class:** `com.flink.cdc.job.MySQLCDCJob`

**Version:** 1.0.0
