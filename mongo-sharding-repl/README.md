# Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Заполняем mongodb данными

```shell
./scripts/mongo-init-shards.sh
```

В output-е отобразятся логи пошаговой инициализации и заполнения данными кластера.

# Как проверить

Откройте в браузере http://localhost:8080

# Доступные эндпоинты

Список доступных эндпоинтов, swagger http://localhost:8080/docs