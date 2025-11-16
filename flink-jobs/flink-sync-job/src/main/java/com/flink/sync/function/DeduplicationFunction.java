package com.flink.sync.function;

import com.flink.sync.transform.ClickHouseRow;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.api.common.time.Time;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 중복 제거 함수 (Deduplication Function)
 * CDC 이벤트의 중복을 필터링하여 ClickHouse에 동일한 데이터가 반복 삽입되는 것을 방지합니다.
 * 동작 원리:
 * 1. KeyBy를 통해 id로 이벤트를 그룹화
 * 2. ValueState를 사용하여 이미 처리된 이벤트인지 확인
 * 3. 처음 보는 이벤트만 다음 단계로 전달
 * 4. State TTL(Time-To-Live)을 설정하여 메모리 효율성 보장
 * 사용 예시:
 * <pre>
 * DataStream<ClickHouseRow> deduplicated = clickHouseRowStream
 *     .keyBy(row -> String.valueOf(row.getId()))
 *     .process(new DeduplicationFunction(600)); // 600초 (10분) TTL - Production 권장
 * </pre>
 */
public class DeduplicationFunction extends KeyedProcessFunction<String, ClickHouseRow, ClickHouseRow> {

    private static final Logger LOG = LoggerFactory.getLogger(DeduplicationFunction.class);

    // State TTL (초 단위) - 이 시간이 지나면 State가 자동으로 정리됨
    private final int stateTtlSeconds;

    // 중복 체크를 위한 State (이벤트가 이미 처리되었는지 여부)
    private transient ValueState<Boolean> seenState;

    /**
     * DeduplicationFunction 생성자
     *
     * @param stateTtlSeconds State 보관 시간 (초).
     *                        이 시간이 지나면 State가 삭제되어 메모리 효율성 보장.
     *                        권장값: 600초 (10분) - Production 표준 (네트워크 지연, 재시도, restart 고려)
     *                        개발 환경: 60초도 가능하지만 restart 시 중복 발생 가능
     */
    public DeduplicationFunction(int stateTtlSeconds) {
        this.stateTtlSeconds = stateTtlSeconds;
    }

    @Override
    public void open(Configuration parameters) throws Exception {
        // ValueState 설정: Boolean 타입 (처리 여부만 저장)
        ValueStateDescriptor<Boolean> descriptor = new ValueStateDescriptor<>(
                "seen-state", // State 이름
                Boolean.class // State 타입
        );

        // State TTL 설정 (메모리 효율성을 위해 일정 시간 후 자동 삭제)
        org.apache.flink.api.common.state.StateTtlConfig ttlConfig = org.apache.flink.api.common.state.StateTtlConfig
                .newBuilder(Time.seconds(stateTtlSeconds))
                .setUpdateType(org.apache.flink.api.common.state.StateTtlConfig.UpdateType.OnCreateAndWrite)
                .setStateVisibility(org.apache.flink.api.common.state.StateTtlConfig.StateVisibility.NeverReturnExpired)
                .build();

        descriptor.enableTimeToLive(ttlConfig);
        seenState = getRuntimeContext().getState(descriptor);

        LOG.info("✅ DeduplicationFunction 초기화 완료 (State TTL: {}초)", stateTtlSeconds);
    }

    @Override
    public void processElement(
            ClickHouseRow value,
            Context ctx,
            Collector<ClickHouseRow> out
    ) throws Exception {

        // State에서 이미 처리된 이벤트인지 확인
        Boolean hasSeen = seenState.value();

        if (hasSeen == null) {
            // 첫 번째로 보는 이벤트 → State에 기록하고 다음 단계로 전달
            seenState.update(true);
            out.collect(value);

            if (LOG.isDebugEnabled()) {
                LOG.debug("✅ 신규 이벤트: id={}, cdc_ts_ms={}, operation={}",
                          value.getId(), value.getCdcTsMs(), value.getCdcOp());
            }
        } else {
            // 이미 처리된 중복 이벤트 → 필터링 (다음 단계로 전달하지 않음)
            LOG.warn("⚠️ 중복 이벤트 필터링: id={}, cdc_ts_ms={}, operation={}",
                     value.getId(), value.getCdcTsMs(), value.getCdcOp());
        }
    }
}
