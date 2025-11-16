#!/bin/bash

# ============================================
# 전체 시스템 초기화 스크립트
# 목적: MySQL, ClickHouse, Kafka를 한 번에 초기화
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
DOCKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${DOCKER_DIR}/.." && pwd)"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Flink ClickHouse CDC 파이프라인${NC}"
echo -e "${BLUE}   전체 시스템 초기화${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 1. Docker Compose 서비스 시작
echo -e "${BLUE}[1/5] Docker Compose 서비스 시작${NC}"
cd "$PROJECT_ROOT"

if ! docker-compose ps | grep -q "Up"; then
    echo -e "${YELLOW}⏳ 서비스 시작 중...${NC}"
    docker-compose up -d mysql clickhouse kafka
    echo -e "${GREEN}✅ 서비스 시작 완료${NC}"
else
    echo -e "${GREEN}✅ 서비스가 이미 실행 중입니다${NC}"
fi
echo ""

# 2. 서비스 준비 대기
echo -e "${BLUE}[2/5] 서비스 준비 대기 (약 30초)${NC}"
echo -e "${YELLOW}⏳ MySQL 준비 중...${NC}"
until docker exec yeumgw-mysql mysqladmin ping -h localhost --silent; do
    echo -n "."
    sleep 2
done
echo -e "${GREEN}✅ MySQL 준비 완료${NC}"

echo -e "${YELLOW}⏳ ClickHouse 준비 중...${NC}"
until docker exec yeumgw-clickhouse-server clickhouse-client --query "SELECT 1" > /dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo -e "${GREEN}✅ ClickHouse 준비 완료${NC}"

echo -e "${YELLOW}⏳ Kafka 준비 중...${NC}"
sleep 10  # Kafka는 추가 대기 시간 필요
echo -e "${GREEN}✅ Kafka 준비 완료${NC}"
echo ""

# 3. MySQL 초기화
echo -e "${BLUE}[3/5] MySQL 데이터베이스 초기화${NC}"
docker exec -i yeumgw-mysql mysql -uroot -ptest123 < "${DOCKER_DIR}/init/sql/init-mysql.sql"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ MySQL 초기화 완료${NC}"
else
    echo -e "${RED}❌ MySQL 초기화 실패${NC}"
    exit 1
fi
echo ""

# 4. ClickHouse 초기화
echo -e "${BLUE}[4/5] ClickHouse 데이터베이스 초기화${NC}"
docker exec -i yeumgw-clickhouse-server clickhouse-client --multiquery < "${DOCKER_DIR}/init/sql/init-clickhouse.sql"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ClickHouse 초기화 완료${NC}"
else
    echo -e "${RED}❌ ClickHouse 초기화 실패${NC}"
    exit 1
fi
echo ""

# 5. Kafka Topics 생성
echo -e "${BLUE}[5/5] Kafka Topics 생성${NC}"
bash "${DOCKER_DIR}/init/kafka/create-topics.sh"
echo ""

# 완료 메시지
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✅ 전체 시스템 초기화 완료!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# 상태 확인
echo -e "${BLUE}📊 시스템 상태 확인:${NC}"
echo ""

echo -e "${YELLOW}MySQL 주문 데이터:${NC}"
docker exec yeumgw-mysql mysql -uroot -ptest123 -e "
USE order_db;
SELECT
    status,
    COUNT(*) as order_count,
    SUM(total_amount) as total_revenue
FROM orders
GROUP BY status
ORDER BY status;
"
echo ""

echo -e "${YELLOW}ClickHouse 테이블 목록:${NC}"
docker exec yeumgw-clickhouse-server clickhouse-client --query "
SELECT
    name AS table_name,
    engine,
    total_rows
FROM system.tables
WHERE database = 'order_analytics'
ORDER BY name;
" --format Pretty
echo ""

echo -e "${YELLOW}Kafka Topics:${NC}"
docker exec yeumgw-kafka kafka-topics --bootstrap-server localhost:9092 --list
echo ""

# 다음 단계 안내
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}   다음 단계${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo -e "1. Flink CDC Job 제출:"
echo -e "   ${YELLOW}flink run --detached --class com.example.MySQLCDCJob flink-cdc-job.jar${NC}"
echo ""
echo -e "2. Flink Sync Job 제출:"
echo -e "   ${YELLOW}flink run --detached --class com.example.KafkaToClickHouseJob flink-sync-job.jar${NC}"
echo ""
echo -e "3. NestJS API 시작:"
echo -e "   ${YELLOW}docker-compose up -d platform-api${NC}"
echo ""
echo -e "4. Flink Web UI 접속:"
echo -e "   ${YELLOW}http://localhost:8081${NC}"
echo ""
echo -e "5. Kafka UI 접속:"
echo -e "   ${YELLOW}http://localhost:8080${NC}"
echo ""
