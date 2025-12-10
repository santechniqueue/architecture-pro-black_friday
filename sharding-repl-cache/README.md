# Как запустить

Запускаем mongodb и приложение.

```shell
docker compose up -d
```

# Как проверить

Дожидаемся успешного запуска всех контейнеров.
После можно проверить по логам, весь ли кластер Redis успешно поднялся.
```
docker logs redis_init
```
Если всё успешно, в логах контейнера можно увидеть подобные сообщения:
```
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