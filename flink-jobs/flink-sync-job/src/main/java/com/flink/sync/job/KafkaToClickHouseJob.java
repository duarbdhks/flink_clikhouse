package com.flink.sync.job;

import com.flink.sync.config.KafkaSourceConfig;
import com.flink.sync.function.DeduplicationFunction;
import com.flink.sync.sink.ClickHouseSink;
import com.flink.sync.transform.CDCEventTransformer;
import com.flink.sync.transform.ClickHouseRow;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
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
 * Kafka Topic (orders-cdc) -> Flink CDC Event Transformer -> ClickHouse Sink
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

        // 5. Kafka Source 생성
        KafkaSource<String> kafkaSource = KafkaSourceConfig.createOrdersSource();
        LOG.info("✅ Kafka Source 생성 완료");

        // 6. Kafka 이벤트 스트림 생성
        DataStream<String> cdcEventStream = env
                .fromSource(kafkaSource, WatermarkStrategy.noWatermarks(), "Kafka CDC Source")
                .uid("kafka-cdc-source")
                .name("Kafka CDC Event Reader");

        // 7. CDC 이벤트를 ClickHouse Row로 변환
        DataStream<ClickHouseRow> clickHouseRowStream = cdcEventStream
                .map(new CDCEventTransformer())
                .uid("cdc-transformer")
                .name("CDC Event Transformer")
                .filter(Objects::nonNull)  // null 필터링 (변환 실패 이벤트 제외)
                .uid("filter-null-rows")
                .name("Filter Null Rows");

        // 8. 중복 제거 (Deduplication) - ClickHouse 삽입 전 애플리케이션 레벨 필터링
        DataStream<ClickHouseRow> deduplicatedStream = clickHouseRowStream
                .keyBy(row -> row.getId() + "_" + row.getCdcTsMs()) // (id, cdc_ts_ms) 조합으로 그룹화
                .process(new DeduplicationFunction(60)) // 60초 State TTL
                .uid("deduplication")
                .name("Deduplication Filter");

        // 9. ClickHouse Sink 생성 및 데이터 삽입
        deduplicatedStream
                .addSink(ClickHouseSink.createOrdersSink())
                .uid("clickhouse-sink")
                .name("ClickHouse Orders Sink");

        LOG.info("✅ ClickHouse Sink 생성 완료 (중복 제거 활성화)");

        // 10. Job 실행
        LOG.info("🚀 Kafka to ClickHouse Sync Job 시작...");
        LOG.info("📥 Source: Kafka (orders-cdc)");
        LOG.info("📤 Sink: ClickHouse (orders_realtime)");
        LOG.info("⚙️  Parallelism: {}", env.getParallelism());
        LOG.info("🔄 Batch Size: 1000 rows, Interval: 5 seconds");

        env.execute("Kafka CDC to ClickHouse - Orders Sync");
    }

    /**
     * Checkpoint 설정 (Exactly-Once 보장)
     */
    private static void configureCheckpointing(StreamExecutionEnvironment env) {
        // Checkpoint 간격: 60초
        env.enableCheckpointing(60000L);

        CheckpointConfig checkpointConfig = env.getCheckpointConfig();

        // Checkpoint 모드: EXACTLY_ONCE
        checkpointConfig.setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);

        // Checkpoint 간 최소 간격: 30초
        checkpointConfig.setMinPauseBetweenCheckpoints(30000L);

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

        // Checkpoint 스토리지 설정: 파일 시스템 기반 (Job 재시작 시 복구 가능)
        // Docker 볼륨: ./docker/volumes/flink-checkpoints:/tmp/flink-checkpoints
        checkpointConfig.setCheckpointStorage("file:///tmp/flink-checkpoints");

        LOG.info("✅ Checkpoint 설정 완료: interval=60s, mode=EXACTLY_ONCE, storage=file:///tmp/flink-checkpoints");
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
