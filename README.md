# Как запустить

Запускаем mongodb, redis и приложение.

```shell
docker compose up -d
```

# Как проверить

Дожидаемся успешного запуска всех контейнеров.
После можно проверить по логам, все ли шарды и реплики успешно инициализированы, весь ли кластер Redis успешно поднялся.
```
docker logs config_init
docker logs shards_init
docker logs mongos_init
docker logs redis_init
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

[2025-12-02 23:41:40] 🎉 Redis Cluster is now configured and healthy (cluster_state:ok).
[2025-12-02 23:41:40] 🎉 Redis Cluster initialization finished successfully.
```
Так же можно проверить статус работы самого Redis-кластера командами:
1.  ```
    docker exec -it redis1 redis-cli cluster info
    ```
    В результате этой команды должны быть следующие значения:
    ```
    cluster_state:ok - кластер в здоровом состоянии.
    cluster_slots_assigned:16384 и cluster_slots_ok:16384 - все слоты распределены и в порядке.
    cluster_slots_pfail:0, cluster_slots_fail:0 - нет проблемных/упавших нод.
    cluster_known_nodes:6 - всего 6 нод.
    cluster_size:3 - 3 мастер-ноды в кластере.
    ```
2.  ```
    docker exec -it redis1 redis-cli cluster nodes
    ```
    Здесь у всех нод должно быть "connected"

Откройте в браузере http://localhost:8080

# Доступные эндпоинты

Список доступных эндпоинтов, swagger http://localhost:8080/docs