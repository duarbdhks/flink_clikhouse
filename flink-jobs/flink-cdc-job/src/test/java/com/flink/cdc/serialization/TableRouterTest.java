package com.flink.cdc.serialization;

import org.junit.Before;
import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/**
 * TableRouter 단위 테스트
 */
public class TableRouterTest {

    private TableRouter ordersRouter;
    private TableRouter orderItemsRouter;

    @Before
    public void setUp() {
        ordersRouter = new TableRouter("orders");
        orderItemsRouter = new TableRouter("order_items");
    }

    @Test
    public void testFilterOrdersTable() throws Exception {
        // Given: orders 테이블 CDC 이벤트
        String ordersEvent = "{"
                + "\"source\": {\"table\": \"orders\", \"db\": \"order_db\"},"
                + "\"op\": \"c\","
                + "\"after\": {\"id\": 1}"
                + "}";

        // When & Then: orders 라우터는 통과
        assertTrue(ordersRouter.filter(ordersEvent));

        // When & Then: order_items 라우터는 차단
        assertFalse(orderItemsRouter.filter(ordersEvent));
    }

    @Test
    public void testFilterOrderItemsTable() throws Exception {
        // Given: order_items 테이블 CDC 이벤트
        String orderItemsEvent = "{"
                + "\"source\": {\"table\": \"order_items\", \"db\": \"order_db\"},"
                + "\"op\": \"u\","
                + "\"after\": {\"id\": 1}"
                + "}";

        // When & Then: order_items 라우터는 통과
        assertTrue(orderItemsRouter.filter(orderItemsEvent));

        // When & Then: orders 라우터는 차단
        assertFalse(ordersRouter.filter(orderItemsEvent));
    }

    @Test
    public void testFilterWithoutSourceField() throws Exception {
        // Given: source 필드가 없는 잘못된 이벤트
        String invalidEvent = "{"
                + "\"op\": \"c\","
                + "\"after\": {\"id\": 1}"
                + "}";

        // When & Then: 모든 라우터가 차단
        assertFalse(ordersRouter.filter(invalidEvent));
        assertFalse(orderItemsRouter.filter(invalidEvent));
    }

    @Test
    public void testFilterWithoutTableField() throws Exception {
        // Given: source.table 필드가 없는 잘못된 이벤트
        String invalidEvent = "{"
                + "\"source\": {\"db\": \"order_db\"},"
                + "\"op\": \"c\","
                + "\"after\": {\"id\": 1}"
                + "}";

        // When & Then: 모든 라우터가 차단
        assertFalse(ordersRouter.filter(invalidEvent));
        assertFalse(orderItemsRouter.filter(invalidEvent));
    }

    @Test
    public void testFilterWithInvalidJson() throws Exception {
        // Given: 잘못된 JSON
        String invalidJson = "not a json";

        // When & Then: 파싱 실패로 차단
        assertFalse(ordersRouter.filter(invalidJson));
        assertFalse(orderItemsRouter.filter(invalidJson));
    }

    @Test
    public void testFilterDifferentOperations() throws Exception {
        // Given: 다양한 operation 타입의 이벤트
        String createEvent = createCdcEvent("orders", "c");
        String updateEvent = createCdcEvent("orders", "u");
        String deleteEvent = createCdcEvent("orders", "d");
        String readEvent = createCdcEvent("orders", "r");

        // When & Then: operation 타입과 관계없이 테이블 이름만 확인
        assertTrue(ordersRouter.filter(createEvent));
        assertTrue(ordersRouter.filter(updateEvent));
        assertTrue(ordersRouter.filter(deleteEvent));
        assertTrue(ordersRouter.filter(readEvent));
    }

    @Test
    public void testOperationTableRouter() throws Exception {
        // Given: CREATE operation만 필터링하는 라우터
        TableRouter.OperationTableRouter createOnlyRouter =
                new TableRouter.OperationTableRouter("orders", "c");

        String createEvent = createCdcEvent("orders", "c");
        String updateEvent = createCdcEvent("orders", "u");

        // When & Then: CREATE만 통과
        assertTrue(createOnlyRouter.filter(createEvent));
        assertFalse(createOnlyRouter.filter(updateEvent));
    }

    /**
     * 테스트용 CDC 이벤트 생성
     */
    private String createCdcEvent(String tableName, String operation) {
        return "{"
                + "\"source\": {\"table\": \"" + tableName + "\", \"db\": \"order_db\"},"
                + "\"op\": \"" + operation + "\","
                + "\"after\": {\"id\": 1}"
                + "}";
    }
}
