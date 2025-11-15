package com.flink.sync.transform;

import java.io.Serializable;
import java.math.BigDecimal;
import java.sql.Timestamp;

/**
 * ClickHouse orders_realtime 테이블 Row 모델
 *
 * ClickHouse 테이블 스키마:
 * - id BIGINT
 * - user_id BIGINT
 * - status VARCHAR
 * - total_amount DECIMAL(10,2)
 * - created_at TIMESTAMP
 * - updated_at TIMESTAMP
 * - cdc_op VARCHAR(1)
 * - cdc_ts_ms BIGINT
 * - sync_timestamp TIMESTAMP (자동)
 */
public class ClickHouseRow implements Serializable {
    private static final long serialVersionUID = 1L;

    private Long id;
    private Long userId;
    private String status;
    private BigDecimal totalAmount;
    private Timestamp createdAt;
    private Timestamp updatedAt;
    private String cdcOp;
    private Long cdcTsMs;

    // Constructors
    public ClickHouseRow() {
    }

    public ClickHouseRow(Long id, Long userId, String status, BigDecimal totalAmount,
                         Timestamp createdAt, Timestamp updatedAt, String cdcOp, Long cdcTsMs) {
        this.id = id;
        this.userId = userId;
        this.status = status;
        this.totalAmount = totalAmount;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
        this.cdcOp = cdcOp;
        this.cdcTsMs = cdcTsMs;
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public BigDecimal getTotalAmount() {
        return totalAmount;
    }

    public void setTotalAmount(BigDecimal totalAmount) {
        this.totalAmount = totalAmount;
    }

    public Timestamp getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Timestamp createdAt) {
        this.createdAt = createdAt;
    }

    public Timestamp getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Timestamp updatedAt) {
        this.updatedAt = updatedAt;
    }

    public String getCdcOp() {
        return cdcOp;
    }

    public void setCdcOp(String cdcOp) {
        this.cdcOp = cdcOp;
    }

    public Long getCdcTsMs() {
        return cdcTsMs;
    }

    public void setCdcTsMs(Long cdcTsMs) {
        this.cdcTsMs = cdcTsMs;
    }

    @Override
    public String toString() {
        return "ClickHouseRow{" +
                "id=" + id +
                ", userId=" + userId +
                ", status='" + status + '\'' +
                ", totalAmount=" + totalAmount +
                ", createdAt=" + createdAt +
                ", cdcOp='" + cdcOp + '\'' +
                '}';
    }
}
