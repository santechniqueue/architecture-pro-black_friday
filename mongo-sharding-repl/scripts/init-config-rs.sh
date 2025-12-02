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
    local status
    status="$(mongosh --host "$host" --port "$port" --quiet 2>/dev/null <<'EOF'
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
    if [[ "$status" == "PRIMARY" ]]; then
      log "✅ PRIMARY is ready at ${host}:${port}."
      return 0
    fi

    log "⏳ PRIMARY is not ready yet (${status}), attempt ${i}/${max_attempts}..."
    sleep 5
  done

  log "❌ Error: PRIMARY was not elected at ${host}:${port} in time."
  return 1
}

main() {
  log "🚧 Starting config server replica set initialization..."

  wait_for_mongo configSrv1 27017
  wait_for_mongo configSrv2 27017
  wait_for_mongo configSrv3 27017

  log "Checking if config_server replica set is already initialized..."

  local status
  status="$(mongosh --host configSrv1 --port 27017 --quiet 2>/dev/null <<'EOF'
try {
  rs.status().ok ? "1" : "0";
} catch (e) {
  "0";
}
EOF
)"

  if [[ "$status" == "1" ]]; then
    log "✅ Replica set config_server is already initialized, skipping."
    return 0
  fi

  log "🚀 Initializing config_server replica set..."

  mongosh --host configSrv1 --port 27017 <<'EOF'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27017" },
    { _id: 1, host: "configSrv2:27017" },
    { _id: 2, host: "configSrv3:27017" }
  ]
});
EOF

  wait_for_rs_primary configSrv1 27017

  log "🎉 Config server replica set initialization completed."
}

main "$@"