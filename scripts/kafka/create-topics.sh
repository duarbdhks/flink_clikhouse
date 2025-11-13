#!/bin/bash

# ============================================
# Kafka Topic 생성 스크립트
# 목적: CDC 파이프라인에 필요한 Kafka Topics 생성
# ============================================

set -e  # 에러 발생 시 스크립트 중단

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}   Kafka Topics 생성 시작${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Kafka 컨테이너 이름
KAFKA_CONTAINER="yeumgw-kafka"

# Kafka가 실행 중인지 확인
if ! docker ps | grep -q "$KAFKA_CONTAINER"; then
    echo -e "${RED}❌ Kafka 컨테이너가 실행되고 있지 않습니다.${NC}"
    echo -e "${YELLOW}💡 먼저 'docker-compose up -d kafka'를 실행하세요.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Kafka 컨테이너 실행 확인 완료${NC}"
echo ""

# Topic 설정
TOPICS=(
    "orders-cdc-topic"
)

PARTITIONS=3
REPLICATION_FACTOR=1

# Topic 생성 함수
create_topic() {
    local topic_name=$1
    echo -e "${BLUE}📋 Topic 생성: ${topic_name}${NC}"

    # Topic이 이미 존재하는지 확인
    if docker exec $KAFKA_CONTAINER kafka-topics \
        --bootstrap-server localhost:9092 \
        --list | grep -q "^${topic_name}$"; then
        echo -e "${YELLOW}⚠️  Topic '${topic_name}'이(가) 이미 존재합니다. 건너뜁니다.${NC}"
    else
        # Topic 생성
        docker exec $KAFKA_CONTAINER kafka-topics \
            --bootstrap-server localhost:9092 \
            --create \
            --topic "$topic_name" \
            --partitions $PARTITIONS \
            --replication-factor $REPLICATION_FACTOR \
            --config cleanup.policy=delete \
            --config retention.ms=604800000 \
            --config segment.ms=86400000

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Topic '${topic_name}' 생성 완료${NC}"
        else
            echo -e "${RED}❌ Topic '${topic_name}' 생성 실패${NC}"
            exit 1
        fi
    fi
    echo ""
}

# 모든 Topic 생성
for topic in "${TOPICS[@]}"; do
    create_topic "$topic"
done

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}   생성된 Topics 목록${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Topics 목록 조회
docker exec $KAFKA_CONTAINER kafka-topics \
    --bootstrap-server localhost:9092 \
    --list

echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}   Topic 상세 정보${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# 각 Topic의 상세 정보 출력
for topic in "${TOPICS[@]}"; do
    echo -e "${YELLOW}Topic: ${topic}${NC}"
    docker exec $KAFKA_CONTAINER kafka-topics \
        --bootstrap-server localhost:9092 \
        --describe \
        --topic "$topic"
    echo ""
done

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}✅ Kafka Topics 생성 완료!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# 추가 정보 출력
echo -e "${BLUE}📊 Topic 설정 정보:${NC}"
echo -e "  - Partitions: ${PARTITIONS}"
echo -e "  - Replication Factor: ${REPLICATION_FACTOR}"
echo -e "  - Retention Period: 7일 (604800000ms)"
echo -e "  - Segment Roll Period: 1일 (86400000ms)"
echo ""

echo -e "${BLUE}💡 유용한 Kafka 명령어:${NC}"
echo -e "  - Topics 목록: docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list"
echo -e "  - Consumer Lag 확인: docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group [group-id]"
echo -e "  - 메시지 소비 테스트: docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic orders-cdc-topic --from-beginning"
echo ""
