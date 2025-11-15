package com.flink.sync.transform;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.io.Serializable;
import java.util.Map;

/**
 * Debezium CDC 이벤트 모델
 *
 * CDC 이벤트 JSON 구조:
 * {
 *   "before": {...},      // UPDATE/DELETE의 경우 변경 전 값
 *   "after": {...},       // CREATE/UPDATE의 경우 변경 후 값
 *   "source": {
 *     "db": "order_db",
 *     "table": "orders",
 *     "ts_ms": 1699999999999
 *   },
 *   "op": "c" | "u" | "d" | "r",  // create, update, delete, read(snapshot)
 *   "ts_ms": 1699999999999
 * }
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class CDCEvent implements Serializable {
    private static final long serialVersionUID = 1L;

    @JsonProperty("before")
    private Map<String, Object> before;

    @JsonProperty("after")
    private Map<String, Object> after;

    @JsonProperty("source")
    private Source source;

    @JsonProperty("op")
    private String operation;

    @JsonProperty("ts_ms")
    private Long timestampMs;

    // Getters and Setters
    public Map<String, Object> getBefore() {
        return before;
    }

    public void setBefore(Map<String, Object> before) {
        this.before = before;
    }

    public Map<String, Object> getAfter() {
        return after;
    }

    public void setAfter(Map<String, Object> after) {
        this.after = after;
    }

    public Source getSource() {
        return source;
    }

    public void setSource(Source source) {
        this.source = source;
    }

    public String getOperation() {
        return operation;
    }

    public void setOperation(String operation) {
        this.operation = operation;
    }

    public Long getTimestampMs() {
        return timestampMs;
    }

    public void setTimestampMs(Long timestampMs) {
        this.timestampMs = timestampMs;
    }

    /**
     * Source 메타데이터
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Source implements Serializable {
        private static final long serialVersionUID = 1L;

        @JsonProperty("db")
        private String database;

        @JsonProperty("table")
        private String table;

        @JsonProperty("ts_ms")
        private Long timestampMs;

        // Getters and Setters
        public String getDatabase() {
            return database;
        }

        public void setDatabase(String database) {
            this.database = database;
        }

        public String getTable() {
            return table;
        }

        public void setTable(String table) {
            this.table = table;
        }

        public Long getTimestampMs() {
            return timestampMs;
        }

        public void setTimestampMs(Long timestampMs) {
            this.timestampMs = timestampMs;
        }
    }

    @Override
    public String toString() {
        return "CDCEvent{" +
                "operation='" + operation + '\'' +
                ", table='" + (source != null ? source.getTable() : "null") + '\'' +
                ", timestamp=" + timestampMs +
                '}';
    }
}
