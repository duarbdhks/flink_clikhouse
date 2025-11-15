package com.flink.cdc.config;

import com.ververica.cdc.connectors.mysql.source.MySqlSource;
import com.ververica.cdc.connectors.mysql.table.StartupOptions;
import com.ververica.cdc.debezium.JsonDebeziumDeserializationSchema;

import java.util.Properties;

/**
 * MySQL CDC Source 설정 클래스
 * MySQL binlog를 읽어 CDC 이벤트를 생성합니다.
 * <p>
 * application.properties 파일에서 설정을 동적으로 읽어옵니다.
 */
public class CDCSourceConfig {

    // MySQL CDC Source 설정 (application.properties에서 로드)
    private static final String HOSTNAME = ConfigLoader.get("mysql.hostname");
    private static final int PORT = ConfigLoader.getInt("mysql.port");
    private static final String USERNAME = ConfigLoader.get("mysql.username");
    private static final String PASSWORD = ConfigLoader.get("mysql.password");
    private static final String DATABASE_LIST = ConfigLoader.get("mysql.database.list");
    private static final String TABLE_LIST = ConfigLoader.get("mysql.table.list");
    private static final String SERVER_ID = ConfigLoader.get("mysql.server.id");
    private static final String SERVER_TIME_ZONE = ConfigLoader.get("mysql.server.timezone", "UTC");

    /**
     * MySQL CDC Source를 생성합니다.
     *
     * @return MySqlSource<String> - JSON 형식의 CDC 이벤트를 생성하는 소스
     */
    public static MySqlSource<String> createMySqlSource() {
        // JDBC Properties (application.properties에서 로드)
        Properties jdbcProperties = new Properties();
        jdbcProperties.setProperty("characterEncoding", ConfigLoader.get("mysql.jdbc.characterEncoding", "utf-8"));
        jdbcProperties.setProperty("useSSL", ConfigLoader.get("mysql.jdbc.useSSL", "false"));
        jdbcProperties.setProperty("serverTimezone", ConfigLoader.get("mysql.jdbc.serverTimezone", SERVER_TIME_ZONE));

        // Debezium Properties (application.properties에서 로드)
        Properties debeziumProperties = new Properties();
        debeziumProperties.setProperty("snapshot.mode", ConfigLoader.get("debezium.snapshot.mode", "initial"));
        debeziumProperties.setProperty("decimal.handling.mode", ConfigLoader.get("debezium.decimal.handling.mode", "string"));
        debeziumProperties.setProperty("bigint.unsigned.handling.mode", ConfigLoader.get("debezium.bigint.unsigned.handling.mode", "long"));
        debeziumProperties.setProperty("include.schema.changes", ConfigLoader.get("debezium.include.schema.changes", "false"));

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
