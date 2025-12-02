# Как запустить

Запускаем mongodb и приложение.

```shell
docker compose up -d
```

# Как проверить

Дожидаемся успешного запуска всех контейнеров.
После можно проверить по логам, все ли шарды и реплики успешно инициализированы.
```
docker logs config_init
docker logs shards_init
docker logs mongos_init
```
Если всё успешно, в логах этих контейнеров можно увидеть подобные сообщения:
```
[2025-12-02 22:18:56] Waiting for PRIMARY in replica set at configSrv1:27017...
[2025-12-02 22:18:56] ✅ PRIMARY is ready at configSrv1:27017.
[2025-12-02 22:18:56] 🎉 Config server replica set initialization completed.
```
```
Waiting for PRIMARY in replica set at shard2a:27017...
[2025-12-02 22:19:00] ✅ PRIMARY is ready at shard2a:27017.
[2025-12-02 22:19:00] 🎉 Shard replica set shard2 initialization completed.
[2025-12-02 22:19:00] 🎉 All shard replica sets are initialized.
```
```
[2025-12-02 22:19:13] 🎉 Shards are configured in mongos.
[2025-12-02 22:19:13] 🎉 mongos initialization completed.
```

Откройте в браузере http://localhost:8080

# Доступные эндпоинты

Список доступных эндпоинтов, swagger http://localhost:8080/docs