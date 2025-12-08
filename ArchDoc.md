# Задание 7. Проектирование схем коллекций для шардирования данных

## 1. Коллекция `Orders`

### Основные операции

- Запись:
  - Создание заказа.
- Чтение:
  - История заказов конкретного пользователя: user_id, сортировка по дате. 
  - Отображение статуса заказа: чаще всего в разрезе заказов клиента.

### Описание схемы

```javascript
{
  _id: ObjectId(),                  // Уникальный идентификатор документа
  order_id: Integer,                // Уникальный "человекочитаемый" числовой id заказа для клиента 
  user_id: ObjectId(),              // Идентификатор клиента
  created_at: ISODate(),            // Дата и время оформления заказа
  status: String,                   // "new" | "paid" | "shipped" | "delivered" | "cancelled" ...
  total_cost: NumberDecimal("0.00"),// Общая сумма заказа, Decimal128 - best-practice для хранения денежных сумм
  geo_zone: String,                 // Код геозоны, например "RU-MOW", "RU-SPE", "RU-SVE"
  items: [
    {
      product_id: ObjectId(),
      name: String,                 // Денормализация имени товара для удобства аналитики
      category: String,             // Денормализация категории
      price: NumberDecimal("0.00"), // Цена на момент покупки
      quantity: NumberInt()         // Количество
    }
  ],
  updated_at: ISODate()             // Для оптимистичной блокировки
}
```

### Индексы
```javascript
// История заказов пользователя по дате
db.orders.createIndex({ user_id: 1, created_at: -1 });

// Быстрый поиск по числовому id заказа
db.orders.createIndex({ order_id: 1 }, { unique: true });

// Поиск и обновление по статусу для внутренних процессов
db.orders.createIndex({ status: 1, updated_at: -1 });

// Быстрый поиск по _id (Mongo создаёт автоматически)
```

### Стратегия шардирования

Шард-ключ: `{ user_id: "hashed" }`. <br>Стратегия: hash.

#### Причина выбора

1. Распределение нагрузки: 
   - Для большого количества пользователей значение по user_id распределяется равномерно. 
   - Hashed key обеспечивает равномерное распределение, так как новые заказы разных пользователей попадают на разные шарды. 
2. Таргетированные запросы истории:
    - Запрос `db.orders.find({ user_id: <id> }).sort({ created_at: -1 })` попадает на один шард, так как все заказы этого пользователя лежат в одном наборе с тем же user_id. 
    - Подходит для запросов на странице заказов клиента.
3. Создание заказа:
    - При создании заказа мы знаем user_id, поэтому запрос сразу уйдёт на нужный шард. 
4. Статус заказа:
   - Статус заказа так же отслеживается по пользователю на странице заказов - также таргетированный запрос.


## 2. Коллекция `Products`

### Основные операции

- Запись:
  - Частые обновления остатков при покупках. 
- Чтение:
  - Поиск товаров по категории (страницы каталога). 
  - Фильтрация по диапазону цен. 
  - Отображение карточки товара.

### Описание схемы

```javascript
{
  _id: ObjectId(),                  // product_id
  name: String,                     // Наименование
  category: String,                 // Например "smartphones", "audio", "tv", "books"
  price: NumberDecimal("0.00"),     // Текущая цена
  stocks: [                         // Остатки по геозонам
    {
      geo_zone: String,             // "RU-MOW", "RU-SPE", ...
      quantity: NumberInt()
    }
  ],
  attributes: {                     // Доп. атрибуты
    color: String,
    size: String,
  },
  is_active: Boolean,               // Флаг доступности товара
  created_at: ISODate(),
  updated_at: ISODate()
}
```

### Индексы

```javascript
// Основной индекс под выдачу каталога: категория + цена
db.products.createIndex({ category: 1, price: 1 });

// Быстрый доступ к остаткам по geo + product
db.products.createIndex({ _id: 1, "stocks.geo_zone": 1 });

// Фильтрация активных товаров в каталоге
db.products.createIndex({ is_active: 1, category: 1, price: 1 });
```

### Стратегия шардирования

Шард-ключ: составной `{ category: 1, price: 1 }` <br>Стратегия: range based sharding

#### Причина выбора

1. Оптимизация каталога, так как в каталог часто уходят запросы в виде:
   ```js
   db.products.find({
     category: "smartphones",
     price: { $gte: 10000, $lte: 30000 },
     is_active: true
   }).sort({ price: 1 }).limit(20);
   ```
   - Range-шардирование по `(category, price)` позволяет:
     - ограничить запрос только чанками с нужной категорией;
     - внутри категории использовать эффективный range-скан по цене.
2. Горячие категории:  
   - Популярные категории могут занимать много чанков.
   - Чанки по этой категории и диапазону цен можно физически разнести по разным шардам, добиваясь распределения нагрузки.
3. Обновление остатков: 
   - Обновления стоков идут по `_id` и геозоне.
   - В сервисе можно хранить `category`/`price` товара в кэше и подставлять их в запросы, чтобы обновления также таргетировались на нужный шард.
4. Почему не hash и не geo:
   - `hash` по `_id` делает практически все каталожные запросы scatter-gather, что плохо масштабируется.
   - `geo` не является основным фильтром каталога - чаще всего пользователь фильтрует по категории/цене, а геозона идёт как дополнительный фильтр наличия.


## 3. Коллекция `Carts`

### Основные операции

Запись:
- Частые изменения: добавление/изменение/удаление товаров.
- Слияние гостевой корзины в пользовательской.
- Автоматическая очистка старых корзин по TTL.
Чтение:
- Получение текущей корзины:
  - `{ session_id, status: "active" }` - для гостя;
  - `{ user_id, status: "active" }` - для залогиненного.

### Описание схемы

```javasrcipt
{
  _id: ObjectId(),                  // Идентификатор корзины
  user_id: ObjectId(),              // Может быть null для гостя
  session_id: String,               // Уникальный идентификатор сессии (UUID/токен и т.п.)
  status: String,                   // "active" | "ordered" | "abandoned"
  items: [
    {
      product_id: ObjectId(),
      quantity: NumberInt()
    }
  ],
  created_at: ISODate(),
  updated_at: ISODate(),
  expires_at: ISODate()             // Время, после которого корзина удаляется TTL-механизмом
}
```

### Индексы

```javascript
// Индекс для пользователей
db.carts.createIndex({ user_id: 1, session_id: 1 });

// Поиск активной корзины по user_id (авторизованный пользователь)
db.carts.createIndex({ user_id: 1, status: 1 });

// Поиск активной корзины по session_id (гость)
db.carts.createIndex({ session_id: 1, status: 1 });

// Индекс на TTL корзины
db.carts.createIndex(
  { expires_at: 1 },
  { expireAfterSeconds: 0 }
);
```

### Стратегия шардирования

Шард-ключ: составной `{ user_id: 1, session_id: 1 }` <br>Стратегия: dynamic sharding

#### Причина выбора

1. Единый ключ для всех владельцев: 
   - Для гостя: `{ user_id: null, session_id: "<sess>" }`.  
   - Для пользователя: `{ user_id: <ObjectId>, session_id: "<sess>" }`.  
   - Все операции с корзиной конкретного владельца проходят через один и тот же набор значений `(user_id, session_id)`.
2. Таргетированные запросы под операции из условия:
   - Гость - получить корзину:
     ```js
     db.carts.findOne({
       user_id: null,
       session_id: "<sess>",
       status: "active"
     });
     ```
     - Здесь полный шард-ключ, соответсвенно, запрос таргетируется на один шард.
   - Пользователь - получить корзину:
     ```js
     db.carts.findOne({
       user_id: <userId>,
       status: "active"
     });
     ```
     - Здесь MongoDB умеет таргетировать по префиксу шард-ключа (`user_id`), так что это не превращается в полноформатный scatter-gather.
   - Создание/обновление корзины и изменения товаров выполняются по тем же ключам и, соответственно, идут на один шард.
3. Слияние гостевой корзины в пользовательской:

   Алгоритм:

   1. Найти гостевую корзину:
      ```js
      db.carts.findOne({
        user_id: null,
        session_id: "<sess>",
        status: "active"
      });
      ```
   2. Найти/создать пользовательскую корзину:
      ```js
      const userCart = db.carts.findOne({
        user_id: <userId>,
        status: "active"
      });
      ```
   3. Объединить `items` в приложении и записать в пользовательскую корзину (`updateOne` по `user_id`, `session_id`).
   4. Гостевую пометить `status: "abandoned"`.
   - Здесь все запросы либо по полному шард-ключу, либо по его префиксу.
4. Динамический характер нагрузки: - 
   - По корзинам возможны серьёзные пики нагрузок в периоды распродаж. 
   - Корзины живут недолго: активно обновляются и затем либо превращаются в заказ, либо удаляются TTL-механизмом. 
   - Увеличение числа шардов позволяет балансировщику перекидывать чанки с корзинами на менее загруженные узлы, что отражает идею dynamic sharding на практике.

# Задание 8. Выявление и устранение «горячих» шардов

## Метрики

1. Операции в секунду по шарду, снимаем раз в N сек.:
    ```js
    db.serverStatus().opcounters
    /*
    opcounters : {
       insert : Long("<num>"),
       query : Long("<num>"),
       update : Long("<num>"),
       delete : Long("<num>"),
       getmore : Long("<num>"),
       command : Long("<num>"),
    }
    */
    ```
    - `shard_reads_qps` - rate(opcounters.query + opcounters.command на чтение).
    - `shard_writes_qps` - rate(opcounters.insert + update + delete).
2. Latency запросов по шарду:
   - Количество операций и конфликтов:
     ```js
     db.serverStatus().metrics.operation
     /*
     {
       scanAndOrder: { total: 123, time: 456 },
       writeConflicts: { ... },
     }
     */
     ```
   - Можно включить profiling на slow-query, и из system.profile:
       ```js
       db.setProfilingLevel(1, { slowms: 50 }); // всё, что >50мс
       db.system.profile.aggregate([
         { $match: { ns: "mobile_world.products" } },
           { $group: {
             _id: null,
             p95_ms: {
               $percentile: { input: "$millis", p: [0.95] }
             }
           }}
        ]);
      ```
3. Статусы репликации:
    ```js
    rs.printSecondaryReplicationInfo()
    /*
    source: m1.example.net:27002
        syncedTo: Mon Mar 01 2021 16:30:50 GMT-0800 (PST)
        0 secs (0 hrs) behind the primary
    source: m2.example.net:27003
        syncedTo: Mon Mar 01 2021 16:30:50 GMT-0800 (PST)
        0 secs (0 hrs) behind the primary
    ...
    */
    ```
4. Ресурсы:
   - % использования CPU шардов
   - % дисковой IO-задержки шардов
   - Чтение с диска (байт/сек) на шардах
   - Запись на диск (байт/сек) на шардах
   - Количество активных подключений на шардах
5. Метрики по чанкам и распределению данных:
    ```js
    db.getSiblingDB("config").chunks.aggregate([
      { $match: { ns: "mobile_world.products" } },
      { $group: { _id: "$shard", chunks: { $sum: 1 } } }
    ]);
    /*
    { _id: "shard01", chunks: 120 }
    { _id: "shard02", chunks: 80  }
    { _id: "shard03", chunks: 95  }
    */
    ```
6. Количество данных на шард:
    ```js
    db.getSiblingDB("mobile_world").products.stats({ scale: 1024*1024 })
    /*
    {
      ns: "mobile_world.products",
      size: ...,
      sharded: true,
      shards: {
        shard01: { size: 8000, count: 500k, ... },
        shard02: { size: 3000, count: 150k, ... },
        shard03: { size: 3200, count: 160k, ... }
      }
    }
    ```
7. Задержки выполнения операций:
    ```js
    db.serverStatus().opLatencies
    /*
    {
      reads:  { latency: NumberLong("123456"), ops: NumberLong("7890") },
      writes: { latency: NumberLong("23456"),  ops: NumberLong("345")  },
      commands: { ... }
    }
    */
    ```
    - На основе latency или ops можно вычислить среднюю latency, а в мониторинге - агрегировать.


## Механизмы автоматического перераспределения данных

1. Встроенный балансировщик MongDB:
    
    Балансировщик уравнивает количество и размер чанков между шардами.
    ```js
    // Проверка состояния балансировщика
    sh.getBalancerState();
    
    // Включение балансировщика
    sh.setBalancerState(true);
    
    // Настройка размера чанка (по умолчанию 64MB, можно снизить для более тонкого сплита)
    db.getSiblingDB("config").settings.update(
      { _id: "chunksize" },
      { $set: { value: 32 } },     // 32MB
      { upsert: true }
    );
    ```
2. Дробление горячих чанков по цене:

    Идея заключается в том, чтобы один большой чанк разделить на несколько более мелких чанков командой `sh.splitAt(namespace, query)`, каждый из которых может быть перенесён на другой шард. 
    Например, по цене:
    ```js
    sh.splitAt(
      "mobile_world.products",
      { category: "electronics", price: 10000 }
    );
    
    sh.splitAt(
      "mobile_world.products",
      { category: "electronics", price: 20000 }
    );
    
    sh.splitAt(
      "mobile_world.products",
      { category: "electronics", price: 50000 }
    );
    ```
   
3. Перераспределение данных между шардами:
    
    После предварительного splitAt один большой чанк electronics делится на несколько диапазонов по цене. Каждый диапазон можно перенести на менее загруженный шард через sh.moveChunk. Таким образом мы не только уменьшаем размер горячих чанков, но и физически распределяем их между шардами.

    Например, перенести часть "electronics" до 20к на shard02:
      ```js
      // Пример: перенести часть "electronics" до 20k на shard02
      sh.moveChunk(
        "mobile_world.products",
        { category: "electronics", price: 15000 },
        "shard02"
      );
        
      // И, например, диапазон 20k–50k на shard03
      sh.moveChunk(
        "mobile_world.products",
        { category: "electronics", price: 30000 },
        "shard03"
      );
      ```
4. Включение авторазделение чанков:
    
    В старых версиях MongoDB до 6.0.3 можно явно управлять авторазделением через `sh.disableAutoSplit()` / `sh.enableAutoSplit()`. 

    В современных версиях авторазделение включено по умолчанию, и основной способ управления - это размер чанка (`chunksize`) и явные `sh.splitAt(...)`.
