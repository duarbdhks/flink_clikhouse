package com.flink.cdc.config;

import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.base.DeliveryGuarantee;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;

import java.util.Properties;

/**
 * Kafka Sink 설정 클래스
 * CDC 이벤트를 Kafka 토픽으로 전송합니다.
 */
public class KafkaSinkConfig {

    private static final String KAFKA_BROKERS = "kafka:9092";
    private static final String ORDERS_TOPIC = "orders-cdc-topic";
    private static final String ORDER_ITEMS_TOPIC = "order-items-cdc-topic";

    /**
     * Orders CDC 이벤트를 위한 Kafka Sink 생성
     *
     * @return KafkaSink<String> - orders-cdc-topic으로 전송하는 Sink
     */
    public static KafkaSink<String> createOrdersSink() {
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("transaction.timeout.ms", "900000"); // 15 minutes

        return KafkaSink.<String>builder()
                        .setBootstrapServers(KAFKA_BROKERS)
                        .setRecordSerializer(
                                KafkaRecordSerializationSchema.builder()
                                                              .setTopic(ORDERS_TOPIC)
                                                              .setValueSerializationSchema(new SimpleStringSchema())
                                                              .build()
                        )
                        // EXACTLY_ONCE 보장 (Kafka 트랜잭션 사용)
                        .setDeliveryGuarantee(DeliveryGuarantee.EXACTLY_ONCE)
                        .setTransactionalIdPrefix("flink-cdc-orders-")
                        .setKafkaProducerConfig(kafkaProps)
                        .build();
    }

    /**
     * Order Items CDC 이벤트를 위한 Kafka Sink 생성
     *
     * @return KafkaSink<String> - order-items-cdc-topic으로 전송하는 Sink
     */
    public static KafkaSink<String> createOrderItemsSink() {
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("transaction.timeout.ms", "900000");

        return KafkaSink.<String>builder()
                        .setBootstrapServers(KAFKA_BROKERS)
                        .setRecordSerializer(
                                KafkaRecordSerializationSchema.builder()
                                                              .setTopic(ORDER_ITEMS_TOPIC)
                                                              .setValueSerializationSchema(new SimpleStringSchema())
                                                              .build()
                        )
                        .setDeliveryGuarantee(DeliveryGuarantee.EXACTLY_ONCE)
                        .setTransactionalIdPrefix("flink-cdc-order-items-")
                        .setKafkaProducerConfig(kafkaProps)
                        .build();
    }

    /**
     * 통합 CDC 이벤트를 위한 Kafka Sink 생성 (단일 토픽)
     * 테이블 구분은 CDC 이벤트의 source.table 필드로 수행
     *
     * @return KafkaSink<String> - orders-cdc-topic으로 전송하는 Sink
     */
    public static KafkaSink<String> createUnifiedSink() {
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("transaction.timeout.ms", "900000");
        kafkaProps.setProperty("compression.type", "snappy"); // 압축 활성화
        kafkaProps.setProperty("linger.ms", "100"); // 배치 처리 최적화
        kafkaProps.setProperty("batch.size", "16384"); // 16KB 배치 크기

        return KafkaSink.<String>builder()
                        .setBootstrapServers(KAFKA_BROKERS)
                        .setRecordSerializer(
                                KafkaRecordSerializationSchema.builder()
                                                              .setTopic(ORDERS_TOPIC)
                                                              .setValueSerializationSchema(new SimpleStringSchema())
                                                              .build()
                        )
                        .setDeliveryGuarantee(DeliveryGuarantee.EXACTLY_ONCE)
                        .setTransactionalIdPrefix("flink-cdc-unified-")
                        .setKafkaProducerConfig(kafkaProps)
                        .build();
    }

    /**
     * 개발/테스트용 AT_LEAST_ONCE 보장 Sink (성능 우선)
     */
    public static KafkaSink<String> createAtLeastOnceSink(String topic) {
        return KafkaSink.<String>builder()
                        .setBootstrapServers(KAFKA_BROKERS)
                        .setRecordSerializer(
                                KafkaRecordSerializationSchema.builder()
                                                              .setTopic(topic)
                                                              .setValueSerializationSchema(new SimpleStringSchema())
                                                              .build()
                        )
                        .setDeliveryGuarantee(DeliveryGuarantee.AT_LEAST_ONCE)
                        .build();
    }
}
