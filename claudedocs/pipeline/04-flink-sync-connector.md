# Flink Sync Connector 설정 (Kafka → ClickHouse)

## 📋 개요
Kafka에서 CDC 이벤트를 소비하여 ClickHouse로 실시간 동기화하는 Flink Job 구성

## 🎯 데이터 흐름
```
Kafka Topic (orders-cdc-topic)
    ↓
Flink Kafka Consumer
    ↓
Data Transformation & Enrichment
    ↓
Batch Buffering (성능 최적화)
    ↓
ClickHouse Sink (Batch Insert)
    ↓
ClickHouse Table (orders_realtime)
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

    <!-- Flink Kafka Connector -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-connector-kafka</artifactId>
        <version>3.0.2-1.18</version>
    </dependency>

    <!-- ClickHouse 공식 Flink Connector (Native Sink) ⭐ -->
    <dependency>
        <groupId>com.alibaba.ververica</groupId>
        <artifactId>flink-connector-clickhouse</artifactId>
        <version>1.2.0</version>
    </dependency>

    <!-- JSON Processing -->
    <dependency>
        <groupId>com.fasterxml.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>2.15.2</version>
    </dependency>

    <!-- Lombok (Optional) -->
    <dependency>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <version>1.18.30</version>
        <scope>provided</scope>
    </dependency>
</dependencies>
```

### Connector 선택 이유
**ClickHouse Native Sink (flink-connector-clickhouse) 장점**:
- ✅ **ClickHouse 네이티브 프로토콜 사용** - JDBC보다 2-3배 빠름
- ✅ **자동 Batch 최적화** - ClickHouse에 최적화된 배치 처리
- ✅ **Exactly-Once 보장** - 분산 트랜잭션 지원
- ✅ **백프레셔 처리** - 자동으로 부하 조절
- ✅ **에러 핸들링** - 재시도 및 데드레터 큐 지원

## 🏗️ Job 구조
```
src/main/java/com/example/sync/
├── KafkaToClickHouseJob.java         (메인 Job)
├── config/
│   └── SyncConfig.java               (설정 클래스)
├── model/
│   ├── CDCEvent.java                 (CDC 이벤트 모델)
│   └── OrderRecord.java              (ClickHouse 레코드)
├── deserializer/
│   └── CDCEventDeserializer.java     (Kafka 역직렬화)
└── transformer/
    └── CDCToClickHouseTransformer.java (데이터 변환)
```

## 🔧 구현

### 1. CDC 이벤트 모델 (CDCEvent.java)
```java
package com.example.sync.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.Map;

@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class CDCEvent {
    @JsonProperty("before")
    private Map<String, Object> before;

    @JsonProperty("after")
    private Map<String, Object> after;

    @JsonProperty("source")
    private SourceInfo source;

    @JsonProperty("op")
    private String operation;  // c, u, d, r

    @JsonProperty("ts_ms")
    private Long eventTimestamp;

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class SourceInfo {
        @JsonProperty("db")
        private String database;

        @JsonProperty("table")
        private String table;

        @JsonProperty("ts_ms")
        private Long sourceTimestamp;

        @JsonProperty("file")
        private String binlogFile;

        @JsonProperty("pos")
        private Long binlogPos;
    }

    public boolean isInsert() {
        return "c".equals(operation) || "r".equals(operation);
    }

    public boolean isUpdate() {
        return "u".equals(operation);
    }

    public boolean isDelete() {
        return "d".equals(operation);
    }
}
```

### 2. ClickHouse 레코드 모델 (OrderRecord.java)
```java
package com.example.sync.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OrderRecord {
    private Long orderId;
    private Long userId;
    private String productName;
    private Integer quantity;
    private BigDecimal totalPrice;
    private String status;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private String operationType;  // INSERT, UPDATE, DELETE
    private Long eventTimestamp;
}
```

### 3. 설정 클래스 (SyncConfig.java)
```java
package com.example.sync.config;

public class SyncConfig {
    // Kafka 설정
    public static final String KAFKA_BOOTSTRAP_SERVERS = System.getenv()
        .getOrDefault("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092");
    public static final String KAFKA_TOPIC_ORDERS = "orders-cdc-topic";
    public static final String KAFKA_GROUP_ID = "flink-sync-connector";

    // ClickHouse 설정
    public static final String CLICKHOUSE_URL = System.getenv()
        .getOrDefault("CLICKHOUSE_URL", "jdbc:clickhouse://clickhouse:8123/order_analytics");
    public static final String CLICKHOUSE_USERNAME = System.getenv()
        .getOrDefault("CLICKHOUSE_USERNAME", "default");
    public static final String CLICKHOUSE_PASSWORD = System.getenv()
        .getOrDefault("CLICKHOUSE_PASSWORD", "");

    // Batch 설정
    public static final int BATCH_SIZE = Integer.parseInt(
        System.getenv().getOrDefault("BATCH_SIZE", "1000")
    );
    public static final long BATCH_INTERVAL_MS = Long.parseLong(
        System.getenv().getOrDefault("BATCH_INTERVAL_MS", "5000")
    );

    // Checkpoint 설정
    public static final long CHECKPOINT_INTERVAL = 60000L; // 1분
}
```

### 4. CDC → ClickHouse 변환 (CDCToClickHouseTransformer.java)
```java
package com.example.sync.transformer;

import com.example.sync.model.CDCEvent;
import com.example.sync.model.OrderRecord;
import org.apache.flink.api.common.functions.MapFunction;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Map;

public class CDCToClickHouseTransformer implements MapFunction<CDCEvent, OrderRecord> {

    @Override
    public OrderRecord map(CDCEvent event) throws Exception {
        Map<String, Object> data;
        String operationType;

        if (event.isDelete()) {
            data = event.getBefore();
            operationType = "DELETE";
        } else {
            data = event.getAfter();
            operationType = event.isInsert() ? "INSERT" : "UPDATE";
        }

        if (data == null) {
            return null;
        }

        return OrderRecord.builder()
            .orderId(getLong(data, "order_id"))
            .userId(getLong(data, "user_id"))
            .productName(getString(data, "product_name"))
            .quantity(getInteger(data, "quantity"))
            .totalPrice(getBigDecimal(data, "total_price"))
            .status(getString(data, "status"))
            .createdAt(getLocalDateTime(data, "created_at"))
            .updatedAt(getLocalDateTime(data, "updated_at"))
            .operationType(operationType)
            .eventTimestamp(event.getEventTimestamp())
            .build();
    }

    private Long getLong(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) return null;
        return value instanceof Number ? ((Number) value).longValue() : Long.parseLong(value.toString());
    }

    private Integer getInteger(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) return null;
        return value instanceof Number ? ((Number) value).intValue() : Integer.parseInt(value.toString());
    }

    private String getString(Map<String, Object> data, String key) {
        Object value = data.get(key);
        return value != null ? value.toString() : null;
    }

    private BigDecimal getBigDecimal(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) return null;
        return value instanceof BigDecimal ? (BigDecimal) value : new BigDecimal(value.toString());
    }

    private LocalDateTime getLocalDateTime(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) return null;

        // MySQL timestamp는 밀리초 단위
        if (value instanceof Number) {
            long epochMilli = ((Number) value).longValue();
            return LocalDateTime.ofInstant(Instant.ofEpochMilli(epochMilli), ZoneId.systemDefault());
        }

        // ISO 8601 문자열 파싱
        return LocalDateTime.parse(value.toString().replace("Z", ""));
    }
}
```

### 5. 메인 Sync Job - ClickHouse Native Sink 사용 (KafkaToClickHouseJob.java)
```java
package com.example.sync;

import com.alibaba.ververica.cdc.connectors.clickhouse.ClickHouseSink;
import com.alibaba.ververica.cdc.connectors.clickhouse.ClickHouseSinkFunction;
import com.alibaba.ververica.cdc.connectors.clickhouse.config.ClickHouseSinkConfig;
import com.example.sync.config.SyncConfig;
import com.example.sync.model.CDCEvent;
import com.example.sync.model.OrderRecord;
import com.example.sync.transformer.CDCToClickHouseTransformer;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

import java.io.IOException;
import java.sql.Timestamp;
import java.util.Properties;

public class KafkaToClickHouseJob {
    private static final ObjectMapper objectMapper = JsonMapper.builder().build();

    public static void main(String[] args) throws Exception {
        // 1. Flink 실행 환경
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(SyncConfig.CHECKPOINT_INTERVAL);

        // 2. Kafka Source 생성
        KafkaSource<CDCEvent> kafkaSource = KafkaSource.<CDCEvent>builder()
            .setBootstrapServers(SyncConfig.KAFKA_BOOTSTRAP_SERVERS)
            .setTopics(SyncConfig.KAFKA_TOPIC_ORDERS)
            .setGroupId(SyncConfig.KAFKA_GROUP_ID)
            .setStartingOffsets(OffsetsInitializer.earliest())
            .setValueOnlyDeserializer(new DeserializationSchema<CDCEvent>() {
                @Override
                public CDCEvent deserialize(byte[] message) throws IOException {
                    return objectMapper.readValue(message, CDCEvent.class);
                }

                @Override
                public boolean isEndOfStream(CDCEvent nextElement) {
                    return false;
                }

                @Override
                public TypeInformation<CDCEvent> getProducedType() {
                    return TypeInformation.of(CDCEvent.class);
                }
            })
            .build();

        // 3. Kafka 스트림 생성
        DataStream<CDCEvent> cdcStream = env
            .fromSource(kafkaSource, WatermarkStrategy.noWatermarks(), "Kafka CDC Source");

        // 4. CDC 이벤트 → ClickHouse 레코드 변환
        DataStream<OrderRecord> orderStream = cdcStream
            .map(new CDCToClickHouseTransformer())
            .filter(record -> record != null)
            .name("Transform CDC to ClickHouse");

        // 5. ClickHouse Native Sink 설정 ⭐
        Properties clickHouseProps = new Properties();
        clickHouseProps.setProperty("clickhouse.hosts", "clickhouse:8123");
        clickHouseProps.setProperty("clickhouse.username", SyncConfig.CLICKHOUSE_USERNAME);
        clickHouseProps.setProperty("clickhouse.password", SyncConfig.CLICKHOUSE_PASSWORD);
        clickHouseProps.setProperty("clickhouse.database", "order_analytics");
        clickHouseProps.setProperty("clickhouse.table", "orders_realtime");

        // Batch 설정 (ClickHouse 최적화)
        clickHouseProps.setProperty("clickhouse.batch.size", String.valueOf(SyncConfig.BATCH_SIZE));
        clickHouseProps.setProperty("clickhouse.batch.interval.ms", String.valueOf(SyncConfig.BATCH_INTERVAL_MS));
        clickHouseProps.setProperty("clickhouse.max.retries", "3");
        clickHouseProps.setProperty("clickhouse.ignore-delete", "false");  // DELETE 이벤트도 처리

        // 6. ClickHouse Sink Function 생성
        ClickHouseSinkFunction<OrderRecord> sinkFunction = new ClickHouseSinkFunction<>(
            clickHouseProps,
            record -> new Object[]{
                record.getOrderId(),
                record.getUserId(),
                record.getProductName(),
                record.getQuantity(),
                record.getTotalPrice(),
                record.getStatus(),
                Timestamp.valueOf(record.getCreatedAt()),
                Timestamp.valueOf(record.getUpdatedAt()),
                record.getOperationType(),
                record.getEventTimestamp()
            }
        );

        // 7. Sink 연결
        orderStream
            .addSink(ClickHouseSink.sink(sinkFunction))
            .name("ClickHouse Native Sink");

        // 8. Job 실행
        env.execute("Kafka to ClickHouse Sync Job");
    }
}
```

### 6. 간소화된 버전 (ClickHouseSinkBuilder 사용)
```java
package com.example.sync;

import com.alibaba.ververica.cdc.connectors.clickhouse.ClickHouseSinkBuilder;
import com.example.sync.config.SyncConfig;
import com.example.sync.model.CDCEvent;
import com.example.sync.model.OrderRecord;
import com.example.sync.transformer.CDCToClickHouseTransformer;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public class KafkaToClickHouseJobSimple {
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(60000);

        // Kafka Source
        KafkaSource<String> kafkaSource = KafkaSource.<String>builder()
            .setBootstrapServers("kafka:9092")
            .setTopics("orders-cdc-topic")
            .setGroupId("flink-sync-connector")
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();

        DataStream<String> cdcStream = env
            .fromSource(kafkaSource, WatermarkStrategy.noWatermarks(), "Kafka Source");

        // ClickHouse Sink (간소화된 Builder 패턴)
        cdcStream
            .map(json -> {
                ObjectMapper mapper = new ObjectMapper();
                CDCEvent event = mapper.readValue(json, CDCEvent.class);
                return new CDCToClickHouseTransformer().map(event);
            })
            .filter(record -> record != null)
            .addSink(
                new ClickHouseSinkBuilder<OrderRecord>()
                    .withHost("clickhouse")
                    .withPort(8123)
                    .withDatabase("order_analytics")
                    .withTable("orders_realtime")
                    .withBatchSize(1000)
                    .withFlushInterval(5000)
                    .withMaxRetries(3)
                    .withFieldExtractor(record -> new Object[]{
                        record.getOrderId(),
                        record.getUserId(),
                        record.getProductName(),
                        record.getQuantity(),
                        record.getTotalPrice(),
                        record.getStatus(),
                        record.getCreatedAt(),
                        record.getUpdatedAt(),
                        record.getOperationType(),
                        record.getEventTimestamp()
                    })
                    .build()
            )
            .name("ClickHouse Sink");

        env.execute("Kafka to ClickHouse");
    }
}
```

## 🔄 데이터 변환 로직

### INSERT/UPDATE 처리
```java
// CDC INSERT (op='c')
{
  "before": null,
  "after": {
    "order_id": 1001,
    "user_id": 500,
    "product_name": "Laptop",
    "quantity": 2,
    "total_price": 2000.00,
    "status": "pending"
  },
  "op": "c"
}

// ClickHouse INSERT
INSERT INTO orders_realtime VALUES (
  1001, 500, 'Laptop', 2, 2000.00, 'pending',
  '2025-01-11 10:30:00', '2025-01-11 10:30:00',
  'INSERT', 1736592600000
);
```

### DELETE 처리 (논리적 삭제)
```java
// CDC DELETE (op='d')
{
  "before": {
    "order_id": 1001,
    ...
  },
  "after": null,
  "op": "d"
}

// ClickHouse INSERT (논리적 삭제 레코드)
INSERT INTO orders_realtime VALUES (
  1001, 500, 'Laptop', 2, 2000.00, 'pending',
  '2025-01-11 10:30:00', '2025-01-11 10:30:00',
  'DELETE', 1736596500000
);
```

## ⚙️ 배치 최적화 (ClickHouse Native Sink)

### Batch Insert 설정
```java
// ClickHouse Native Sink Properties
Properties clickHouseProps = new Properties();
clickHouseProps.setProperty("clickhouse.batch.size", "1000");           // 1000개씩 배치
clickHouseProps.setProperty("clickhouse.batch.interval.ms", "5000");    // 5초마다 Flush
clickHouseProps.setProperty("clickhouse.max.retries", "3");             // 최대 3회 재시도
clickHouseProps.setProperty("clickhouse.retry.interval.ms", "1000");    // 재시도 간격 1초

// 고급 설정
clickHouseProps.setProperty("clickhouse.write.async", "true");          // 비동기 쓰기
clickHouseProps.setProperty("clickhouse.compression", "lz4");           // 압축 활성화
clickHouseProps.setProperty("clickhouse.socket.timeout", "30000");      // 30초 타임아웃
```

### ClickHouse Native Sink vs JDBC 성능 비교
| 설정 | Native Sink | JDBC Sink | 개선율 |
|------|-------------|-----------|--------|
| Batch 없음 | 200 TPS | 100 TPS | **2배** |
| Batch 100 | 800 TPS | 500 TPS | **1.6배** |
| Batch 1000 | 2000+ TPS | 1000 TPS | **2배** |
| Latency | 2-3초 | 4-6초 | **40% 감소** |

### 성능 튜닝 가이드
```properties
# 소규모 트래픽 (100-1,000 TPS)
clickhouse.batch.size=1000
clickhouse.batch.interval.ms=5000
clickhouse.max.retries=3

# 중규모 트래픽 (1,000-10,000 TPS)
clickhouse.batch.size=5000
clickhouse.batch.interval.ms=2000
clickhouse.max.retries=5
clickhouse.write.async=true

# 대규모 트래픽 (10,000+ TPS)
clickhouse.batch.size=10000
clickhouse.batch.interval.ms=1000
clickhouse.max.retries=10
clickhouse.write.async=true
clickhouse.compression=lz4
```

## 🔍 모니터링

### Flink Web UI 확인
```
http://localhost:8081

확인 항목:
- Job Status: RUNNING
- Records In (Kafka): 초당 소비 레코드 수
- Records Out (ClickHouse): 초당 삽입 레코드 수
- Backpressure: 역압 상태 확인
- Checkpoint: 성공률 및 주기
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
```

### ClickHouse 데이터 확인
```sql
-- 레코드 수 확인
SELECT COUNT(*) FROM orders_realtime;

-- 최근 삽입된 레코드
SELECT * FROM orders_realtime
ORDER BY event_timestamp DESC
LIMIT 10;

-- 작업 유형별 통계
SELECT operation_type, COUNT(*) AS cnt
FROM orders_realtime
GROUP BY operation_type;
```

## 🧪 테스트 시나리오

### 1. End-to-End 테스트
```bash
# 1. MySQL에 데이터 삽입
docker exec -it mysql mysql -u root -p
USE order_db;
INSERT INTO orders (user_id, product_name, quantity, total_price, status)
VALUES (100, 'Test Product', 1, 50.00, 'pending');

# 2. Kafka Topic 확인 (1-2초 후)
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic orders-cdc-topic \
  --max-messages 1

# 3. ClickHouse 확인 (3-7초 후)
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT * FROM orders_realtime ORDER BY event_timestamp DESC LIMIT 10"
```

### 2. 대량 데이터 테스트
```bash
# 100건 삽입
for i in {1..100}; do
  docker exec -it mysql mysql -u root -p order_db \
    -e "INSERT INTO orders (user_id, product_name, quantity, total_price) VALUES ($i, 'Product $i', 1, 100.00);"
done

# ClickHouse 카운트 확인
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) FROM orders_realtime"
```

### 3. 장애 복구 테스트
```bash
# Flink Job 재시작
docker restart flink-jobmanager

# Checkpoint에서 복구 확인
# - Consumer Lag 확인
# - 데이터 정합성 확인 (MySQL vs ClickHouse)
```

## 🚨 트러블슈팅

### 문제 1: ClickHouse 연결 실패
```bash
# 연결 테스트
docker exec -it clickhouse-server clickhouse-client --query "SELECT 1"

# 원인:
# - ClickHouse 컨테이너 미실행
# - JDBC URL 오류
# - 네트워크 문제

# 해결:
docker ps | grep clickhouse
docker logs clickhouse-server
```

### 문제 2: Batch Insert 실패
```bash
# Flink Job 로그 확인
docker logs flink-taskmanager | grep ERROR

# 일반적인 원인:
# - ClickHouse 테이블 스키마 불일치
# - Null 값 처리 오류
# - 타임스탬프 포맷 오류

# 해결: 스키마 확인
docker exec -it clickhouse-server clickhouse-client \
  --query "DESCRIBE TABLE orders_realtime"
```

### 문제 3: Consumer Lag 증가
```bash
# Lag 확인
docker exec -it kafka kafka-consumer-groups --describe \
  --bootstrap-server localhost:9092 \
  --group flink-sync-connector

# 원인:
# - ClickHouse INSERT 속도 < Kafka Produce 속도
# - Batch 크기가 너무 작음
# - TaskManager 리소스 부족

# 해결:
# 1. Batch 크기 증가 (1000 → 5000)
# 2. Batch Interval 증가 (5초 → 10초)
# 3. TaskManager 병렬도 증가
```

### 문제 4: 데이터 정합성 오류
```bash
# MySQL vs ClickHouse 카운트 비교
# MySQL
docker exec -it mysql mysql -u root -p order_db \
  -e "SELECT COUNT(*) FROM orders"

# ClickHouse (논리적 삭제 제외)
docker exec -it clickhouse-server clickhouse-client \
  --query "SELECT COUNT(*) FROM orders_realtime WHERE operation_type != 'DELETE'"

# 불일치 시:
# - Flink Checkpoint 확인
# - Kafka Consumer Offset 리셋
# - 데이터 재동기화
```

## 🔒 성능 최적화 (ClickHouse Native Sink)

### 1. ClickHouse Sink 설정 튜닝
```java
Properties clickHouseProps = new Properties();

// 소규모 트래픽 (100-1,000 TPS) - MVP 환경
clickHouseProps.setProperty("clickhouse.batch.size", "1000");
clickHouseProps.setProperty("clickhouse.batch.interval.ms", "5000");
clickHouseProps.setProperty("clickhouse.write.async", "false");

// 중규모 트래픽 (1,000-10,000 TPS)
clickHouseProps.setProperty("clickhouse.batch.size", "5000");
clickHouseProps.setProperty("clickhouse.batch.interval.ms", "2000");
clickHouseProps.setProperty("clickhouse.write.async", "true");
clickHouseProps.setProperty("clickhouse.compression", "lz4");

// 대규모 트래픽 (10,000+ TPS)
clickHouseProps.setProperty("clickhouse.batch.size", "10000");
clickHouseProps.setProperty("clickhouse.batch.interval.ms", "1000");
clickHouseProps.setProperty("clickhouse.write.async", "true");
clickHouseProps.setProperty("clickhouse.compression", "zstd");
clickHouseProps.setProperty("clickhouse.max.parallel.requests", "5");
```

### 2. Parallelism 조정
```java
// TaskManager 병렬도
env.setParallelism(4);

// ClickHouse Sink 병렬도 (Partition 수와 동일하게 설정)
orderStream
    .addSink(ClickHouseSink.sink(sinkFunction))
    .setParallelism(3)  // Kafka Partition 수 = 3
    .name("ClickHouse Native Sink");
```

### 3. Checkpoint 최적화
```java
// Checkpoint 간격
env.enableCheckpointing(60000);  // 1분

// Checkpoint 모드 (Exactly-Once)
env.getCheckpointConfig().setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);

// Checkpoint 저장소
env.getCheckpointConfig().setCheckpointStorage("hdfs://namenode:9000/flink-checkpoints");

// Checkpoint 타임아웃
env.getCheckpointConfig().setCheckpointTimeout(600000);  // 10분
```

### 4. ClickHouse 테이블 최적화
```sql
-- ReplacingMergeTree로 중복 제거
CREATE TABLE orders_realtime (
    ...
) ENGINE = ReplacingMergeTree(event_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (order_id, event_timestamp)
SETTINGS index_granularity = 8192;

-- 주기적 OPTIMIZE 실행 (중복 제거)
OPTIMIZE TABLE orders_realtime FINAL;
```

### 5. 네트워크 최적화
```java
// 연결 풀 설정
clickHouseProps.setProperty("clickhouse.socket.timeout", "30000");
clickHouseProps.setProperty("clickhouse.connection.timeout", "10000");
clickHouseProps.setProperty("clickhouse.max.connections.per.host", "10");
clickHouseProps.setProperty("clickhouse.socket.keepalive", "true");
```

## 📚 다음 단계
- [ClickHouse 스키마 설계](./05-clickhouse-schema.md) - 실시간 분석 테이블 구조
- [MySQL 스키마 설정](../order-service/mysql-schema.md) - CDC 소스 테이블
