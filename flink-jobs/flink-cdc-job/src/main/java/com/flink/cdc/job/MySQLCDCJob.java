package com.flink.cdc.job;

import com.flink.cdc.config.CDCSourceConfig;
import com.flink.cdc.config.KafkaSinkConfig;
import com.flink.cdc.serialization.TableRouter;
import com.ververica.cdc.connectors.mysql.source.MySqlSource;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.restartstrategy.RestartStrategies;
import org.apache.flink.api.common.time.Time;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.streaming.api.CheckpointingMode;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.CheckpointConfig;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.TimeUnit;

/**
 * MySQL CDC Job - MySQL binlog 변경사항을 Kafka로 전송
 * <p>
 * 데이터 흐름:
 * MySQL binlog -> Flink CDC Source -> Kafka Sink -> orders-cdc-topic / order-items-cdc-topic
 * <p>
 * 실행 방법:
 * flink run -c com.flink.cdc.job.MySQLCDCJob flink-cdc-job.jar
 */
public class MySQLCDCJob {

    private static final Logger LOG = LoggerFactory.getLogger(MySQLCDCJob.class);

    public static void main(String[] args) throws Exception {
        // 1. Flink 실행 환경 설정
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // 2. Checkpoint 설정 (Exactly-Once 보장)
        configureCheckpointing(env);

        // 3. 재시작 전략 설정
        configureRestartStrategy(env);

        // 4. 병렬도 설정
        env.setParallelism(2); // TaskManager 수에 맞춰 조정

        // 5. MySQL CDC Source 생성
        MySqlSource<String> mySqlSource = CDCSourceConfig.createMySqlSource();
        LOG.info("✅ MySQL CDC Source 생성 완료");

        // 6. CDC 이벤트 스트림 생성
        DataStream<String> cdcStream = env.fromSource(mySqlSource, WatermarkStrategy.noWatermarks(), "MySQL CDC Source")
                                          .uid("mysql-cdc-source")
                                          .name("MySQL Binlog Reader");

        // 7. 테이블별로 라우팅 (orders / order_items)
        DataStream<String> ordersStream = cdcStream.filter(new TableRouter("orders")).uid("filter-orders").name("Filter Orders Table");

        DataStream<String> orderItemsStream = cdcStream.filter(new TableRouter("order_items"))
                                                       .uid("filter-order-items")
                                                       .name("Filter Order Items Table");

        // 8. Kafka Sink 생성
        KafkaSink<String> ordersSink = KafkaSinkConfig.createOrdersSink();
        KafkaSink<String> orderItemsSink = KafkaSinkConfig.createOrderItemsSink();
        LOG.info("✅ Kafka Sinks 생성 완료");

        // 9. Orders 스트림을 Kafka로 전송
        ordersStream.sinkTo(ordersSink).uid("kafka-sink-orders").name("Kafka Sink - Orders Topic");

        // 10. Order Items 스트림을 Kafka로 전송
        orderItemsStream.sinkTo(orderItemsSink).uid("kafka-sink-order-items").name("Kafka Sink - Order Items Topic");

        // 11. Job 실행
        LOG.info("🚀 MySQL CDC Job 시작...");
        LOG.info("📊 Source: MySQL (order_db.orders, order_db.order_items)");
        LOG.info("📤 Sink: Kafka (orders-cdc-topic, order-items-cdc-topic)");
        LOG.info("⚙️  Parallelism: {}", env.getParallelism());

        env.execute("MySQL CDC to Kafka - Orders & Order Items");
    }

    /**
     * Checkpoint 설정 (Exactly-Once 보장)
     */
    private static void configureCheckpointing(StreamExecutionEnvironment env) {
        // Checkpoint 간격: 60초
        env.enableCheckpointing(60000L);

        CheckpointConfig checkpointConfig = env.getCheckpointConfig();

        // Checkpoint 모드: EXACTLY_ONCE (정확히 한 번 보장)
        checkpointConfig.setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);

        // Checkpoint 간 최소 간격: 30초 (너무 자주 실행 방지)
        checkpointConfig.setMinPauseBetweenCheckpoints(30000L);

        // Checkpoint 타임아웃: 10분
        checkpointConfig.setCheckpointTimeout(600000L);

        // 동시 실행 가능한 Checkpoint 수: 1
        checkpointConfig.setMaxConcurrentCheckpoints(1);

        // Job 취소 시에도 Checkpoint 보존 (복구 가능)
        checkpointConfig.setExternalizedCheckpointCleanup(CheckpointConfig.ExternalizedCheckpointCleanup.RETAIN_ON_CANCELLATION);

        // 허용 가능한 Checkpoint 실패 횟수: 3회
        checkpointConfig.setTolerableCheckpointFailureNumber(3);

        LOG.info("✅ Checkpoint 설정 완료: interval=60s, mode=EXACTLY_ONCE");
    }

    /**
     * 재시작 전략 설정 (장애 복구)
     */
    private static void configureRestartStrategy(StreamExecutionEnvironment env) {
        // 고정 지연 재시작 전략: 최대 3회, 10초 간격
        env.setRestartStrategy(RestartStrategies.fixedDelayRestart(3, // 최대 재시작 횟수
                                                                   Time.of(10, TimeUnit.SECONDS) // 재시작 간격
        ));

        LOG.info("✅ Restart Strategy 설정 완료: 최대 3회, 10초 간격");
    }
}
