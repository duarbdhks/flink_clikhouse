package com.flink.cdc.config;

import com.ververica.cdc.connectors.mysql.source.MySqlSource;
import org.junit.Test;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNotSame;

/**
 * CDCSourceConfig 단위 테스트
 */
public class CDCSourceConfigTest {

    @Test
    public void testCreateMySqlSource() {
        // When: MySQL CDC Source 생성
        MySqlSource<String> source = CDCSourceConfig.createMySqlSource();

        // Then: Source가 정상적으로 생성됨
        assertNotNull("MySQL Source should not be null", source);
    }

    @Test
    public void testCreateOrdersSource() {
        // When: Orders 전용 Source 생성
        MySqlSource<String> source = CDCSourceConfig.createOrdersSource();

        // Then: Source가 정상적으로 생성됨
        assertNotNull("Orders Source should not be null", source);
    }

    @Test
    public void testCreateOrderItemsSource() {
        // When: OrderItems 전용 Source 생성
        MySqlSource<String> source = CDCSourceConfig.createOrderItemsSource();

        // Then: Source가 정상적으로 생성됨
        assertNotNull("OrderItems Source should not be null", source);
    }

    @Test
    public void testSourcesAreIndependent() {
        // When: 여러 Source를 생성
        MySqlSource<String> source1 = CDCSourceConfig.createMySqlSource();
        MySqlSource<String> source2 = CDCSourceConfig.createMySqlSource();

        // Then: 각각 독립적인 인스턴스
        assertNotNull(source1);
        assertNotNull(source2);
        assertNotSame("Sources should be different instances", source1, source2);
    }
}
