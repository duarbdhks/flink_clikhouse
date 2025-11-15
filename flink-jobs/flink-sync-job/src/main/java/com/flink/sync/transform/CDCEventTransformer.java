package com.flink.sync.transform;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.apache.flink.api.common.functions.MapFunction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/**
 * CDC 이벤트를 ClickHouse Row로 변환하는 Transformer
 *
 * 변환 로직:
 * - CREATE/READ/UPDATE: after 필드의 데이터 사용
 * - DELETE: before 필드의 데이터 사용 (cdc_op='d'로 표시)
 * - cdc_op: c(create), r(read/snapshot), u(update), d(delete)
 */
public class CDCEventTransformer implements MapFunction<String, ClickHouseRow> {

    private static final Logger LOG = LoggerFactory.getLogger(CDCEventTransformer.class);
    private static final ObjectMapper objectMapper;

    static {
        objectMapper = new ObjectMapper();
        objectMapper.registerModule(new JavaTimeModule());
    }

    private static final DateTimeFormatter DATE_TIME_FORMATTER =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'");

    @Override
    public ClickHouseRow map(String cdcEventJson) throws Exception {
        try {
            // JSON 파싱
            CDCEvent event = objectMapper.readValue(cdcEventJson, CDCEvent.class);

            // operation 타입에 따라 데이터 선택
            Map<String, Object> data;
            String operation = event.getOperation();

            if ("d".equals(operation)) {
                // DELETE: before 데이터 사용
                data = event.getBefore();
            } else {
                // CREATE, READ, UPDATE: after 데이터 사용
                data = event.getAfter();
            }

            if (data == null || data.isEmpty()) {
                LOG.warn("⚠️  CDC 이벤트에 데이터가 없습니다: {}", cdcEventJson);
                return null;
            }

            // ClickHouse Row 생성
            ClickHouseRow row = new ClickHouseRow();

            // 필드 매핑
            row.setId(getLongValue(data, "id"));
            row.setUserId(getLongValue(data, "user_id"));
            row.setStatus(getStringValue(data, "status"));
            row.setTotalAmount(getBigDecimalValue(data, "total_amount"));
            row.setCreatedAt(getTimestampValue(data, "created_at"));
            row.setUpdatedAt(getTimestampValue(data, "updated_at"));
            row.setCdcOp(operation);
            row.setCdcTsMs(event.getTimestampMs());

            LOG.debug("✅ CDC 이벤트 변환 성공: {} -> {}", operation, row.getId());

            return row;

        } catch (Exception e) {
            LOG.error("❌ CDC 이벤트 변환 실패: {}", cdcEventJson, e);
            // 실패한 이벤트는 null 반환 (필터링됨)
            return null;
        }
    }

    /**
     * Map에서 Long 값 추출
     */
    private Long getLongValue(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) {
            return null;
        }
        if (value instanceof Number) {
            return ((Number) value).longValue();
        }
        try {
            return Long.parseLong(value.toString());
        } catch (NumberFormatException e) {
            LOG.warn("⚠️  Long 변환 실패: {} = {}", key, value);
            return null;
        }
    }

    /**
     * Map에서 String 값 추출
     */
    private String getStringValue(Map<String, Object> data, String key) {
        Object value = data.get(key);
        return value != null ? value.toString() : null;
    }

    /**
     * Map에서 BigDecimal 값 추출
     */
    private BigDecimal getBigDecimalValue(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) {
            return null;
        }
        if (value instanceof BigDecimal) {
            return (BigDecimal) value;
        }
        if (value instanceof Number) {
            return BigDecimal.valueOf(((Number) value).doubleValue());
        }
        try {
            return new BigDecimal(value.toString());
        } catch (NumberFormatException e) {
            LOG.warn("⚠️  BigDecimal 변환 실패: {} = {}", key, value);
            return null;
        }
    }

    /**
     * Map에서 Timestamp 값 추출
     *
     * MySQL Debezium 포맷 예시:
     * - "2024-11-14T05:30:00Z"
     * - Long timestamp (milliseconds)
     */
    private Timestamp getTimestampValue(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) {
            return null;
        }

        try {
            // Long 타입 (milliseconds)
            if (value instanceof Number) {
                return new Timestamp(((Number) value).longValue());
            }

            // String 타입 (ISO 8601 포맷)
            String strValue = value.toString();

            // ISO 8601 포맷 파싱 (UTC 타임존 지원)
            if (strValue.contains("T")) {
                // ZonedDateTime으로 파싱하여 타임존 정보 유지
                Instant instant = Instant.parse(strValue);
                return Timestamp.from(instant);
            }

            // Long string
            return new Timestamp(Long.parseLong(strValue));

        } catch (Exception e) {
            LOG.warn("⚠️  Timestamp 변환 실패: {} = {}", key, value, e);
            return null;
        }
    }
}
