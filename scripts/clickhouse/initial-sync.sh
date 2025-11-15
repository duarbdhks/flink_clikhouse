#!/bin/bash

# ============================================
# MySQL → ClickHouse 초기 데이터 동기화 스크립트
# 목적: 최초 MySQL의 기존 데이터를 ClickHouse로 동기화
# 방법: Flink CDC Snapshot 기능 활용
# ============================================

set -e  # 에러 발생 시 스크립트 중단

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 스크립트 디렉토리 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   MySQL → ClickHouse 초기 데이터 동기화${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 1. 사전 확인
echo -e "${BLUE}[1/6] 사전 확인${NC}"

# MySQL 데이터 확인
echo -e "${YELLOW}📊 MySQL 현재 데이터 확인:${NC}"
MYSQL_ORDER_COUNT=$(docker exec yeumgw-mysql mysql -uroot -ptest123 -se "SELECT COUNT(*) FROM order_db.orders WHERE deleted_at IS NULL")
MYSQL_ITEM_COUNT=$(docker exec yeumgw-mysql mysql -uroot -ptest123 -se "SELECT COUNT(*) FROM order_db.order_items WHERE deleted_at IS NULL")
MYSQL_ORDER_ID_RANGE=$(docker exec yeumgw-mysql mysql -uroot -ptest123 -se "SELECT CONCAT(MIN(id), '-', MAX(id)) FROM order_db.orders WHERE deleted_at IS NULL")

echo -e "   Orders: ${GREEN}${MYSQL_ORDER_COUNT}${NC}건 (ID 범위: ${MYSQL_ORDER_ID_RANGE})"
echo -e "   Order Items: ${GREEN}${MYSQL_ITEM_COUNT}${NC}건"
echo ""

if [ "$MYSQL_ORDER_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  MySQL에 데이터가 없습니다. 샘플 데이터를 먼저 삽입하세요.${NC}"
    echo -e "   실행: ${BLUE}bash scripts/setup/init-all.sh${NC}"
    exit 1
fi

# ClickHouse 데이터 확인
echo -e "${YELLOW}📊 ClickHouse 현재 데이터 확인:${NC}"
CH_ORDER_COUNT=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT COUNT(*) FROM order_analytics.orders_realtime WHERE deleted_at IS NULL" 2>/dev/null || echo "0")
CH_ITEM_COUNT=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT COUNT(*) FROM order_analytics.order_items_realtime WHERE deleted_at IS NULL" 2>/dev/null || echo "0")
CH_ORDER_ID_RANGE=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT concat(toString(min(id)), '-', toString(max(id))) FROM order_analytics.orders_realtime WHERE deleted_at IS NULL" 2>/dev/null || echo "0-0")

echo -e "   Orders: ${GREEN}${CH_ORDER_COUNT}${NC}건 (ID 범위: ${CH_ORDER_ID_RANGE})"
echo -e "   Order Items: ${GREEN}${CH_ITEM_COUNT}${NC}건"

# 중복 체크
CH_DUPLICATE_COUNT=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT COUNT(*) FROM (SELECT id FROM order_analytics.orders_realtime WHERE deleted_at IS NULL GROUP BY id HAVING COUNT(*) > 1)" 2>/dev/null || echo "0")

if [ "$CH_DUPLICATE_COUNT" -gt 0 ]; then
    echo -e "   ${RED}⚠️  중복된 ID 발견: ${CH_DUPLICATE_COUNT}개${NC}"
else
    echo -e "   ${GREEN}✓ 중복 없음${NC}"
fi
echo ""

# 2. Flink Jobs 상태 확인
echo -e "${BLUE}[2/6] Flink Jobs 상태 확인${NC}"

# CDC Job 확인
CDC_JOB_STATUS=$(docker exec yeumgw-flink-jobmanager flink list 2>/dev/null | grep "MySQL CDC" | grep "RUNNING" || echo "")
SYNC_JOB_STATUS=$(docker exec yeumgw-flink-jobmanager flink list 2>/dev/null | grep "ClickHouse" | grep "RUNNING" || echo "")

if [ -n "$CDC_JOB_STATUS" ]; then
    echo -e "${GREEN}✅ CDC Job이 이미 실행 중입니다${NC}"
    CDC_RUNNING=true
else
    echo -e "${YELLOW}⚠️  CDC Job이 실행 중이 아닙니다${NC}"
    CDC_RUNNING=false
fi

if [ -n "$SYNC_JOB_STATUS" ]; then
    echo -e "${GREEN}✅ Sync Job이 이미 실행 중입니다${NC}"
    SYNC_RUNNING=true
else
    echo -e "${YELLOW}⚠️  Sync Job이 실행 중이 아닙니다${NC}"
    SYNC_RUNNING=false
fi
echo ""

# 3. 초기화 전략 선택
echo -e "${BLUE}[3/6] 초기화 전략 선택${NC}"

if [ "$CDC_RUNNING" = true ] && [ "$SYNC_RUNNING" = true ]; then
    echo -e "${YELLOW}⚠️  Flink Jobs이 이미 실행 중입니다.${NC}"
    echo -e "${YELLOW}   기존 Job을 취소하고 재시작하여 스냅샷을 다시 읽습니다.${NC}"
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ 초기화를 취소했습니다${NC}"
        exit 1
    fi

    # 기존 Job 취소
    echo -e "${YELLOW}⏳ 기존 Flink Jobs 취소 중...${NC}"
    docker exec yeumgw-flink-jobmanager flink list | grep "RUNNING" | awk '{print $4}' | while read job_id; do
        docker exec yeumgw-flink-jobmanager flink cancel "$job_id" 2>/dev/null || true
    done
    echo -e "${GREEN}✅ 기존 Jobs 취소 완료${NC}"
    sleep 5
fi
echo ""

# 4. Kafka Consumer Group 오프셋 리셋
echo -e "${BLUE}[4/6] Kafka Consumer Group 오프셋 리셋${NC}"
echo -e "${YELLOW}⏳ Consumer Group 삭제 중...${NC}"

# Sync Job의 Consumer Group 삭제
docker exec yeumgw-kafka kafka-consumer-groups \
    --bootstrap-server localhost:9092 \
    --delete --group flink-clickhouse-sync-group 2>/dev/null || true

docker exec yeumgw-kafka kafka-consumer-groups \
    --bootstrap-server localhost:9092 \
    --delete --group flink-clickhouse-sync-group-items 2>/dev/null || true

echo -e "${GREEN}✅ Consumer Group 리셋 완료${NC}"
echo ""

# 5. ClickHouse 데이터 초기화
echo -e "${BLUE}[5/6] ClickHouse 데이터 초기화${NC}"
echo -e "${YELLOW}⚠️  기존 ClickHouse 데이터를 모두 삭제합니다.${NC}"
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 초기화를 취소했습니다${NC}"
    exit 1
fi

echo -e "${YELLOW}⏳ ClickHouse 테이블 초기화 중...${NC}"
docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "TRUNCATE TABLE order_analytics.orders_realtime"
docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "TRUNCATE TABLE order_analytics.order_items_realtime"

echo -e "${GREEN}✅ ClickHouse 초기화 완료${NC}"
echo ""

# 6. Flink Jobs 재시작 (Snapshot 모드)
echo -e "${BLUE}[6/6] Flink Jobs 시작 (Snapshot 모드)${NC}"

# CDC Job 시작
echo -e "${YELLOW}⏳ CDC Job 시작 중...${NC}"
CDC_JOB_ID=$(docker exec yeumgw-flink-jobmanager flink run -d \
    -c com.flink.cdc.job.MySQLCDCJob \
    /opt/flink/jobs/jars/flink-cdc-job.jar 2>&1 | grep "JobID" | awk '{print $NF}')

if [ -n "$CDC_JOB_ID" ]; then
    echo -e "${GREEN}✅ CDC Job 시작 완료 (Job ID: ${CDC_JOB_ID})${NC}"
else
    echo -e "${RED}❌ CDC Job 시작 실패${NC}"
    exit 1
fi

# CDC Job이 스냅샷을 완료할 때까지 대기 (약 10초)
echo -e "${YELLOW}⏳ CDC 스냅샷 완료 대기 중 (10초)...${NC}"
sleep 10

# Sync Job 시작
echo -e "${YELLOW}⏳ Sync Job 시작 중...${NC}"
SYNC_JOB_ID=$(docker exec yeumgw-flink-jobmanager flink run -d \
    -c com.flink.sync.job.KafkaToClickHouseJob \
    /opt/flink/jobs/jars/flink-sync-job.jar 2>&1 | grep "JobID" | awk '{print $NF}')

if [ -n "$SYNC_JOB_ID" ]; then
    echo -e "${GREEN}✅ Sync Job 시작 완료 (Job ID: ${SYNC_JOB_ID})${NC}"
else
    echo -e "${RED}❌ Sync Job 시작 실패${NC}"
    exit 1
fi

echo ""

# 동기화 대기
echo -e "${BLUE}⏳ 초기 동기화 진행 중 (약 30초 소요)...${NC}"
for i in {1..30}; do
    echo -n "."
    sleep 1

    # 10초마다 진행 상황 확인
    if [ $((i % 10)) -eq 0 ]; then
        CH_COUNT=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
            --query "SELECT COUNT(*) FROM order_analytics.orders_realtime WHERE deleted_at IS NULL" 2>/dev/null || echo "0")
        echo -ne "\n${YELLOW}   현재 ClickHouse Orders: ${CH_COUNT}/${MYSQL_ORDER_COUNT}${NC}\n"
    fi
done
echo ""

# 최종 검증
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   최종 검증${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# MySQL vs ClickHouse 데이터 비교
FINAL_CH_ORDER_COUNT=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT COUNT(*) FROM order_analytics.orders_realtime WHERE deleted_at IS NULL" 2>/dev/null || echo "0")
FINAL_CH_ITEM_COUNT=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT COUNT(*) FROM order_analytics.order_items_realtime WHERE deleted_at IS NULL" 2>/dev/null || echo "0")
FINAL_CH_ORDER_ID_RANGE=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT concat(toString(min(id)), '-', toString(max(id))) FROM order_analytics.orders_realtime WHERE deleted_at IS NULL" 2>/dev/null || echo "0-0")

echo -e "${YELLOW}📊 동기화 결과:${NC}"
echo ""
echo -e "  ${BLUE}Orders:${NC}"
echo -e "    MySQL: ${GREEN}${MYSQL_ORDER_COUNT}${NC}건 (ID: ${MYSQL_ORDER_ID_RANGE})"
echo -e "    ClickHouse: ${GREEN}${FINAL_CH_ORDER_COUNT}${NC}건 (ID: ${FINAL_CH_ORDER_ID_RANGE})"

# 중복 체크
FINAL_CH_DUPLICATE_COUNT=$(docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT COUNT(*) FROM (SELECT id FROM order_analytics.orders_realtime WHERE deleted_at IS NULL GROUP BY id HAVING COUNT(*) > 1)" 2>/dev/null || echo "0")

if [ "$MYSQL_ORDER_COUNT" -eq "$FINAL_CH_ORDER_COUNT" ] && [ "$MYSQL_ORDER_ID_RANGE" = "$FINAL_CH_ORDER_ID_RANGE" ] && [ "$FINAL_CH_DUPLICATE_COUNT" -eq 0 ]; then
    echo -e "    ${GREEN}✅ 동기화 성공! (개수, ID 범위, 중복 모두 일치)${NC}"
elif [ "$FINAL_CH_DUPLICATE_COUNT" -gt 0 ]; then
    echo -e "    ${RED}❌ 중복된 ID 발견: ${FINAL_CH_DUPLICATE_COUNT}개${NC}"
    echo -e "    ${YELLOW}ClickHouse를 TRUNCATE하고 다시 시도하세요.${NC}"
else
    echo -e "    ${RED}⚠️  데이터 불일치${NC}"
    echo -e "       개수: ${MYSQL_ORDER_COUNT} vs ${FINAL_CH_ORDER_COUNT}"
    echo -e "       ID 범위: ${MYSQL_ORDER_ID_RANGE} vs ${FINAL_CH_ORDER_ID_RANGE}"
    echo -e "    ${YELLOW}추가 대기 후 다시 확인하세요.${NC}"
fi
echo ""

echo -e "  ${BLUE}Order Items:${NC}"
echo -e "    MySQL: ${GREEN}${MYSQL_ITEM_COUNT}${NC}건"
echo -e "    ClickHouse: ${GREEN}${FINAL_CH_ITEM_COUNT}${NC}건"

if [ "$MYSQL_ITEM_COUNT" -eq "$FINAL_CH_ITEM_COUNT" ]; then
    echo -e "    ${GREEN}✅ 동기화 성공!${NC}"
else
    echo -e "    ${RED}⚠️  데이터 불일치 (${MYSQL_ITEM_COUNT} vs ${FINAL_CH_ITEM_COUNT})${NC}"
    echo -e "    ${YELLOW}추가 대기 후 다시 확인하세요.${NC}"
fi
echo ""

# 샘플 데이터 확인
echo -e "${YELLOW}📋 ClickHouse 샘플 데이터 (최근 5개 활성 주문):${NC}"
docker exec yeumgw-clickhouse-server clickhouse-client --user admin --password test123 \
    --query "SELECT id, user_id, status, total_amount, created_at, cdc_op FROM order_analytics.orders_realtime WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 5 FORMAT Pretty"
echo ""

# 완료 메시지
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✅ 초기 동기화 완료!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

echo -e "${BLUE}💡 다음 단계:${NC}"
echo -e "1. Flink Dashboard에서 Job 상태 확인: ${YELLOW}http://localhost:8081${NC}"
echo -e "2. Kafka UI에서 메시지 확인: ${YELLOW}http://localhost:8080${NC}"
echo -e "3. ClickHouse에서 실시간 조회 테스트:"
echo -e "   ${YELLOW}docker exec -it yeumgw-clickhouse-server clickhouse-client --user admin --password test123${NC}"
echo ""
