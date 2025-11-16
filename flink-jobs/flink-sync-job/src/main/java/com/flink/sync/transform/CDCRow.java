package com.flink.sync.transform;

import java.io.Serializable;

/**
 * CDC 이벤트로부터 변환된 Row 공통 인터페이스
 * DeduplicationFunction에서 제네릭 타입으로 사용
 */
public interface CDCRow extends Serializable {
    /**
     * Row의 고유 ID 반환 (중복 제거 키로 사용)
     */
    Long getId();

    /**
     * CDC 타임스탬프 반환 (ReplacingMergeTree 버전 컬럼)
     */
    Long getCdcTsMs();

    /**
     * CDC 작업 타입 반환 (c=create, r=read, u=update, d=delete)
     */
    String getCdcOp();
}
