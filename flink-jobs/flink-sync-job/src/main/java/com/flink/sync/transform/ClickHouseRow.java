package com.flink.sync.transform;

import java.io.Serializable;
import java.math.BigDecimal;
import java.sql.Timestamp;

/**
 * ClickHouse orders_realtime 테이블 Row 모델
 *
 * ClickHouse 테이블 스키마 (멱등성 보장 버전):
 * - id BIGINT
 * - user_id BIGINT
 * - status VARCHAR
 * - total_amount DECIMAL(10,2)
 * - created_at TIMESTAMP
 * - updated_at TIMESTAMP
 * - deleted_at NULLABLE(TIMESTAMP)
 * - cdc_op VARCHAR(1)
 * - cdc_ts_ms BIGINT (버전 컬럼 - ReplacingMergeTree 중복 제거용)
 */
public class ClickHouseRow implements Serializable {
    private static final long serialVersionUID = 1L;

    private Long id;
    private Long userId;
    private String status;
    private BigDecimal totalAmount;
    private Timestamp createdAt;
    private Timestamp updatedAt;
    private Timestamp deletedAt;  // Soft Delete 지원
    private String cdcOp;
    private Long cdcTsMs;

    // Constructors
    public ClickHouseRow() {
    }

    public ClickHouseRow(Long id, Long userId, String status, BigDecimal totalAmount,
                         Timestamp createdAt, Timestamp updatedAt, Timestamp deletedAt,
                         String cdcOp, Long cdcTsMs) {
        this.id = id;
        this.userId = userId;
        this.status = status;
        this.totalAmount = totalAmount;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
        this.deletedAt = deletedAt;
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

    public Timestamp getDeletedAt() {
        return deletedAt;
    }

    public void setDeletedAt(Timestamp deletedAt) {
        this.deletedAt = deletedAt;
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
