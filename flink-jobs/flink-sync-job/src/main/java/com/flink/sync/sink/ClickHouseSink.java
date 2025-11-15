package com.flink.sync.sink;

import com.flink.common.config.ConfigLoader;
import com.flink.sync.transform.ClickHouseRow;
import org.apache.flink.connector.jdbc.JdbcConnectionOptions;
import org.apache.flink.connector.jdbc.JdbcExecutionOptions;
import org.apache.flink.connector.jdbc.JdbcSink;
import org.apache.flink.connector.jdbc.JdbcStatementBuilder;
import org.apache.flink.streaming.api.functions.sink.SinkFunction;

import java.sql.PreparedStatement;
import java.sql.SQLException;

/**
 * ClickHouse Sink 설정
 * ClickHouse orders_realtime 테이블에 데이터를 삽입합니다.
 * <p>
 * application.properties 파일에서 설정을 동적으로 읽어옵니다.
 */
public class ClickHouseSink {

    // ClickHouse Sink 설정 (application.properties에서 로드)
    private static final String CLICKHOUSE_URL = ConfigLoader.get("clickhouse.url");
    private static final String CLICKHOUSE_DRIVER = ConfigLoader.get("clickhouse.driver");
    private static final String CLICKHOUSE_USER = ConfigLoader.get("clickhouse.username");
    private static final String CLICKHOUSE_PASSWORD = ConfigLoader.get("clickhouse.password");

    /**
     * Orders 테이블을 위한 ClickHouse Sink 생성
     * ReplacingMergeTree이므로 INSERT만 수행 (UPDATE/DELETE 없음)
     * ClickHouse가 자동으로 중복 제거 및 최신 버전 유지
     */
    public static SinkFunction<ClickHouseRow> createOrdersSink() {
        String insertSQL = "INSERT INTO orders_realtime (id, user_id, status, total_amount, created_at, updated_at, cdc_op, cdc_ts_ms, sync_timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, now())";
        int batchSize = ConfigLoader.getInt("clickhouse.batch.size", 1000);
        long batchIntervalMs = ConfigLoader.getLong("clickhouse.batch.interval.ms", 5000L);
        int maxRetries = ConfigLoader.getInt("clickhouse.max.retries", 3);

        return JdbcSink.sink(
                insertSQL,
                new OrdersStatementBuilder(),
                JdbcExecutionOptions.builder()
                                    .withBatchSize(batchSize)              // application.properties에서 로드
                                    .withBatchIntervalMs(batchIntervalMs)  // application.properties에서 로드
                                    .withMaxRetries(maxRetries)            // application.properties에서 로드
                                    .build(),
                new JdbcConnectionOptions.JdbcConnectionOptionsBuilder()
                        .withUrl(CLICKHOUSE_URL)
                        .withDriverName(CLICKHOUSE_DRIVER)
                        .withUsername(CLICKHOUSE_USER)
                        .withPassword(CLICKHOUSE_PASSWORD)
                        .build()
        );
    }

    /**
     * PreparedStatement에 ClickHouseRow 데이터를 바인딩
     */
    private static class OrdersStatementBuilder implements JdbcStatementBuilder<ClickHouseRow> {
        @Override
        public void accept(PreparedStatement ps, ClickHouseRow row) throws SQLException {
            ps.setLong(1, row.getId());
            ps.setLong(2, row.getUserId());
            ps.setString(3, row.getStatus());
            ps.setBigDecimal(4, row.getTotalAmount());
            ps.setTimestamp(5, row.getCreatedAt());
            ps.setTimestamp(6, row.getUpdatedAt());
            ps.setString(7, row.getCdcOp());
            ps.setLong(8, row.getCdcTsMs());
            // sync_timestamp는 now()로 자동 설정
        }
    }

    /**
     * 개발/테스트용: 작은 배치 크기로 빠른 싱크
     */
    public static SinkFunction<ClickHouseRow> createOrdersSinkFast() {
        String insertSQL = "INSERT INTO orders_realtime (id, user_id, status, total_amount, created_at, updated_at, cdc_op, cdc_ts_ms, sync_timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, now())";

        int fastBatchSize = ConfigLoader.getInt("clickhouse.fast.batch.size", 100);
        long fastBatchIntervalMs = ConfigLoader.getLong("clickhouse.fast.batch.interval.ms", 1000L);
        int maxRetries = ConfigLoader.getInt("clickhouse.max.retries", 3);

        return JdbcSink.sink(
                insertSQL,
                new OrdersStatementBuilder(),
                JdbcExecutionOptions.builder()
                                    .withBatchSize(fastBatchSize)              // application.properties에서 로드
                                    .withBatchIntervalMs(fastBatchIntervalMs)  // application.properties에서 로드
                                    .withMaxRetries(maxRetries)
                                    .build(),
                new JdbcConnectionOptions.JdbcConnectionOptionsBuilder()
                        .withUrl(CLICKHOUSE_URL)
                        .withDriverName(CLICKHOUSE_DRIVER)
                        .withUsername(CLICKHOUSE_USER)
                        .withPassword(CLICKHOUSE_PASSWORD)
                        .build()
        );
    }
}
