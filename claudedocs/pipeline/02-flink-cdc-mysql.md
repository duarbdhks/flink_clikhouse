# Flink CDC MySQL 설정

## 📋 개요
MySQL Binlog를 실시간으로 캡처하여 Kafka로 전송하는 Flink CDC Job 구성 가이드

## 🎯 구성 요소
```
MySQL (binlog enabled)
    ↓
Flink CDC Connector
    ↓
Kafka Topic (orders-cdc-topic)
```

## 📦 필요한 의존성

### Maven 의존성 (pom.xml)
```xml
<dependencies>
    <!-- Flink Core -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-streaming-java</artifactId>
        <version>1.18.0</version>
    </dependency>

    <!-- Flink CDC MySQL Connector -->
    <dependency>
        <groupId>com.ververica</groupId>
        <artifactId>flink-connector-mysql-cdc</artifactId>
        <version>3.0.1</version>
    </dependency>

    <!-- Flink Kafka Connector -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-connector-kafka</artifactId>
        <version>3.0.2-1.18</version>
    </dependency>

    <!-- JSON Serialization -->
    <dependency>
        <groupId>com.fasterxml.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>2.15.2</version>
    </dependency>

    <!-- MySQL JDBC Driver -->
    <dependency>
        <groupId>mysql</groupId>
        <artifactId>mysql-connector-java</artifactId>
        <version>8.0.33</version>
    </dependency>
</dependencies>
```

## 🔧 MySQL 설정

### 1. Binlog 활성화 (my.cnf 또는 docker-compose 환경변수)
```ini
[mysqld]
# Binlog 설정
server-id = 1
log_bin = mysql-bin
binlog_format = ROW
binlog_row_image = FULL
expire_logs_days = 7

# 선택적: 특정 데이터베이스만 binlog 기록
# binlog-do-db = order_db
```

### 2. CDC 전용 사용자 생성
```sql
-- CDC 사용자 생성
CREATE USER 'flink_cdc'@'%' IDENTIFIED BY 'cdc_password_123';

-- 필요한 권한 부여
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT
ON *.* TO 'flink_cdc'@'%';

-- 권한 적용
FLUSH PRIVILEGES;
```

### 3. 플랫폼 데이터베이스 및 테이블 생성
```sql
CREATE DATABASE IF NOT EXISTS order_db;
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
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

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
  INDEX idx_category (category),
  INDEX idx_price (price),
  INDEX idx_name (name)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- orders 테이블
CREATE TABLE IF NOT EXISTS orders (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '주문 ID',
  user_id      BIGINT         NOT NULL COMMENT '사용자 ID',
  status       VARCHAR(20)    NOT NULL DEFAULT 'PENDING' COMMENT '주문 상태',
  total_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00 COMMENT '총 주문 금액',
  order_date   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '주문 생성 일시',
  updated_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '마지막 수정 일시',
  INDEX idx_user_id (user_id),
  INDEX idx_status (status),
  INDEX idx_order_date (order_date)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- order_items 테이블
CREATE TABLE IF NOT EXISTS order_items (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '주문 항목 ID',
  order_id     BIGINT         NOT NULL COMMENT '주문 ID (FK)',
  product_id   BIGINT         NOT NULL COMMENT '상품 ID',
  product_name VARCHAR(255)   NOT NULL COMMENT '상품명',
  quantity     INT            NOT NULL DEFAULT 1 COMMENT '수량',
  price        DECIMAL(10, 2) NOT NULL COMMENT '단가',
  subtotal     DECIMAL(10, 2) NOT NULL COMMENT '소계',
  created_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 일시',
  FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
  INDEX idx_order_id (order_id),
  INDEX idx_product_id (product_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
```

## 🚀 Flink CDC Job 구현

### Job 구조
```
src/main/java/com/example/cdc/
├── MySQLCDCJob.java              (메인 Job)
├── config/
│   └── CDCConfig.java            (설정 클래스)
├── serializer/
│   └── OrderEventSerializer.java (Kafka 직렬화)
└── model/
    └── OrderEvent.java           (데이터 모델)
```

### 1. 데이터 모델 (OrderEvent.java)
```java
package com.example.cdc.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.math.BigDecimal;
import java.time.LocalDateTime;

public class OrderEvent {
    @JsonProperty("order_id")
    private Long orderId;

    @JsonProperty("user_id")
    private Long userId;

    @JsonProperty("product_name")
    private String productName;

    @JsonProperty("quantity")
    private Integer quantity;

    @JsonProperty("total_price")
    private BigDecimal totalPrice;

    @JsonProperty("status")
    private String status;

    @JsonProperty("created_at")
    private LocalDateTime createdAt;

    @JsonProperty("updated_at")
    private LocalDateTime updatedAt;

    @JsonProperty("operation")
    private String operation; // INSERT, UPDATE, DELETE

    @JsonProperty("event_timestamp")
    private Long eventTimestamp;

    // Getters and Setters
    // ... (생략)
}
```

### 2. CDC 설정 클래스 (CDCConfig.java)
```java
package com.example.cdc.config;

public class CDCConfig {
    // MySQL 설정
    public static final String MYSQL_HOST = System.getenv().getOrDefault("MYSQL_HOST", "mysql");
    public static final int MYSQL_PORT = Integer.parseInt(System.getenv().getOrDefault("MYSQL_PORT", "3306"));
    public static final String MYSQL_DATABASE = System.getenv().getOrDefault("MYSQL_DATABASE", "order_db");
    public static final String MYSQL_USERNAME = System.getenv().getOrDefault("MYSQL_USERNAME", "flink_cdc");
    public static final String MYSQL_PASSWORD = System.getenv().getOrDefault("MYSQL_PASSWORD", "cdc_password_123");

    // CDC 설정
    public static final String SERVER_ID = System.getenv().getOrDefault("CDC_SERVER_ID", "5400-5404");
    public static final String[] TABLES = {
        MYSQL_DATABASE + ".orders",
        MYSQL_DATABASE + ".order_items"
    };

    // Kafka 설정
    public static final String KAFKA_BOOTSTRAP_SERVERS = System.getenv().getOrDefault(
        "KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"
    );
    public static final String KAFKA_TOPIC_ORDERS = "orders-cdc-topic";
    public static final String KAFKA_TOPIC_ORDER_ITEMS = "order-items-cdc-topic";

    // Checkpoint 설정
    public static final long CHECKPOINT_INTERVAL = 60000L; // 1분
}
```

### 3. 메인 CDC Job (MySQLCDCJob.java)
```java
package com.example.cdc;

import com.example.cdc.config.CDCConfig;
import com.example.cdc.model.OrderEvent;
import com.ververica.cdc.connectors.mysql.source.MySqlSource;
import com.ververica.cdc.connectors.mysql.table.StartupOptions;
import com.ververica.cdc.debezium.JsonDebeziumDeserializationSchema;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.streaming.api.datastream.DataStreamSource;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.ProcessFunction;
import org.apache.flink.util.Collector;

import java.util.Properties;

public class MySQLCDCJob {
    public static void main(String[] args) throws Exception {
        // 1. Flink 실행 환경 설정
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // 2. Checkpoint 설정 (Exactly-Once 보장)
        env.enableCheckpointing(CDCConfig.CHECKPOINT_INTERVAL);
        env.getCheckpointConfig().setCheckpointStorage("file:///tmp/flink-checkpoints");

        // 3. MySQL CDC Source 생성
        MySqlSource<String> mySqlSource = MySqlSource.<String>builder()
            .hostname(CDCConfig.MYSQL_HOST)
            .port(CDCConfig.MYSQL_PORT)
            .databaseList(CDCConfig.MYSQL_DATABASE)
            .tableList(CDCConfig.TABLES)
            .username(CDCConfig.MYSQL_USERNAME)
            .password(CDCConfig.MYSQL_PASSWORD)
            .serverId(CDCConfig.SERVER_ID)
            .startupOptions(StartupOptions.initial()) // 초기 스냅샷 + 증분 동기화
            .deserializer(new JsonDebeziumDeserializationSchema()) // JSON 형식으로 역직렬화
            .build();

        // 4. CDC 스트림 생성
        DataStreamSource<String> cdcStream = env
            .fromSource(mySqlSource, WatermarkStrategy.noWatermarks(), "MySQL CDC Source");

        // 5. 테이블별 라우팅 및 Kafka로 전송
        cdcStream
            .process(new ProcessFunction<String, String>() {
                @Override
                public void processElement(String value, Context ctx, Collector<String> out) throws Exception {
                    // JSON 파싱하여 테이블명 추출
                    if (value.contains("\"table\":\"orders\"")) {
                        ctx.output(ordersSideOutput, value);
                    } else if (value.contains("\"table\":\"order_items\"")) {
                        ctx.output(orderItemsSideOutput, value);
                    }
                }
            });

        // 6. Kafka Sink 생성 (orders 테이블)
        KafkaSink<String> ordersSink = KafkaSink.<String>builder()
            .setBootstrapServers(CDCConfig.KAFKA_BOOTSTRAP_SERVERS)
            .setRecordSerializer(
                KafkaRecordSerializationSchema.builder()
                    .setTopic(CDCConfig.KAFKA_TOPIC_ORDERS)
                    .setValueSerializationSchema(new SimpleStringSchema())
                    .build()
            )
            .build();

        // 7. Kafka Sink 생성 (order_items 테이블)
        KafkaSink<String> orderItemsSink = KafkaSink.<String>builder()
            .setBootstrapServers(CDCConfig.KAFKA_BOOTSTRAP_SERVERS)
            .setRecordSerializer(
                KafkaRecordSerializationSchema.builder()
                    .setTopic(CDCConfig.KAFKA_TOPIC_ORDER_ITEMS)
                    .setValueSerializationSchema(new SimpleStringSchema())
                    .build()
            )
            .build();

        // 8. Kafka로 전송
        cdcStream
            .filter(value -> value.contains("\"table\":\"orders\""))
            .sinkTo(ordersSink)
            .name("Orders CDC to Kafka");

        cdcStream
            .filter(value -> value.contains("\"table\":\"order_items\""))
            .sinkTo(orderItemsSink)
            .name("Order Items CDC to Kafka");

        // 9. Job 실행
        env.execute("MySQL CDC to Kafka Job");
    }
}
```

### 4. 간소화된 버전 (단일 Kafka Topic)
```java
package com.example.cdc;

import com.example.cdc.config.CDCConfig;
import com.ververica.cdc.connectors.mysql.source.MySqlSource;
import com.ververica.cdc.connectors.mysql.table.StartupOptions;
import com.ververica.cdc.debezium.JsonDebeziumDeserializationSchema;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public class MySQLCDCJobSimple {
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(60000);

        // MySQL CDC Source
        MySqlSource<String> mySqlSource = MySqlSource.<String>builder()
            .hostname("mysql")
            .port(3306)
            .databaseList("order_db")
            .tableList("order_db.orders", "order_db.order_items")
            .username("flink_cdc")
            .password("cdc_password_123")
            .startupOptions(StartupOptions.initial())
            .deserializer(new JsonDebeziumDeserializationSchema())
            .build();

        // Kafka Sink
        KafkaSink<String> kafkaSink = KafkaSink.<String>builder()
            .setBootstrapServers("kafka:9092")
            .setRecordSerializer(
                KafkaRecordSerializationSchema.builder()
                    .setTopic("orders-cdc-topic")
                    .setValueSerializationSchema(new SimpleStringSchema())
                    .build()
            )
            .build();

        // Pipeline
        env.fromSource(mySqlSource, WatermarkStrategy.noWatermarks(), "MySQL CDC")
            .sinkTo(kafkaSink)
            .name("CDC to Kafka");

        env.execute("MySQL CDC Job");
    }
}
```

## 📊 CDC 이벤트 형식

### Flink CDC Change Event 구조
```json
{
  "before": null,
  "after": {
    "order_id": 1001,
    "user_id": 500,
    "product_name": "Laptop",
    "quantity": 2,
    "total_price": 2000.00,
    "status": "pending",
    "created_at": "2025-01-11T10:30:00Z",
    "updated_at": "2025-01-11T10:30:00Z"
  },
  "source": {
    "version": "3.0.1",
    "connector": "mysql",
    "name": "mysql-server",
    "ts_ms": 1736592600000,
    "snapshot": "false",
    "db": "order_db",
    "table": "orders",
    "server_id": 1,
    "gtid": null,
    "file": "mysql-bin.000003",
    "pos": 1234,
    "row": 0
  },
  "op": "c",  // c=create, u=update, d=delete, r=read(snapshot)
  "ts_ms": 1736592600123,
  "transaction": null
}
```

### 작업 유형 (op 필드)
- **`c` (create)**: INSERT 작업
- **`u` (update)**: UPDATE 작업
- **`d` (delete)**: DELETE 작업
- **`r` (read)**: 초기 스냅샷 읽기

## 🔍 모니터링 및 디버깅

### 1. Flink Web UI에서 확인
```
http://localhost:8081

확인 항목:
- Job 상태 (RUNNING)
- Checkpoints 성공률
- Records Sent (Kafka로 전송된 레코드 수)
- Backpressure (역압 상태)
```

### 2. Kafka Topic 확인
```bash
# 컨테이너 접속
docker exec -it kafka bash

# Topic 목록 확인
kafka-topics --bootstrap-server localhost:9092 --list

# CDC 이벤트 확인
kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic orders-cdc-topic \
  --from-beginning \
  --max-messages 10
```

### 3. MySQL Binlog 상태 확인
```sql
-- Binlog 활성화 확인
SHOW VARIABLES LIKE 'log_bin';

-- Binlog 파일 목록
SHOW BINARY LOGS;

-- 현재 Binlog 위치
SHOW MASTER STATUS;

-- Binlog 이벤트 확인
SHOW BINLOG EVENTS IN 'mysql-bin.000003' LIMIT 10;
```

## ⚙️ Startup Options

### 1. initial() - 초기 스냅샷 + 증분 동기화 (권장)
```java
.startupOptions(StartupOptions.initial())
```
- 기존 데이터 전체 스냅샷 후 binlog 증분 동기화
- **MVP 테스트에 적합**

### 2. latest() - 최신 binlog부터
```java
.startupOptions(StartupOptions.latest())
```
- Job 시작 이후의 변경사항만 캡처
- 기존 데이터 무시

### 3. timestamp() - 특정 시점부터
```java
.startupOptions(StartupOptions.timestamp(1736592600000L))
```
- 특정 타임스탬프 이후의 변경사항 캡처

### 4. specificOffset() - 특정 binlog 위치부터
```java
.startupOptions(StartupOptions.specificOffset("mysql-bin.000003", 1234))
```
- 특정 binlog 파일 및 offset부터 시작

## 🧪 테스트 방법

### 1. MySQL에 테스트 데이터 삽입
```sql
USE order_db;

-- 주문 생성 (order_items는 별도로 추가)
INSERT INTO orders (user_id, status, total_amount, order_date)
VALUES (101, 'PENDING', 500.00, NOW());

-- 주문 항목 추가
INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
VALUES (LAST_INSERT_ID(), 1001, 'Test Product', 5, 100.00, 500.00);
```

### 2. Kafka에서 이벤트 확인
```bash
kafka-console-consumer --bootstrap-server kafka:9092 \
  --topic orders-cdc-topic \
  --from-beginning
```

### 3. UPDATE 테스트
```sql
UPDATE orders SET status = 'completed' WHERE order_id = 1001;
```

### 4. DELETE 테스트
```sql
DELETE FROM orders WHERE order_id = 1001;
```

## 🚨 트러블슈팅

### 문제 1: CDC Job이 시작되지 않음
```
원인: MySQL binlog가 비활성화됨
해결: my.cnf에서 log_bin 설정 확인
```

### 문제 2: 권한 오류 (Access denied)
```sql
-- 권한 재부여
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT
ON *.* TO 'flink_cdc'@'%';
FLUSH PRIVILEGES;
```

### 문제 3: Checkpoint 실패
```
원인: Checkpoint 저장 경로 문제
해결:
env.getCheckpointConfig().setCheckpointStorage("file:///tmp/flink-checkpoints");
# 또는 HDFS, S3 사용
```

### 문제 4: Kafka 연결 실패
```
원인: Kafka 부트스트랩 서버 주소 오류
해결: Docker 네트워크에서 'kafka' 호스트명 사용
```

## 📦 Docker 배포 설정

### Dockerfile (Flink Job)
```dockerfile
FROM flink:1.18.0-scala_2.12-java11

# CDC Job JAR 복사
COPY target/mysql-cdc-job.jar /opt/flink/usrlib/

# MySQL Connector 복사 (런타임 의존성)
COPY lib/mysql-connector-java-8.0.33.jar /opt/flink/lib/
COPY lib/flink-connector-mysql-cdc-3.0.1.jar /opt/flink/lib/
COPY lib/flink-connector-kafka-3.0.2-1.18.jar /opt/flink/lib/

# 환경변수 설정
ENV MYSQL_HOST=mysql
ENV KAFKA_BOOTSTRAP_SERVERS=kafka:9092
```

## 🔐 보안 고려사항

### 1. CDC 사용자 권한 최소화
```sql
-- 특정 데이터베이스만 접근
CREATE USER 'flink_cdc'@'%' IDENTIFIED BY 'strong_password';
GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON order_db.* TO 'flink_cdc'@'%';
```

### 2. 비밀번호 암호화
```bash
# 환경변수로 관리
export MYSQL_PASSWORD=$(echo "cdc_password_123" | base64)
```

### 3. SSL 연결 활성화
```java
.jdbcProperties(Map.of(
    "useSSL", "true",
    "requireSSL", "true"
))
```

## 📚 다음 단계
- [Confluent Kafka 구성](./03-confluent-kafka.md) - CDC 이벤트를 받을 Kafka 설정
- [Flink Sync Connector](./04-flink-sync-connector.md) - Kafka → ClickHouse 동기화
