#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%F %T')] $*"
}

wait_for_mongo() {
  local host="$1"
  local port="$2"
  local max_attempts="${3:-60}"

  log "Waiting for mongos to be available at ${host}:${port}..."

  for ((i=1; i<=max_attempts; i++)); do
    if mongosh --host "$host" --port "$port" --quiet \
      --eval "db.adminCommand('ping').ok" 2>/dev/null | grep -q "1"; then
      log "✅ ${host}:${port} is up."
      return 0
    fi

    log "⏳ ${host}:${port} is not ready yet, attempt ${i}/${max_attempts}..."
    sleep 5
  done

  log "❌ Error: ${host}:${port} did not become available in time."
  return 1
}

ensure_shards_added() {
  log "Checking if shards are added to mongos..."

  wait_for_mongo mongos_router 27026

  local shards
  shards="$(mongosh --host mongos_router --port 27026 --quiet <<'EOF'
const res = db.adminCommand({ listShards: 1 });
if (!res.ok) {
  print("");
} else {
  print(res.shards.map(s => s._id).join(","));
}
EOF
)"

  log "Current shards: ${shards:-<none>}"

  if [[ "$shards" == *"shard1"* ]]; then
    log "✅ shard1 is already added, skipping."
  else
    log "➕ Adding shard1..."
    mongosh --host mongos_router --port 27026 <<'EOF'
print("Adding shard1...");
sh.addShard("shard1/shard1a:27017,shard1b:27017,shard1c:27017");
EOF
  fi

  if [[ "$shards" == *"shard2"* ]]; then
    log "✅ shard2 is already added, skipping."
  else
    log "➕ Adding shard2..."
    mongosh --host mongos_router --port 27026 <<'EOF'
print("Adding shard2...");
sh.addShard("shard2/shard2a:27017,shard2b:27017,shard2c:27017");
EOF
  fi

  log "🎉 Shards are configured in mongos."
}

main() {
  log "🚧 Starting mongos initialization (shards registration)..."
  ensure_shards_added
  log "🎉 mongos initialization completed."
}

main "$@"