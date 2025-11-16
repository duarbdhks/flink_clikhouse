package com.flink.sync.config;

import com.flink.common.config.ConfigLoader;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.kafka.clients.consumer.OffsetResetStrategy;

import java.util.Properties;

/**
 * Kafka Source 설정 클래스
 * CDC 이벤트를 Kafka 토픽에서 읽어옵니다.
 * <p>
 * application.properties 파일에서 설정을 동적으로 읽어옵니다.
 */
public class KafkaSourceConfig {

    // Kafka Source 설정 (application.properties에서 로드)
    private static final String KAFKA_BROKERS = ConfigLoader.get("kafka.bootstrap.servers");
    private static final String ORDERS_TOPIC = ConfigLoader.get("kafka.topic.orders");
    private static final String ORDER_ITEMS_TOPIC = ConfigLoader.get("kafka.topic.order.items");
    private static final String CONSUMER_GROUP = ConfigLoader.get("kafka.consumer.group");

    /**
     * Orders CDC 이벤트를 위한 Kafka Source 생성
     *
     * @return KafkaSource<String> - orders-cdc에서 읽는 소스
     */
    public static KafkaSource<String> createOrdersSource() {
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("max.poll.records",
                ConfigLoader.get("kafka.consumer.max.poll.records", "500"));
        kafkaProps.setProperty("session.timeout.ms",
                ConfigLoader.get("kafka.consumer.session.timeout.ms", "30000"));
        kafkaProps.setProperty("enable.auto.commit",
                ConfigLoader.get("kafka.consumer.enable.auto.commit", "false")); // Flink가 offset 관리

        return KafkaSource.<String>builder()
                          .setBootstrapServers(KAFKA_BROKERS)
                          .setTopics(ORDERS_TOPIC)
                          .setGroupId(CONSUMER_GROUP)
                          // 첫 실행: latest (최신 메시지부터), 재시작: committed offset
                          // LATEST로 변경하여 Job 재시작 시 중복 처리 방지
                          .setStartingOffsets(OffsetsInitializer.committedOffsets(OffsetResetStrategy.LATEST))
                          .setValueOnlyDeserializer(new SimpleStringSchema())
                          .setProperties(kafkaProps)
                          .build();
    }

    /**
     * Order Items CDC 이벤트를 위한 Kafka Source 생성
     *
     * @return KafkaSource<String> - order-items-cdc에서 읽는 소스
     */
    public static KafkaSource<String> createOrderItemsSource() {
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("max.poll.records", ConfigLoader.get("kafka.consumer.max.poll.records", "500"));
        kafkaProps.setProperty("session.timeout.ms", ConfigLoader.get("kafka.consumer.session.timeout.ms", "30000"));
        kafkaProps.setProperty("enable.auto.commit", ConfigLoader.get("kafka.consumer.enable.auto.commit", "false"));

        return KafkaSource.<String>builder()
                          .setBootstrapServers(KAFKA_BROKERS)
                          .setTopics(ORDER_ITEMS_TOPIC)
                          .setGroupId(CONSUMER_GROUP + "-items")
                          // 첫 실행: latest (최신 메시지부터), 재시작: committed offset
                          .setStartingOffsets(OffsetsInitializer.committedOffsets(OffsetResetStrategy.LATEST))
                          .setValueOnlyDeserializer(new SimpleStringSchema())
                          .setProperties(kafkaProps)
                          .build();
    }

    /**
     * 개발/테스트용: 처음부터 읽는 Source
     */
    public static KafkaSource<String> createOrdersSourceFromEarliest() {
        return KafkaSource.<String>builder()
                          .setBootstrapServers(KAFKA_BROKERS)
                          .setTopics(ORDERS_TOPIC)
                          .setGroupId(CONSUMER_GROUP + "-dev")
                          .setStartingOffsets(OffsetsInitializer.earliest())
                          .setValueOnlyDeserializer(new SimpleStringSchema())
                          .build();
    }
}
