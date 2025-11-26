#!/bin/bash

echo "🚧 | 1/4: Initializing Config Server..."
docker compose exec -T configSrv mongosh --port 27017 <<'EOF'
rs.initiate(
  {
    _id : "config_server",
    configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
EOF
echo "✅ | 1/4: Config Server initialized successfully."
sleep 3

echo "🚧 | 2/4: Initializing Shards..."
echo "⏳ | Shard1..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate(
  {
    _id : "shard1",
    members: [
      { _id : 0, host : "shard1:27018" },
      // { _id : 1, host : "shard2:27019" }
    ]
  }
);
EOF
echo "⏳ | Shard1 initialized."
sleep 1

echo "⏳ | Shard2..."
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
rs.initiate(
  {
    _id : "shard2",
    members: [
      // { _id : 0, host : "shard1:27018" },
      { _id : 1, host : "shard2:27019" }
    ]
  }
);
EOF
echo "⏳ | Shard2 initialized."

echo "✅ | 2/4: All shards are initialized successfully."
sleep 3

echo "🚧 | 3/4: Initializing Routers and fill with test data..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard( "shard1/shard1:27018");
sh.addShard( "shard2/shard2:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );

use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i });
db.helloDoc.countDocuments();
EOF

echo "\n✅ | 3/4: Routers initialized successfully. Test data filled successfully."
sleep 3

echo "🚧 | 4/4: Checking data"

echo "⏳ | Shard1 documents count:"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
use somedb;
db.helloDoc.countDocuments();
EOF
sleep 1

echo "⏳ | Shard2 documents count:"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
use somedb;
db.helloDoc.countDocuments();
EOF
echo "✅ | 4/4: Data was checked."
echo "✅ | MongoDB cluster initialized."
