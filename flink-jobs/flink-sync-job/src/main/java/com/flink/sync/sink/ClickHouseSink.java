package com.flink.sync.sink;

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
 */
public class ClickHouseSink {

    private static final String CLICKHOUSE_URL = "jdbc:clickhouse://clickhouse:8123/order_analytics";
    private static final String CLICKHOUSE_USER = "admin";
    private static final String CLICKHOUSE_PASSWORD = "test123";

    /**
     * Orders 테이블을 위한 ClickHouse Sink 생성
     * ReplacingMergeTree이므로 INSERT만 수행 (UPDATE/DELETE 없음)
     * ClickHouse가 자동으로 중복 제거 및 최신 버전 유지
     */
    public static SinkFunction<ClickHouseRow> createOrdersSink() {
        String insertSQL = "INSERT INTO orders_realtime (" +
                "id, user_id, status, total_amount, created_at, updated_at, " +
                "cdc_op, cdc_ts_ms, sync_timestamp" +
                ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, now())";

        return JdbcSink.sink(
                insertSQL,
                new OrdersStatementBuilder(),
                JdbcExecutionOptions.builder()
                                    .withBatchSize(1000)           // 1000건씩 배치 insert
                                    .withBatchIntervalMs(5000L)    // 최대 5초 대기
                                    .withMaxRetries(3)             // 실패 시 3회 재시도
                                    .build(),
                new JdbcConnectionOptions.JdbcConnectionOptionsBuilder()
                        .withUrl(CLICKHOUSE_URL)
                        .withDriverName("com.clickhouse.jdbc.ClickHouseDriver")
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
        String insertSQL = "INSERT INTO orders_realtime (" +
                "id, user_id, status, total_amount, created_at, updated_at, " +
                "cdc_op, cdc_ts_ms, sync_timestamp" +
                ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, now())";

        return JdbcSink.sink(
                insertSQL,
                new OrdersStatementBuilder(),
                JdbcExecutionOptions.builder()
                                    .withBatchSize(100)            // 100건씩 배치
                                    .withBatchIntervalMs(1000L)    // 1초 간격
                                    .withMaxRetries(3)
                                    .build(),
                new JdbcConnectionOptions.JdbcConnectionOptionsBuilder()
                        .withUrl(CLICKHOUSE_URL)
                        .withDriverName("com.clickhouse.jdbc.ClickHouseDriver")
                        .withUsername(CLICKHOUSE_USER)
                        .withPassword(CLICKHOUSE_PASSWORD)
                        .build()
        );
    }
}
