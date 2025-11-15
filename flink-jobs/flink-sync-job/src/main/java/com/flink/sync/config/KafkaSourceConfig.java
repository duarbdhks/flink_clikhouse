package com.flink.sync.config;

import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;

import java.util.Properties;

/**
 * Kafka Source 설정 클래스
 * CDC 이벤트를 Kafka 토픽에서 읽어옵니다.
 */
public class KafkaSourceConfig {

    private static final String KAFKA_BROKERS = "kafka:9092";
    private static final String ORDERS_TOPIC = "orders-cdc-topic";
    private static final String ORDER_ITEMS_TOPIC = "order-items-cdc-topic";
    private static final String CONSUMER_GROUP = "flink-clickhouse-sync-group";

    /**
     * Orders CDC 이벤트를 위한 Kafka Source 생성
     *
     * @return KafkaSource<String> - orders-cdc-topic에서 읽는 소스
     */
    public static KafkaSource<String> createOrdersSource() {
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("max.poll.records", "500");
        kafkaProps.setProperty("session.timeout.ms", "30000");
        kafkaProps.setProperty("enable.auto.commit", "false"); // Flink가 offset 관리

        return KafkaSource.<String>builder()
                .setBootstrapServers(KAFKA_BROKERS)
                .setTopics(ORDERS_TOPIC)
                .setGroupId(CONSUMER_GROUP)
                // 첫 실행: earliest (모든 메시지), 재시작: committed offset
                .setStartingOffsets(OffsetsInitializer.committedOffsets())
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .setProperties(kafkaProps)
                .build();
    }

    /**
     * Order Items CDC 이벤트를 위한 Kafka Source 생성
     *
     * @return KafkaSource<String> - order-items-cdc-topic에서 읽는 소스
     */
    public static KafkaSource<String> createOrderItemsSource() {
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("max.poll.records", "500");
        kafkaProps.setProperty("session.timeout.ms", "30000");
        kafkaProps.setProperty("enable.auto.commit", "false");

        return KafkaSource.<String>builder()
                .setBootstrapServers(KAFKA_BROKERS)
                .setTopics(ORDER_ITEMS_TOPIC)
                .setGroupId(CONSUMER_GROUP + "-items")
                .setStartingOffsets(OffsetsInitializer.committedOffsets())
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
