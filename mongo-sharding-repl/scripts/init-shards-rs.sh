#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%F %T')] $*"
}

wait_for_mongo() {
  local host="$1"
  local port="$2"
  local max_attempts="${3:-60}"

  log "Waiting for MongoDB to be available at ${host}:${port}..."

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

wait_for_rs_primary() {
  local host="$1"
  local port="$2"
  local max_attempts="${3:-60}"

  log "Waiting for PRIMARY in replica set at ${host}:${port}..."

  for ((i=1; i<=max_attempts; i++)); do
    local output
    output="$(mongosh --host "$host" --port "$port" --quiet 2>/dev/null <<'EOF'
try {
  const s = rs.isMaster();
  if (s.ismaster === true) {
    print("PRIMARY");
  } else {
    print("NOTPRIMARY");
  }
} catch (e) {
  print("ERROR");
}
EOF
)"
    if echo "$output" | grep -q "PRIMARY"; then
      log "✅ PRIMARY is ready at ${host}:${port}."
      return 0
    fi

    log "⏳ PRIMARY is not ready yet (raw output: ${output}), attempt ${i}/${max_attempts}..."
    sleep 5
  done

  log "❌ Error: PRIMARY was not elected at ${host}:${port} in time."
  return 1
}

ensure_shard_rs() {
  local rs_name="$1"
  local primary_host="$2"
  local members_js="$3"

  log "Checking shard replica set ${rs_name}..."

  local status
  status="$(mongosh --host "$primary_host" --port 27017 --quiet 2>/dev/null <<'EOF'
try {
  rs.status().ok ? "1" : "0";
} catch (e) {
  "0";
}
EOF
)"

  if [[ "$status" == "1" ]]; then
    log "✅ Replica set ${rs_name} is already initialized, skipping."
    return 0
  fi

  log "🚀 Initializing shard replica set ${rs_name}..."

  mongosh --host "$primary_host" --port 27017 <<EOF
rs.initiate({
  _id: "${rs_name}",
  members: ${members_js}
});
EOF

  wait_for_rs_primary "$primary_host" 27017

  log "🎉 Shard replica set ${rs_name} initialization completed."
}

main() {
  log "🚧 Starting shard replica sets initialization..."

  wait_for_mongo shard1a 27017
  wait_for_mongo shard1b 27017
  wait_for_mongo shard1c 27017

  wait_for_mongo shard2a 27017
  wait_for_mongo shard2b 27017
  wait_for_mongo shard2c 27017

  ensure_shard_rs "shard1" "shard1a" '[
    { _id: 0, host: "shard1a:27017" },
    { _id: 1, host: "shard1b:27017" },
    { _id: 2, host: "shard1c:27017" }
  ]'

  ensure_shard_rs "shard2" "shard2a" '[
    { _id: 0, host: "shard2a:27017" },
    { _id: 1, host: "shard2b:27017" },
    { _id: 2, host: "shard2c:27017" }
  ]'

  log "🎉 All shard replica sets are initialized."
}

main "$@"