package com.flink.cdc.serialization;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.functions.FilterFunction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * CDC 이벤트를 테이블별로 라우팅하는 필터
 * Debezium CDC 이벤트 구조:
 * {
 * "source": {
 * "table": "orders" | "order_items",
 * "db": "order_db"
 * },
 * "op": "c" | "u" | "d" | "r",
 * "before": {...},
 * "after": {...}
 * }
 */
public class TableRouter implements FilterFunction<String> {

    private static final Logger LOG = LoggerFactory.getLogger(TableRouter.class);
    private static final ObjectMapper objectMapper = new ObjectMapper();

    private final String targetTableName;

    /**
     * 생성자
     *
     * @param targetTableName 필터링할 테이블 이름 (예: "orders", "order_items")
     */
    public TableRouter(String targetTableName) {
        this.targetTableName = targetTableName;
    }

    @Override
    public boolean filter(String cdcEvent) throws Exception {
        try {
            // CDC 이벤트 JSON 파싱
            JsonNode jsonNode = objectMapper.readTree(cdcEvent);

            // source.table 필드에서 테이블 이름 추출
            JsonNode sourceNode = jsonNode.get("source");
            if (sourceNode == null) {
                LOG.warn("⚠️  CDC 이벤트에 source 필드가 없습니다: {}", cdcEvent);
                return false;
            }

            JsonNode tableNode = sourceNode.get("table");
            if (tableNode == null) {
                LOG.warn("⚠️  CDC 이벤트에 source.table 필드가 없습니다: {}", cdcEvent);
                return false;
            }

            String tableName = tableNode.asText();

            // 대상 테이블과 일치하는지 확인
            boolean matches = targetTableName.equals(tableName);

            if (matches) {
                // 작업 타입 추출 (선택적 로깅)
                JsonNode opNode = jsonNode.get("op");
                String operation = opNode != null ? opNode.asText() : "unknown";

                LOG.debug("✅ {} 테이블 이벤트 필터링 성공: op={}", tableName, operation);
            }

            return matches;

        } catch (Exception e) {
            LOG.error("❌ CDC 이벤트 파싱 실패: {}", cdcEvent, e);
            // 파싱 실패 시 이벤트 제외
            return false;
        }
    }

    /**
     * 특정 operation만 필터링하는 고급 라우터
     */
    public static class OperationTableRouter implements FilterFunction<String> {
        private static final ObjectMapper objectMapper = new ObjectMapper();
        private final String targetTableName;
        private final String targetOperation; // "c", "u", "d", "r"

        public OperationTableRouter(String targetTableName, String targetOperation) {
            this.targetTableName = targetTableName;
            this.targetOperation = targetOperation;
        }

        @Override
        public boolean filter(String cdcEvent) throws Exception {
            try {
                JsonNode jsonNode = objectMapper.readTree(cdcEvent);

                // 테이블 이름 확인
                JsonNode sourceNode = jsonNode.get("source");
                if (sourceNode == null) return false;

                JsonNode tableNode = sourceNode.get("table");
                if (tableNode == null) return false;

                String tableName = tableNode.asText();
                if (!targetTableName.equals(tableName)) return false;

                // Operation 확인
                JsonNode opNode = jsonNode.get("op");
                if (opNode == null) return false;

                String operation = opNode.asText();
                return targetOperation.equals(operation);

            } catch (Exception e) {
                return false;
            }
        }
    }
}
