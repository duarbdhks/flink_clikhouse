package com.flink.cdc.config;

import com.ververica.cdc.connectors.mysql.source.MySqlSource;
import com.ververica.cdc.connectors.mysql.table.StartupOptions;
import com.ververica.cdc.debezium.JsonDebeziumDeserializationSchema;

import java.util.Properties;

/**
 * MySQL CDC Source 설정 클래스
 * MySQL binlog를 읽어 CDC 이벤트를 생성합니다.
 */
public class CDCSourceConfig {

    private static final String HOSTNAME = "mysql";
    private static final int PORT = 3306;
    private static final String USERNAME = "flink_cdc";
    private static final String PASSWORD = "flink_cdc_password";
    private static final String DATABASE_LIST = "order_db";
    private static final String TABLE_LIST = "order_db.orders,order_db.order_items";
    private static final String SERVER_ID = "5400-5404"; // Unique server ID for CDC
    private static final String SERVER_TIME_ZONE = "UTC";

    /**
     * MySQL CDC Source를 생성합니다.
     *
     * @return MySqlSource<String> - JSON 형식의 CDC 이벤트를 생성하는 소스
     */
    public static MySqlSource<String> createMySqlSource() {
        Properties jdbcProperties = new Properties();
        jdbcProperties.setProperty("characterEncoding", "utf-8");
        jdbcProperties.setProperty("useSSL", "false");
        jdbcProperties.setProperty("serverTimezone", SERVER_TIME_ZONE);

        Properties debeziumProperties = new Properties();
        debeziumProperties.setProperty("snapshot.mode", "initial");
        debeziumProperties.setProperty("decimal.handling.mode", "string");
        debeziumProperties.setProperty("bigint.unsigned.handling.mode", "long");
        debeziumProperties.setProperty("include.schema.changes", "false");

        return MySqlSource.<String>builder()
                          .hostname(HOSTNAME)
                          .port(PORT)
                          .username(USERNAME)
                          .password(PASSWORD)
                          .databaseList(DATABASE_LIST)
                          .tableList(TABLE_LIST)
                          .serverTimeZone(SERVER_TIME_ZONE)
                          .serverId(SERVER_ID)
                          // 초기 로드: 기존 데이터 전체 스냅샷 후 binlog 읽기
                          .startupOptions(StartupOptions.initial())
                          // CDC 이벤트를 JSON으로 역직렬화
                          .deserializer(new JsonDebeziumDeserializationSchema())
                          .jdbcProperties(jdbcProperties)
                          .debeziumProperties(debeziumProperties)
                          .build();
    }

    /**
     * Orders 테이블만을 위한 CDC Source 생성 (선택적)
     */
    public static MySqlSource<String> createOrdersSource() {
        return MySqlSource.<String>builder()
                          .hostname(HOSTNAME)
                          .port(PORT)
                          .username(USERNAME)
                          .password(PASSWORD)
                          .databaseList(DATABASE_LIST)
                          .tableList("order_db.orders")
                          .serverTimeZone(SERVER_TIME_ZONE)
                          .serverId(SERVER_ID)
                          .startupOptions(StartupOptions.initial())
                          .deserializer(new JsonDebeziumDeserializationSchema())
                          .build();
    }

    /**
     * Order Items 테이블만을 위한 CDC Source 생성 (선택적)
     */
    public static MySqlSource<String> createOrderItemsSource() {
        return MySqlSource.<String>builder()
                          .hostname(HOSTNAME)
                          .port(PORT)
                          .username(USERNAME)
                          .password(PASSWORD)
                          .databaseList(DATABASE_LIST)
                          .tableList("order_db.order_items")
                          .serverTimeZone(SERVER_TIME_ZONE)
                          .serverId("5405-5409") // Different server ID for separate source
                          .startupOptions(StartupOptions.initial())
                          .deserializer(new JsonDebeziumDeserializationSchema())
                          .build();
    }
}
