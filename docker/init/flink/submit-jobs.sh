#!/bin/bash
set -e

echo "================================================"
echo "Flink Job Auto Submitter (with Checkpoint Recovery)"
echo "================================================"

# Flink JobManager가 준비될 때까지 대기
echo "[1/4] Waiting for Flink JobManager to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0

while ! curl -sf http://flink-jobmanager:8081 > /dev/null; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ ERROR: Flink JobManager not available after ${MAX_RETRIES} retries"
    exit 1
  fi
  echo "   Waiting... (attempt $RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done

echo "✅ JobManager is ready!"
echo ""

# Savepoint 복구 헬퍼 함수 (수동 생성 Savepoint 우선)
find_cdc_savepoint() {
  local savepoint_dir="/tmp/flink-savepoints/cdc-manual"

  # CDC Job savepoint 중 가장 최근 것 찾기
  if [ -d "$savepoint_dir" ]; then
    local latest_savepoint=$(find "$savepoint_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
      xargs -I {} stat -c "%Y %n" {} 2>/dev/null | \
      sort -rn | \
      head -1 | \
      awk '{print $2}')

    if [ -n "$latest_savepoint" ]; then
      echo "$latest_savepoint"
    else
      echo ""
    fi
  else
    echo ""
  fi
}

find_sync_savepoint() {
  local savepoint_dir="/tmp/flink-savepoints/sync-manual"

  # Sync Job savepoint 중 가장 최근 것 찾기
  if [ -d "$savepoint_dir" ]; then
    local latest_savepoint=$(find "$savepoint_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
      xargs -I {} stat -c "%Y %n" {} 2>/dev/null | \
      sort -rn | \
      head -1 | \
      awk '{print $2}')

    if [ -n "$latest_savepoint" ]; then
      echo "$latest_savepoint"
    else
      echo ""
    fi
  else
    echo ""
  fi
}

# Checkpoint 복구 헬퍼 함수 (자동 생성 Checkpoint, Savepoint 없을 때 사용)
find_cdc_checkpoint() {
  local checkpoint_dir="/tmp/flink-checkpoints/cdc"

  # CDC Job checkpoint 중 가장 최근 것 찾기 (Linux 호환)
  local latest_checkpoint=$(find "$checkpoint_dir" -type d -name "chk-*" 2>/dev/null | \
    xargs -I {} stat -c "%Y %n" {} 2>/dev/null | \
    sort -rn | \
    head -1 | \
    awk '{print $2}')

  if [ -n "$latest_checkpoint" ]; then
    echo "$latest_checkpoint"
  else
    echo ""
  fi
}

find_sync_checkpoint() {
  local checkpoint_dir="/tmp/flink-checkpoints/sync"

  # Sync Job checkpoint 중 가장 최근 것 찾기 (Linux 호환)
  local latest_checkpoint=$(find "$checkpoint_dir" -type d -name "chk-*" 2>/dev/null | \
    xargs -I {} stat -c "%Y %n" {} 2>/dev/null | \
    sort -rn | \
    head -1 | \
    awk '{print $2}')

  if [ -n "$latest_checkpoint" ]; then
    echo "$latest_checkpoint"
  else
    echo ""
  fi
}

# Job이 이미 실행 중인지 확인
is_job_running() {
  local job_name=$1
  /opt/flink/bin/flink list -m flink-jobmanager:8081 2>/dev/null | grep -q "$job_name"
}

echo "[2/4] Checking for existing savepoints and checkpoints..."

# CDC Job 복구 옵션 결정 (Savepoint 우선, Checkpoint 대체)
CDC_SAVEPOINT=$(find_cdc_savepoint)
CDC_CHECKPOINT=$(find_cdc_checkpoint)

if [ -n "$CDC_SAVEPOINT" ]; then
  echo "✅ CDC savepoint found: $CDC_SAVEPOINT (우선 사용)"
  CDC_RECOVERY_OPTION="-s $CDC_SAVEPOINT"
  CDC_RECOVERY_TYPE="SAVEPOINT"
elif [ -n "$CDC_CHECKPOINT" ]; then
  echo "✅ CDC checkpoint found: $CDC_CHECKPOINT (savepoint 없음, checkpoint 사용)"
  CDC_RECOVERY_OPTION="-s $CDC_CHECKPOINT"
  CDC_RECOVERY_TYPE="CHECKPOINT"
else
  echo "⚠️  CDC savepoint/checkpoint not found, will start fresh"
  CDC_RECOVERY_OPTION=""
  CDC_RECOVERY_TYPE="NONE"
fi

# Sync Job 복구 옵션 결정 (Savepoint 우선, Checkpoint 대체)
SYNC_SAVEPOINT=$(find_sync_savepoint)
SYNC_CHECKPOINT=$(find_sync_checkpoint)

if [ -n "$SYNC_SAVEPOINT" ]; then
  echo "✅ Sync savepoint found: $SYNC_SAVEPOINT (우선 사용)"
  SYNC_RECOVERY_OPTION="-s $SYNC_SAVEPOINT"
  SYNC_RECOVERY_TYPE="SAVEPOINT"
elif [ -n "$SYNC_CHECKPOINT" ]; then
  echo "✅ Sync checkpoint found: $SYNC_CHECKPOINT (savepoint 없음, checkpoint 사용)"
  SYNC_RECOVERY_OPTION="-s $SYNC_CHECKPOINT"
  SYNC_RECOVERY_TYPE="CHECKPOINT"
else
  echo "⚠️  Sync savepoint/checkpoint not found, will start fresh"
  SYNC_RECOVERY_OPTION=""
  SYNC_RECOVERY_TYPE="NONE"
fi

echo ""

# CDC Job 제출
echo "[3/4] Submitting Flink CDC Job..."
CDC_JAR_PATH="/opt/flink/jobs/flink-cdc-job/build/libs/flink-cdc-job-1.0.0.jar"
CDC_JOB_NAME="MySQL CDC to Kafka"

if [ ! -f "$CDC_JAR_PATH" ]; then
  echo "⚠️  WARNING: CDC JAR not found at $CDC_JAR_PATH"
  echo "   Skipping CDC Job submission"
elif is_job_running "$CDC_JOB_NAME"; then
  echo "✅ CDC Job is already running, skipping submission"
else
  if [ -n "$CDC_RECOVERY_OPTION" ]; then
    echo "   Attempting CDC recovery from $CDC_RECOVERY_TYPE..."
    if /opt/flink/bin/flink run -d \
      -m flink-jobmanager:8081 \
      $CDC_RECOVERY_OPTION \
      -c com.flink.cdc.job.MySQLCDCJob \
      "$CDC_JAR_PATH" 2>/dev/null; then
      echo "✅ CDC Job restored from $CDC_RECOVERY_TYPE"
    else
      echo "⚠️  CDC $CDC_RECOVERY_TYPE recovery failed, starting fresh"
      /opt/flink/bin/flink run -d \
        -m flink-jobmanager:8081 \
        -c com.flink.cdc.job.MySQLCDCJob \
        "$CDC_JAR_PATH"
      echo "✅ CDC Job submitted successfully"
    fi
  else
    /opt/flink/bin/flink run -d \
      -m flink-jobmanager:8081 \
      -c com.flink.cdc.job.MySQLCDCJob \
      "$CDC_JAR_PATH"
    echo "✅ CDC Job submitted successfully"
  fi
fi

echo ""

# Sync Job 제출
echo "[4/4] Submitting Flink Sync Job..."
SYNC_JAR_PATH="/opt/flink/jobs/flink-sync-job/build/libs/flink-sync-job-1.0.0.jar"
SYNC_JOB_NAME="Kafka CDC to ClickHouse"

if [ ! -f "$SYNC_JAR_PATH" ]; then
  echo "⚠️  WARNING: Sync JAR not found at $SYNC_JAR_PATH"
  echo "   Skipping Sync Job submission"
elif is_job_running "$SYNC_JOB_NAME"; then
  echo "✅ Sync Job is already running, skipping submission"
else
  if [ -n "$SYNC_RECOVERY_OPTION" ]; then
    echo "   Attempting Sync recovery from $SYNC_RECOVERY_TYPE..."
    if /opt/flink/bin/flink run -d \
      -m flink-jobmanager:8081 \
      $SYNC_RECOVERY_OPTION \
      -c com.flink.sync.job.KafkaToClickHouseJob \
      "$SYNC_JAR_PATH" 2>/dev/null; then
      echo "✅ Sync Job restored from $SYNC_RECOVERY_TYPE"
    else
      echo "⚠️  Sync $SYNC_RECOVERY_TYPE recovery failed, starting fresh"
      /opt/flink/bin/flink run -d \
        -m flink-jobmanager:8081 \
        -c com.flink.sync.job.KafkaToClickHouseJob \
        "$SYNC_JAR_PATH"
      echo "✅ Sync Job submitted successfully"
    fi
  else
    /opt/flink/bin/flink run -d \
      -m flink-jobmanager:8081 \
      -c com.flink.sync.job.KafkaToClickHouseJob \
      "$SYNC_JAR_PATH"
    echo "✅ Sync Job submitted successfully"
  fi
fi

echo ""
echo "================================================"
echo "✅ All jobs processed!"
echo "   View jobs at http://localhost:8081"
echo "   CDC recovery: $CDC_RECOVERY_TYPE"
echo "   Sync recovery: $SYNC_RECOVERY_TYPE"
echo "================================================"
echo ""
echo "🔄 Keeping container alive (use docker stop to terminate)..."
# Job 제출 완료 후 컨테이너를 계속 실행 상태로 유지
# restart: unless-stopped 정책과 함께 사용하여 불필요한 재시작 방지
tail -f /dev/null
