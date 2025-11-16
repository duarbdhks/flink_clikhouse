package com.flink.sync.job;

import com.flink.sync.config.KafkaSourceConfig;
import com.flink.sync.function.DeduplicationFunction;
import com.flink.sync.function.OrderItemsDeduplicationFunction;
import com.flink.sync.sink.ClickHouseSink;
import com.flink.sync.transform.CDCEventTransformer;
import com.flink.sync.transform.ClickHouseRow;
import com.flink.sync.transform.OrderItemsTransformer;
import com.flink.sync.transform.OrderItemsRow;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.api.common.restartstrategy.RestartStrategies;
import org.apache.flink.api.common.time.Time;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.streaming.api.CheckpointingMode;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.CheckpointConfig;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Objects;
import java.util.concurrent.TimeUnit;

/**
 * Kafka to ClickHouse Sync Job - Kafka CDC 이벤트를 ClickHouse로 동기화
 * 데이터 흐름:
 * 1. Kafka Topic (orders-cdc) -> Flink CDC Event Transformer -> ClickHouse orders_realtime
 * 2. Kafka Topic (order-items-cdc) -> Flink CDC Event Transformer -> ClickHouse order_items_realtime
 * 실행 방법:
 * flink run -c com.flink.sync.job.KafkaToClickHouseJob flink-sync-job.jar
 */
public class KafkaToClickHouseJob {

    private static final Logger LOG = LoggerFactory.getLogger(KafkaToClickHouseJob.class);

    public static void main(String[] args) throws Exception {
        // 1. Flink 실행 환경 설정
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // 2. Checkpoint 설정 (Exactly-Once 보장)
        configureCheckpointing(env);

        // 3. 재시작 전략 설정
        configureRestartStrategy(env);

        // 4. 병렬도 설정
        env.setParallelism(2);

        // ========================================
        // Pipeline 1: Orders (orders-cdc → orders_realtime)
        // ========================================

        // 5-1. Orders Kafka Source 생성
        KafkaSource<String> ordersKafkaSource = KafkaSourceConfig.createOrdersSource();
        LOG.info("✅ Orders Kafka Source 생성 완료");

        // 6-1. Orders Kafka 이벤트 스트림 생성
        DataStream<String> ordersCdcEventStream = env
                .fromSource(ordersKafkaSource, WatermarkStrategy.noWatermarks(), "Kafka CDC Source - Orders")
                .uid("kafka-cdc-source-orders")
                .name("Kafka CDC Event Reader - Orders");

        // 7-1. Orders CDC 이벤트를 ClickHouse Row로 변환
        DataStream<ClickHouseRow> ordersClickHouseRowStream = ordersCdcEventStream
                .map(new CDCEventTransformer())
                .uid("cdc-transformer-orders")
                .name("CDC Event Transformer - Orders")
                .filter(Objects::nonNull)  // null 필터링 (변환 실패 이벤트 제외)
                .uid("filter-null-rows-orders")
                .name("Filter Null Rows - Orders");

        // 8-1. Orders 중복 제거 (Deduplication)
        DataStream<ClickHouseRow> ordersDeduplicatedStream = ordersClickHouseRowStream
                .keyBy(row -> String.valueOf(row.getId()))
                .process(new DeduplicationFunction(600)) // 600초 (10분) State TTL
                .uid("deduplication-orders")
                .name("Deduplication Filter - Orders");

        // 9-1. Orders ClickHouse Sink
        ordersDeduplicatedStream
                .addSink(ClickHouseSink.createOrdersSink())
                .uid("clickhouse-sink-orders")
                .name("ClickHouse Orders Sink");

        LOG.info("✅ Orders Pipeline 생성 완료 (중복 제거 활성화: State TTL 600초)");

        // ========================================
        // Pipeline 2: OrderItems (order-items-cdc → order_items_realtime)
        // ========================================

        // 5-2. OrderItems Kafka Source 생성
        KafkaSource<String> orderItemsKafkaSource = KafkaSourceConfig.createOrderItemsSource();
        LOG.info("✅ OrderItems Kafka Source 생성 완료");

        // 6-2. OrderItems Kafka 이벤트 스트림 생성
        DataStream<String> orderItemsCdcEventStream = env
                .fromSource(orderItemsKafkaSource, WatermarkStrategy.noWatermarks(), "Kafka CDC Source - OrderItems")
                .uid("kafka-cdc-source-order-items")
                .name("Kafka CDC Event Reader - OrderItems");

        // 7-2. OrderItems CDC 이벤트를 ClickHouse Row로 변환
        DataStream<OrderItemsRow> orderItemsClickHouseRowStream = orderItemsCdcEventStream
                .map(new OrderItemsTransformer())
                .uid("cdc-transformer-order-items")
                .name("CDC Event Transformer - OrderItems")
                .filter(Objects::nonNull)  // null 필터링 (변환 실패 이벤트 제외)
                .uid("filter-null-rows-order-items")
                .name("Filter Null Rows - OrderItems");

        // 8-2. OrderItems 중복 제거 (Deduplication)
        DataStream<OrderItemsRow> orderItemsDeduplicatedStream = orderItemsClickHouseRowStream
                .keyBy(row -> String.valueOf(row.getId()))
                .process(new OrderItemsDeduplicationFunction(600)) // 600초 (10분) State TTL
                .uid("deduplication-order-items")
                .name("Deduplication Filter - OrderItems");

        // 9-2. OrderItems ClickHouse Sink
        orderItemsDeduplicatedStream
                .addSink(ClickHouseSink.createOrderItemsSink())
                .uid("clickhouse-sink-order-items")
                .name("ClickHouse OrderItems Sink");

        LOG.info("✅ OrderItems Pipeline 생성 완료 (중복 제거 활성화: State TTL 600초)");

        // 10. Job 실행
        LOG.info("🚀 Kafka to ClickHouse Sync Job 시작...");
        LOG.info("📥 Source 1: Kafka (orders-cdc) → ClickHouse (orders_realtime)");
        LOG.info("📥 Source 2: Kafka (order-items-cdc) → ClickHouse (order_items_realtime)");
        LOG.info("⚙️  Parallelism: {}", env.getParallelism());
        LOG.info("🔄 Batch Size: 1000 rows, Interval: 5 seconds");

        env.execute("Kafka CDC to ClickHouse - Orders + OrderItems Sync");
    }

    /**
     * Checkpoint 설정 (Exactly-Once 보장)
     */
    private static void configureCheckpointing(StreamExecutionEnvironment env) {
        // Checkpoint 간격: 30초 (Production 표준: 장애 복구 시 데이터 손실 창 최소화)
        env.enableCheckpointing(30000L);

        CheckpointConfig checkpointConfig = env.getCheckpointConfig();

        // Checkpoint 모드: EXACTLY_ONCE
        checkpointConfig.setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);

        // Checkpoint 간 최소 간격: 15초
        checkpointConfig.setMinPauseBetweenCheckpoints(15000L);

        // Checkpoint 타임아웃: 10분
        checkpointConfig.setCheckpointTimeout(600000L);

        // 동시 실행 가능한 Checkpoint 수: 1
        checkpointConfig.setMaxConcurrentCheckpoints(1);

        // Job 취소 시에도 Checkpoint 보존
        checkpointConfig.setExternalizedCheckpointCleanup(
                CheckpointConfig.ExternalizedCheckpointCleanup.RETAIN_ON_CANCELLATION
        );

        // 허용 가능한 Checkpoint 실패 횟수: 3회
        checkpointConfig.setTolerableCheckpointFailureNumber(3);

        // Checkpoint 스토리지 설정: Sync Job 전용 디렉토리
        // Docker 볼륨: ./docker/volumes/flink-checkpoints:/tmp/flink-checkpoints
        // Job별 경로 분리로 checkpoint 혼용 방지 (CDC와 Sync는 다른 operator UID 사용)
        checkpointConfig.setCheckpointStorage("file:///tmp/flink-checkpoints/sync");

        LOG.info("✅ Checkpoint 설정 완료: interval=30s, minPause=15s, mode=EXACTLY_ONCE, storage=file:///tmp/flink-checkpoints/sync");
    }

    /**
     * 재시작 전략 설정 (장애 복구)
     */
    private static void configureRestartStrategy(StreamExecutionEnvironment env) {
        // 고정 지연 재시작 전략: 최대 3회, 10초 간격
        env.setRestartStrategy(
                RestartStrategies.fixedDelayRestart(
                        3, // 최대 재시작 횟수
                        Time.of(10, TimeUnit.SECONDS) // 재시작 간격
                )
        );

        LOG.info("✅ Restart Strategy 설정 완료: 최대 3회, 10초 간격");
    }
}
