#!/usr/bin/env sh
set -eu

log() {
  printf '[%s] %s\n' "$(date +'%F %T')" "$*"
}

wait_for_redis() {
  host="$1"
  port="$2"
  max_attempts="${3:-60}"

  log "Waiting for Redis to be available at ${host}:${port}..."

  i=1
  while [ "$i" -le "$max_attempts" ]; do
    if redis-cli -h "$host" -p "$port" ping 2>/dev/null | grep -q "PONG"; then
      log "✅ ${host}:${port} is up."
      return 0
    fi

    log "⏳ ${host}:${port} is not ready yet, attempt ${i}/${max_attempts}..."
    i=$((i + 1))
    sleep 2
  done

  log "❌ Error: ${host}:${port} did not become available in time."
  return 1
}

is_cluster_configured() {
  info="$(redis-cli -h redis1 -p 6379 cluster info 2>/dev/null || true)"

  echo "$info" | grep -q "cluster_state:ok"
}

create_cluster() {
  log "Creating Redis Cluster with 6 nodes (3 masters, 3 replicas)..."

  printf 'yes\n' | redis-cli --cluster create \
    redis1:6379 \
    redis2:6379 \
    redis3:6379 \
    redis4:6379 \
    redis5:6379 \
    redis6:6379 \
    --cluster-replicas 1

  log "Redis Cluster creation command completed."
}

main() {
  log "🚧 Starting Redis Cluster initialization..."

  wait_for_redis redis1 6379
  wait_for_redis redis2 6379
  wait_for_redis redis3 6379
  wait_for_redis redis4 6379
  wait_for_redis redis5 6379
  wait_for_redis redis6 6379

  if is_cluster_configured; then
    log "✅ Redis Cluster is already configured (cluster_state:ok), skipping creation."
    log "🎉 Redis Cluster initialization finished (idempotent)."
    exit 0
  fi

  create_cluster

  if is_cluster_configured; then
    log "🎉 Redis Cluster is now configured and healthy (cluster_state:ok)."
    exit 0
  else
    log "❌ Redis Cluster creation did not result in cluster_state:ok. Please check node logs."
    exit 1
  fi
}

main "$@"
