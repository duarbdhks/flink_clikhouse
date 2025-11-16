package com.flink.sync.transform;

import java.io.Serializable;
import java.math.BigDecimal;
import java.sql.Timestamp;

/**
 * ClickHouse order_items_realtime 테이블 Row 모델
 *
 * ClickHouse 테이블 스키마:
 * - id BIGINT
 * - order_id BIGINT
 * - product_id BIGINT
 * - product_name VARCHAR
 * - quantity INT
 * - price DECIMAL(10,2)
 * - subtotal DECIMAL(10,2)
 * - created_at TIMESTAMP
 * - updated_at TIMESTAMP
 * - deleted_at NULLABLE(TIMESTAMP)
 * - cdc_op VARCHAR(1)
 * - cdc_ts_ms BIGINT (버전 컬럼 - ReplacingMergeTree 중복 제거용)
 */
public class OrderItemsRow implements CDCRow {
    private static final long serialVersionUID = 1L;

    private Long id;
    private Long orderId;
    private Long productId;
    private String productName;
    private Integer quantity;
    private BigDecimal price;
    private BigDecimal subtotal;
    private Timestamp createdAt;
    private Timestamp updatedAt;
    private Timestamp deletedAt;  // Soft Delete 지원
    private String cdcOp;
    private Long cdcTsMs;

    // Constructors
    public OrderItemsRow() {
    }

    public OrderItemsRow(Long id, Long orderId, Long productId, String productName,
                         Integer quantity, BigDecimal price, BigDecimal subtotal,
                         Timestamp createdAt, Timestamp updatedAt, Timestamp deletedAt,
                         String cdcOp, Long cdcTsMs) {
        this.id = id;
        this.orderId = orderId;
        this.productId = productId;
        this.productName = productName;
        this.quantity = quantity;
        this.price = price;
        this.subtotal = subtotal;
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

    public Long getOrderId() {
        return orderId;
    }

    public void setOrderId(Long orderId) {
        this.orderId = orderId;
    }

    public Long getProductId() {
        return productId;
    }

    public void setProductId(Long productId) {
        this.productId = productId;
    }

    public String getProductName() {
        return productName;
    }

    public void setProductName(String productName) {
        this.productName = productName;
    }

    public Integer getQuantity() {
        return quantity;
    }

    public void setQuantity(Integer quantity) {
        this.quantity = quantity;
    }

    public BigDecimal getPrice() {
        return price;
    }

    public void setPrice(BigDecimal price) {
        this.price = price;
    }

    public BigDecimal getSubtotal() {
        return subtotal;
    }

    public void setSubtotal(BigDecimal subtotal) {
        this.subtotal = subtotal;
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
        return "OrderItemsRow{" +
                "id=" + id +
                ", orderId=" + orderId +
                ", productId=" + productId +
                ", productName='" + productName + '\'' +
                ", quantity=" + quantity +
                ", price=" + price +
                ", subtotal=" + subtotal +
                ", createdAt=" + createdAt +
                ", cdcOp='" + cdcOp + '\'' +
                '}';
    }
}
