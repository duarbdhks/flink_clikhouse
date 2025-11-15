package com.flink.cdc.config;

import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.junit.Test;

import static org.junit.Assert.*;

/**
 * KafkaSinkConfig 단위 테스트
 */
public class KafkaSinkConfigTest {

    @Test
    public void testCreateOrdersSink() {
        // When: Orders Kafka Sink 생성
        KafkaSink<String> sink = KafkaSinkConfig.createOrdersSink();

        // Then: Sink가 정상적으로 생성됨
        assertNotNull("Orders Sink should not be null", sink);
    }

    @Test
    public void testCreateOrderItemsSink() {
        // When: OrderItems Kafka Sink 생성
        KafkaSink<String> sink = KafkaSinkConfig.createOrderItemsSink();

        // Then: Sink가 정상적으로 생성됨
        assertNotNull("OrderItems Sink should not be null", sink);
    }

    @Test
    public void testCreateUnifiedSink() {
        // When: 통합 Kafka Sink 생성
        KafkaSink<String> sink = KafkaSinkConfig.createUnifiedSink();

        // Then: Sink가 정상적으로 생성됨
        assertNotNull("Unified Sink should not be null", sink);
    }

    @Test
    public void testCreateAtLeastOnceSink() {
        // When: AT_LEAST_ONCE Sink 생성
        KafkaSink<String> sink = KafkaSinkConfig.createAtLeastOnceSink("test-topic");

        // Then: Sink가 정상적으로 생성됨
        assertNotNull("AT_LEAST_ONCE Sink should not be null", sink);
    }

    @Test
    public void testSinksAreIndependent() {
        // When: 여러 Sink를 생성
        KafkaSink<String> sink1 = KafkaSinkConfig.createOrdersSink();
        KafkaSink<String> sink2 = KafkaSinkConfig.createOrdersSink();

        // Then: 각각 독립적인 인스턴스
        assertNotNull(sink1);
        assertNotNull(sink2);
        assertNotSame("Sinks should be different instances", sink1, sink2);
    }

    @Test
    public void testDifferentSinksForDifferentTopics() {
        // When: 다른 토픽용 Sink 생성
        KafkaSink<String> ordersSink = KafkaSinkConfig.createOrdersSink();
        KafkaSink<String> orderItemsSink = KafkaSinkConfig.createOrderItemsSink();

        // Then: 각각 독립적인 인스턴스
        assertNotNull(ordersSink);
        assertNotNull(orderItemsSink);
        assertNotSame("Different topic sinks should be different instances",
                ordersSink, orderItemsSink);
    }
}
