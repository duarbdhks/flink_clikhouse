#!/bin/bash
set -e

echo "================================================"
echo "Flink Job Auto Submitter"
echo "================================================"

# Flink JobManager가 준비될 때까지 대기
echo "[1/3] Waiting for Flink JobManager to be ready..."
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

# CDC Job 제출
echo "[2/3] Submitting Flink CDC Job..."
CDC_JAR_PATH="/opt/flink/jobs/flink-cdc-job/build/libs/flink-cdc-job-1.0.0.jar"

if [ ! -f "$CDC_JAR_PATH" ]; then
  echo "⚠️  WARNING: CDC JAR not found at $CDC_JAR_PATH"
  echo "   Skipping CDC Job submission"
else
  /opt/flink/bin/flink run -d \
    -m flink-jobmanager:8081 \
    -c com.flink.cdc.job.MySQLCDCJob \
    "$CDC_JAR_PATH"
  echo "✅ CDC Job submitted successfully"
fi

echo ""

# Sync Job 제출
echo "[3/3] Submitting Flink Sync Job..."
SYNC_JAR_PATH="/opt/flink/jobs/flink-sync-job/build/libs/flink-sync-job-1.0.0.jar"

if [ ! -f "$SYNC_JAR_PATH" ]; then
  echo "⚠️  WARNING: Sync JAR not found at $SYNC_JAR_PATH"
  echo "   Skipping Sync Job submission"
else
  /opt/flink/bin/flink run -d \
    -m flink-jobmanager:8081 \
    -c com.flink.sync.job.KafkaToClickHouseJob \
    "$SYNC_JAR_PATH"
  echo "✅ Sync Job submitted successfully"
fi

echo ""
echo "================================================"
echo "✅ All jobs submitted successfully!"
echo "   View jobs at http://localhost:8081"
echo "================================================"
