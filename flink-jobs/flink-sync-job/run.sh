#!/bin/bash

#==============================================================================
# Flink Sync Job 실행 스크립트
#==============================================================================

set -e  # 에러 발생 시 스크립트 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 프로젝트 루트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JAR_FILE="$SCRIPT_DIR/build/libs/flink-sync-job-1.0.0.jar"
MAIN_CLASS="com.flink.sync.job.KafkaToClickHouseJob"

# 기본 설정
FLINK_MODE="${FLINK_MODE:-docker}"  # docker | standalone | cluster | local
DETACHED="${DETACHED:-true}"  # Docker 기본은 detached
RESTART="${RESTART:-false}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-yeumgw-flink-jobmanager}"

#==============================================================================
# 함수 정의
#==============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "======================================================================"
    echo "  Flink Sync Job - Kafka to ClickHouse"
    echo "======================================================================"
    echo -e "${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_docker_compose() {
    print_info "Docker Compose 환경 확인 중..."

    # Docker 설치 확인
    if ! command -v docker &> /dev/null; then
        print_error "Docker가 설치되어 있지 않습니다."
        exit 1
    fi

    # Flink JobManager 컨테이너 실행 확인
    if ! docker ps | grep -q "$DOCKER_CONTAINER"; then
        print_error "Flink JobManager 컨테이너($DOCKER_CONTAINER)가 실행 중이지 않습니다."
        print_info "먼저 Docker Compose를 시작하세요: docker-compose up -d"
        exit 1
    fi

    print_info "Docker 컨테이너: $DOCKER_CONTAINER ✓"
}

get_running_jobs() {
    print_info "실행 중인 Flink Job 확인..."
    docker exec "$DOCKER_CONTAINER" flink list -r 2>/dev/null || true
}

cancel_job() {
    local job_id="$1"
    print_info "Job 중지 중: $job_id"
    docker exec "$DOCKER_CONTAINER" flink cancel "$job_id"
    sleep 2  # Job이 완전히 중지될 때까지 대기
}

cancel_all_jobs() {
    print_warn "실행 중인 모든 Job을 중지합니다..."

    # 실행 중인 Job ID 추출
    local job_ids=$(docker exec "$DOCKER_CONTAINER" flink list -r 2>/dev/null | grep -oP '[a-f0-9]{32}' || true)

    if [ -z "$job_ids" ]; then
        print_info "실행 중인 Job이 없습니다."
        return 0
    fi

    # 각 Job 중지
    echo "$job_ids" | while read -r job_id; do
        if [ -n "$job_id" ]; then
            cancel_job "$job_id"
        fi
    done
}

check_prerequisites() {
    print_info "전제 조건 확인 중..."

    # Docker 모드가 아닌 경우에만 Java/FLINK_HOME 확인
    if [ "$FLINK_MODE" != "docker" ]; then
        # Java 설치 확인
        if ! command -v java &> /dev/null; then
            print_error "Java가 설치되어 있지 않습니다."
            exit 1
        fi

        local java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        print_info "Java 버전: $java_version"

        # Flink 설치 확인
        if [ -z "$FLINK_HOME" ]; then
            print_warn "FLINK_HOME 환경변수가 설정되어 있지 않습니다."
            print_warn "Flink CLI를 사용하려면 FLINK_HOME을 설정하세요."
        else
            print_info "FLINK_HOME: $FLINK_HOME"
        fi
    fi

    # JAR 파일 존재 확인
    if [ ! -f "$JAR_FILE" ]; then
        print_error "JAR 파일을 찾을 수 없습니다: $JAR_FILE"
        print_info "먼저 빌드를 실행하세요: ./gradlew :flink-sync-job:shadowJar"
        exit 1
    fi

    print_info "JAR 파일 확인: $JAR_FILE ($(du -h "$JAR_FILE" | cut -f1))"
}

build_jar() {
    print_info "JAR 파일 빌드 중..."

    cd "$PROJECT_ROOT"
    ./gradlew :flink-sync-job:clean :flink-sync-job:shadowJar

    if [ $? -eq 0 ]; then
        print_info "빌드 성공!"
    else
        print_error "빌드 실패!"
        exit 1
    fi
}

run_standalone() {
    print_info "Standalone 모드로 실행 중..."

    if [ "$DETACHED" = "true" ]; then
        print_info "Detached 모드로 실행..."
        flink run --detached \
            --class "$MAIN_CLASS" \
            "$JAR_FILE"
    else
        print_info "Attached 모드로 실행..."
        flink run \
            --class "$MAIN_CLASS" \
            "$JAR_FILE"
    fi
}

run_cluster() {
    print_info "Cluster 모드로 실행 중..."

    # JobManager 주소 확인
    if [ -z "$FLINK_JOBMANAGER" ]; then
        print_error "FLINK_JOBMANAGER 환경변수가 설정되어 있지 않습니다."
        print_info "예: export FLINK_JOBMANAGER=localhost:8081"
        exit 1
    fi

    if [ "$DETACHED" = "true" ]; then
        print_info "Detached 모드로 클러스터에 제출..."
        flink run --detached \
            --jobmanager "$FLINK_JOBMANAGER" \
            --class "$MAIN_CLASS" \
            "$JAR_FILE"
    else
        print_info "Attached 모드로 클러스터에 제출..."
        flink run \
            --jobmanager "$FLINK_JOBMANAGER" \
            --class "$MAIN_CLASS" \
            "$JAR_FILE"
    fi
}

run_docker() {
    print_info "Docker Compose 환경에서 실행 중..."

    # Docker 환경 확인
    check_docker_compose

    # Restart 옵션 처리
    if [ "$RESTART" = "true" ]; then
        cancel_all_jobs
    fi

    # JAR 파일 경로 (컨테이너 내부 경로)
    local container_jar="/opt/flink/jobs/flink-sync-job/build/libs/flink-sync-job-1.0.0.jar"

    # Docker exec로 Flink Job 실행
    if [ "$DETACHED" = "true" ]; then
        print_info "Detached 모드로 실행..."
        docker exec "$DOCKER_CONTAINER" flink run --detached \
            --class "$MAIN_CLASS" \
            "$container_jar"
    else
        print_info "Attached 모드로 실행..."
        docker exec "$DOCKER_CONTAINER" flink run \
            --class "$MAIN_CLASS" \
            "$container_jar"
    fi

    # 실행 결과 확인
    if [ $? -eq 0 ]; then
        print_info "Job 제출 성공!"
        echo ""
        get_running_jobs
    else
        print_error "Job 제출 실패!"
        exit 1
    fi
}

run_local() {
    print_info "로컬 모드로 실행 중 (IDE 대신 직접 실행)..."

    java -cp "$JAR_FILE" "$MAIN_CLASS"
}

show_usage() {
    echo "사용법: $0 [OPTIONS]"
    echo ""
    echo "옵션:"
    echo "  -m, --mode MODE       실행 모드 (docker|standalone|cluster|local) [기본: docker]"
    echo "  -b, --build           실행 전 빌드"
    echo "  -r, --restart         기존 Job 중지 후 재시작"
    echo "  -c, --cancel JOB_ID   특정 Job 중지"
    echo "  -l, --list            실행 중인 Job 목록만 표시"
    echo "  -a, --attached        Attached 모드로 실행 (기본: detached)"
    echo "  -h, --help            도움말 표시"
    echo ""
    echo "예제:"
    echo "  $0                          # Docker Compose detached 모드 (기본)"
    echo "  $0 -b                       # 빌드 후 실행"
    echo "  $0 -r                       # 기존 Job 중지 후 재시작"
    echo "  $0 -b -r                    # 빌드 + 재시작 (개발 워크플로우)"
    echo "  $0 -l                       # 실행 중인 Job 목록만 표시"
    echo "  $0 -c <job-id>              # 특정 Job 중지"
    echo "  $0 -m standalone            # Standalone 모드 (FLINK_HOME 필요)"
    echo "  $0 -m local                 # 로컬 모드 (디버깅용)"
}

#==============================================================================
# 메인 실행
#==============================================================================

# 명령행 인수 파싱
BUILD=false
LIST_ONLY=false
CANCEL_JOB_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            FLINK_MODE="$2"
            shift 2
            ;;
        -b|--build)
            BUILD=true
            shift
            ;;
        -r|--restart)
            RESTART=true
            shift
            ;;
        -c|--cancel)
            CANCEL_JOB_ID="$2"
            shift 2
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -a|--attached)
            DETACHED=false
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "알 수 없는 옵션: $1"
            show_usage
            exit 1
            ;;
    esac
done

# 배너 출력
print_banner

# List-only 모드 처리
if [ "$LIST_ONLY" = "true" ]; then
    check_docker_compose
    get_running_jobs
    exit 0
fi

# Cancel 모드 처리
if [ -n "$CANCEL_JOB_ID" ]; then
    check_docker_compose
    cancel_job "$CANCEL_JOB_ID"
    print_info "Job 중지 완료!"
    exit 0
fi

# 빌드 (옵션)
if [ "$BUILD" = "true" ]; then
    build_jar
fi

# 전제 조건 확인
check_prerequisites

# 실행 모드에 따라 실행
case $FLINK_MODE in
    docker)
        run_docker
        ;;
    standalone)
        run_standalone
        ;;
    cluster)
        run_cluster
        ;;
    local)
        run_local
        ;;
    *)
        print_error "지원하지 않는 모드: $FLINK_MODE"
        show_usage
        exit 1
        ;;
esac

print_info "실행 완료!"

# Flink Web UI 링크 표시
if [ "$FLINK_MODE" = "docker" ]; then
    echo ""
    print_info "Flink Web UI: http://localhost:8081"
    print_info "Job 목록 확인: ./run.sh -l"
    print_info "Job 중지: ./run.sh -c <job-id>"
    print_info "재시작: ./run.sh -r"
elif [ "$FLINK_MODE" != "local" ]; then
    echo ""
    print_info "Flink Web UI: http://localhost:8081"
    print_info "Job 목록 확인: flink list"
    print_info "Job 취소: flink cancel <job-id>"
fi
