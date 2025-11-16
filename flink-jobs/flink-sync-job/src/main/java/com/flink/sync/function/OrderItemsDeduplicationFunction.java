package com.flink.sync.function;

import com.flink.sync.transform.OrderItemsRow;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.api.common.time.Time;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * OrderItems 중복 제거 함수
 * DeduplicationFunction과 동일한 로직이지만 OrderItemsRow 전용
 */
public class OrderItemsDeduplicationFunction extends KeyedProcessFunction<String, OrderItemsRow, OrderItemsRow> {

    private static final Logger LOG = LoggerFactory.getLogger(OrderItemsDeduplicationFunction.class);

    private final int stateTtlSeconds;
    private transient ValueState<Boolean> seenState;

    public OrderItemsDeduplicationFunction(int stateTtlSeconds) {
        this.stateTtlSeconds = stateTtlSeconds;
    }

    @Override
    public void open(Configuration parameters) throws Exception {
        ValueStateDescriptor<Boolean> descriptor = new ValueStateDescriptor<>(
                "seen-state",
                Boolean.class
        );

        org.apache.flink.api.common.state.StateTtlConfig ttlConfig = org.apache.flink.api.common.state.StateTtlConfig
                .newBuilder(Time.seconds(stateTtlSeconds))
                .setUpdateType(org.apache.flink.api.common.state.StateTtlConfig.UpdateType.OnCreateAndWrite)
                .setStateVisibility(org.apache.flink.api.common.state.StateTtlConfig.StateVisibility.NeverReturnExpired)
                .build();

        descriptor.enableTimeToLive(ttlConfig);
        seenState = getRuntimeContext().getState(descriptor);

        LOG.info("✅ OrderItemsDeduplicationFunction 초기화 완료 (State TTL: {}초)", stateTtlSeconds);
    }

    @Override
    public void processElement(
            OrderItemsRow value,
            Context ctx,
            Collector<OrderItemsRow> out
    ) throws Exception {

        Boolean hasSeen = seenState.value();

        if (hasSeen == null) {
            seenState.update(true);
            out.collect(value);

            if (LOG.isDebugEnabled()) {
                LOG.debug("✅ 신규 OrderItems 이벤트: id={}, cdc_ts_ms={}, operation={}",
                          value.getId(), value.getCdcTsMs(), value.getCdcOp());
            }
        } else {
            LOG.warn("⚠️ OrderItems 중복 이벤트 필터링: id={}, cdc_ts_ms={}, operation={}",
                     value.getId(), value.getCdcTsMs(), value.getCdcOp());
        }
    }
}
