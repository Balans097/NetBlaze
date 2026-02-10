# IMDB Reviews Scraper - Комплексный пример NimBrowser

> **Полнофункциональный пример использования библиотеки NimBrowser v1.0**

---

## 📋 Содержание

- [Обзор](#обзор)
- [Демонстрируемые возможности](#демонстрируемые-возможности)
- [Структура примера](#структура-примера)
- [Установка и запуск](#установка-и-запуск)
- [Архитектура решения](#архитектура-решения)
- [Детальный разбор кода](#детальный-разбор-кода)
- [Выходные данные](#выходные-данные)
- [Расширение примера](#расширение-примера)

---

## 🎯 Обзор

Этот пример демонстрирует **профессиональный подход** к веб-скрейпингу с использованием NimBrowser. Мы создали полноценный скрейпер отзывов IMDB, который показывает все основные возможности библиотеки.

**Цель:** Извлечение отзывов на фильм "Terminator 3: Rise of the Machines" (2003)  
**URL:** https://www.imdb.com/title/tt0181852/reviews

### Что извлекается

```json
{
  "review_id": "rw1234567",
  "title": "Best action movie of 2002!",
  "rating": "9",
  "review_text": "This movie is absolutely fantastic! Matt Damon delivers...",
  "author": "JohnDoe",
  "author_url": "https://www.imdb.com/user/ur12345",
  "review_date": "15 January 2020",
  "helpful_count": "542 out of 678 found this helpful",
  "has_spoiler": false,
  "sentiment": "positive",
  "word_count": 42,
  "review_length": 245,
  "scraped_at": "2026-02-10T14:30:00"
}
```

---

## ✨ Демонстрируемые возможности

### 1. CSS Селекторы

#### Базовые селекторы
```nim
# По классу
.css(".review-container")

# По атрибуту
.css("[data-review-id]")

# Комбинированные
.css(".rating-other-user-rating span")
```

#### Сложные селекторы
```nim
# Вложенные структуры
.css(".content .text.show-more__control")

# Атрибутные селекторы с data-*
.css("[data-key]")
```

### 2. XPath Запросы

```nim
# Альтернативный способ извлечения рейтинга
loader.addXPath("rating", 
  ".//span[@class='rating-other-user-rating']/span")
```

### 3. Response API

```nim
# Chainable методы
let reviews = response.css(".review-container").getall()

# Извлечение атрибутов
let nextKey = response.css(".load-more-trigger").attrib("data-key")
```

### 4. ItemLoader с процессорами

```nim
# Input processor - обработка входных данных
proc cleanText(values: seq[string]): seq[string] =
  result = @[]
  for value in values:
    result.add normalizeWhitespace(value.strip())

# Output processor - обработка финального значения
proc takeFirst(values: seq[string]): string =
  for value in values:
    if value.strip().len > 0:
      return value
  return ""

# Использование
loader.addCss("title", "a.title",
              inputProcessor = cleanText,
              outputProcessor = takeFirst)
```

### 5. Middleware система

```nim
# Логирование запросов
type LoggingMiddleware = ref object of DownloaderMiddleware
  requestCount: int

method processRequest(m: LoggingMiddleware, ...) =
  m.requestCount += 1
  echo "REQUEST #", m.requestCount

# User-Agent
type UserAgentMiddleware = ref object of DownloaderMiddleware
  userAgent: string
```

### 6. Pipeline обработка

```nim
# Валидация
method processItem(p: ValidationPipeline, item: var Item): bool =
  if not item.hasKey("review_text"):
    return false  # Отбросить
  return true     # Сохранить

# Дедупликация
method processItem(p: DuplicatesPipeline, item: var Item): bool =
  if reviewId in p.seenReviews:
    return false
  p.seenReviews.incl(reviewId)
  return true

# Обогащение
method processItem(p: EnrichmentPipeline, item: var Item): bool =
  item["scraped_at"] = %($now())
  item["word_count"] = %(text.split().len)
  return true
```

### 7. Асинхронная загрузка

```nim
proc scrapeAllPages(scraper: IMDBReviewsScraper) {.async.} =
  for page in 1..MAX_PAGES:
    let response = await fetchAsync(url)
    let reviews = await scrapePage(response)
    await sleepAsync(REQUEST_DELAY)
```

### 8. Обработка пагинации

```nim
proc getNextPageUrl(response: Response): string =
  let nextButton = response.css(".load-more-trigger")
  if not nextButton.node.isNil:
    return REVIEWS_URL & "/_ajax?paginationKey=" & nextButton.attrib("data-key")
  return ""
```

### 9. Множественные форматы экспорта

```nim
# JSON
writeFile("reviews.json", $(%scraper.allReviews).pretty())

# JSON Lines
writeFile("reviews.jsonl", scraper.allReviews.toJsonLines())

# CSV
let csv = scraper.allReviews.toCsv(headers)
writeFile("reviews.csv", csv)
```

### 10. Статистика и отчёты

```nim
type ScrapingStats = object
  requestsCount: int
  itemsScraped: int
  startTime: DateTime
  endTime: DateTime

# Автоматический подсчёт метрик
scraper.stats.itemsScraped += 1
scraper.stats.finish()
```

---

## 🏗️ Структура примера

```
imdb_reviews_scraper.nim
│
├── КОНФИГУРАЦИЯ
│   ├── Константы (URL, задержки)
│   └── Настройки скрейпинга
│
├── DATA PROCESSORS
│   ├── cleanText()          - Очистка текста
│   ├── extractRating()      - Извлечение рейтинга
│   ├── parseDate()          - Парсинг дат
│   ├── joinWithNewline()    - Объединение строк
│   └── cleanUrl()           - Обработка URL
│
├── MIDDLEWARE
│   ├── LoggingMiddleware    - Логирование запросов/ответов
│   └── UserAgentMiddleware  - Установка User-Agent
│
├── PIPELINES
│   ├── ValidationPipeline   - Валидация данных
│   ├── EnrichmentPipeline   - Обогащение данных
│   └── DuplicatesPipeline   - Фильтрация дубликатов
│
├── SCRAPER CLASS
│   ├── newIMDBReviewsScraper()  - Инициализация
│   ├── extractReviewData()      - Извлечение отзыва
│   ├── scrapePage()             - Обработка страницы
│   ├── scrapeAllPages()         - Полный цикл скрейпинга
│   └── getNextPageUrl()         - Пагинация
│
├── MOCK DATA
│   └── createMockResponse()     - Тестовые данные
│
├── EXPORT & REPORTING
│   ├── exportResults()          - Экспорт в файлы
│   ├── printStatistics()        - Статистика
│   └── printSampleReviews()     - Примеры отзывов
│
└── MAIN
    └── main()                   - Точка входа
```

---

## 🚀 Установка и запуск

### Требования

- Nim 1.6.0 или выше
- NimBrowser библиотека

### Компиляция

```bash
nim c -d:release imdb_reviews_scraper.nim
```

### Запуск

```bash
./imdb_reviews_scraper
```

### Пример вывода

```
╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║              IMDB REVIEWS SCRAPER - NimBrowser Demo                    ║
║                                                                        ║
║  Демонстрация возможностей библиотеки NimBrowser v1.0                 ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝

✓ Query cache enabled

╔════════════════════════════════════════════════════════════════════════
║ PAGE 1 / 3
╚════════════════════════════════════════════════════════════════════════
┌────────────────────────────────────────────────────────────
│ REQUEST #1
│ URL: https://www.imdb.com/title/tt0181852/reviews
└────────────────────────────────────────────────────────────

╔════════════════════════════════════════════════════════════
║ PARSING PAGE
╚════════════════════════════════════════════════════════════
Found 3 reviews on this page

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Review #1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  → Extracting review data...
  ✓ Review extracted
  [PIPELINE] Validating item...
  [PIPELINE] ✓ Valid
  [PIPELINE] ✓ Unique
  [PIPELINE] Enriching item...
  [PIPELINE] ✓ Enriched
  ✓ Review saved

...

╔════════════════════════════════════════════════════════════════════
║ SCRAPING STATISTICS
╚════════════════════════════════════════════════════════════════════

  📊 Total requests:      3
  📝 Reviews scraped:     9
  ⏱️  Duration:            0 seconds
  🎯 Success rate:        300.00%

  📈 RATINGS DISTRIBUTION:
     10/10: ███ (3)
     9/10: ███ (3)
     6/10: ███ (3)

  😊 SENTIMENT ANALYSIS:
     Positive: 6
     Neutral: 3

  ✍️  AVERAGE REVIEW LENGTH: 45 words
```

---

## 🔧 Архитектура решения

### Поток данных

```
┌─────────────┐
│   START     │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│  Initialize Scraper │
│  - Middleware       │
│  - Pipelines        │
│  - Stats            │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│  For each page:     │
│                     │
│  ┌───────────────┐  │
│  │ 1. Request    │  │
│  │ Middleware    │  │
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ 2. Fetch      │  │
│  │ (async)       │  │
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ 3. Response   │  │
│  │ Middleware    │  │
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ 4. Parse      │  │
│  │ Reviews       │  │
│  └───────┬───────┘  │
│          │          │
│  │   For each    │  │
│  │   review:     │  │
│  │               │  │
│  │ ┌─────────┐   │  │
│  │ │Extract  │   │  │
│  │ │ItemLoad.│   │  │
│  │ └────┬────┘   │  │
│  │      │        │  │
│  │ ┌────▼────┐   │  │
│  │ │Pipeline │   │  │
│  │ │1:Valid. │   │  │
│  │ └────┬────┘   │  │
│  │      │        │  │
│  │ ┌────▼────┐   │  │
│  │ │Pipeline │   │  │
│  │ │2:Dedup  │   │  │
│  │ └────┬────┘   │  │
│  │      │        │  │
│  │ ┌────▼────┐   │  │
│  │ │Pipeline │   │  │
│  │ │3:Enrich │   │  │
│  │ └────┬────┘   │  │
│  │      │        │  │
│  │ ┌────▼────┐   │  │
│  │ │  Save   │   │  │
│  │ └─────────┘   │  │
│  │               │  │
│  ┌───────▼───────┐  │
│  │ 5. Pagination │  │
│  └───────┬───────┘  │
│          │          │
└──────────┼──────────┘
           │
       ┌───▼────┐
       │ More?  │
       └───┬────┘
           │ No
           ▼
   ┌───────────────┐
   │ 6. Export     │
   │ - JSON        │
   │ - JSON Lines  │
   │ - CSV         │
   └───────┬───────┘
           │
           ▼
   ┌───────────────┐
   │ 7. Statistics │
   │ & Reports     │
   └───────┬───────┘
           │
           ▼
      ┌────────┐
      │  DONE  │
      └────────┘
```

### Обработка отдельного отзыва

```
Review HTML
    │
    ▼
┌─────────────────┐
│  ItemLoader     │
│  (создание)     │
└────────┬────────┘
         │
    ┌────┴────────────────────────────┐
    │                                 │
    ▼                                 ▼
┌────────────┐                 ┌──────────────┐
│ CSS        │                 │ XPath        │
│ Selectors  │                 │ Queries      │
└─────┬──────┘                 └──────┬───────┘
      │                               │
      └────────────┬──────────────────┘
                   │
    ┌──────────────┼──────────────┐
    │              │              │
    ▼              ▼              ▼
┌────────┐   ┌──────────┐   ┌─────────┐
│ Input  │   │ Process  │   │ Output  │
│ Proc.  │──▶│   Data   │──▶│ Proc.   │
└────────┘   └──────────┘   └─────────┘
                   │
                   ▼
            ┌─────────────┐
            │   Item      │
            │ (extracted) │
            └─────────────┘
```

---

## 📖 Детальный разбор кода

### 1. Data Processors

#### cleanText - Очистка текста

```nim
proc cleanText(values: seq[string]): seq[string] =
  result = @[]
  for value in values:
    var cleaned = value
    cleaned = cleaned.strip()              # Убрать начальные/конечные пробелы
    cleaned = normalizeWhitespace(cleaned) # Нормализовать внутренние пробелы
    if cleaned.len > 0:
      result.add cleaned
```

**Использование:**
```nim
loader.addCss("title", "a.title", inputProcessor = cleanText)
```

**Пример:**
```
Input:  "  Best   movie\n\n   ever!  "
Output: "Best movie ever!"
```

#### extractRating - Извлечение рейтинга

```nim
proc extractRating(values: seq[string]): seq[string] =
  result = @[]
  for value in values:
    let pattern = re"(\d+)/10"
    var matches: array[1, string]
    if value.find(pattern, matches) != -1:
      result.add matches[0]  # Только число
    else:
      result.add ""
```

**Пример:**
```
Input:  "8/10"
Output: "8"
```

### 2. Извлечение данных с Selector API

```nim
proc extractReviewData(scraper: IMDBReviewsScraper, 
                      reviewElement: Selector): Item =
  result = initTable[string, JsonNode]()
  
  # Заголовок с двумя альтернативными селекторами
  var title = reviewElement.css("a.title").get()
  if title.len == 0:
    title = reviewElement.css(".review-summary").get()
  if title.len > 0:
    result["title"] = %title.strip()
  
  # Рейтинг с обработкой через процессор
  let ratingElements = reviewElement.css(".rating-other-user-rating span")
  if not ratingElements.node.isNil:
    let ratingText = ratingElements.get()
    let ratingCleaned = extractRating(@[ratingText])
    if ratingCleaned.len > 0:
      result["rating"] = %ratingCleaned[0]
  
  # Текст с нормализацией пробелов
  var reviewText = reviewElement.css(".text.show-more__control").get()
  if reviewText.len == 0:
    reviewText = reviewElement.css(".content .text").get()
  if reviewText.len > 0:
    result["review_text"] = %normalizeWhitespace(reviewText.strip())
  
  # URL с преобразованием в абсолютный
  let authorUrl = reviewElement.css(".display-name-link").attrib("href")
  if authorUrl.len > 0:
    result["author_url"] = %urljoin(BASE_URL, authorUrl)
  
  # Прямое добавление значений
  let hasSpoiler = not reviewElement.css(".spoiler-warning").node.isNil
  result["has_spoiler"] = %hasSpoiler
```

### 3. Pipeline цепочка

```nim
# Последовательная обработка через pipelines
var shouldSave = true

# 1. Validation
shouldSave = scraper.validationPipeline.processItem(item)

if shouldSave:
  # 2. Deduplication
  shouldSave = scraper.duplicatesPipeline.processItem(item)

if shouldSave:
  # 3. Enrichment
  shouldSave = scraper.enrichmentPipeline.processItem(item)

if shouldSave:
  result.add item
```

**Логика работы:**
- Если любой pipeline вернёт `false`, обработка останавливается
- Item не добавляется в результаты
- Последовательность имеет значение (validation → deduplication → enrichment)

### 4. Асинхронная обработка страниц

```nim
proc scrapeAllPages(scraper: IMDBReviewsScraper) {.async.} =
  var currentPage = 1
  var currentUrl = REVIEWS_URL
  
  while currentPage <= MAX_PAGES:
    # Middleware: request
    scraper.loggingMiddleware.processRequest(request, dummyResponse)
    
    # Fetch (async)
    let response = await fetchAsync(currentUrl)
    scraper.stats.requestsCount += 1
    
    # Middleware: response
    scraper.loggingMiddleware.processResponse(request, response)
    
    # Parse (async)
    let reviews = await scraper.scrapePage(response)
    scraper.allReviews.add reviews
    
    # Pagination
    currentUrl = getNextPageUrl(response)
    if currentUrl.len == 0:
      break
    
    currentPage += 1
    
    # Delay
    await sleepAsync(REQUEST_DELAY)
```

---

## 📊 Выходные данные

### 1. JSON (imdb_reviews.json)

```json
[
  {
    "review_id": "rw1234567",
    "title": "Best action movie of 2002!",
    "rating": "9",
    "review_text": "This movie is absolutely fantastic!...",
    "author": "JohnDoe",
    "author_url": "https://www.imdb.com/user/ur12345",
    "review_date": "15 January 2020",
    "helpful_count": "542 out of 678 found this helpful",
    "has_spoiler": false,
    "sentiment": "positive",
    "word_count": 42,
    "review_length": 245,
    "scraped_at": "2026-02-10T14:30:00"
  },
  ...
]
```

### 2. JSON Lines (imdb_reviews.jsonl)

```json
{"review_id":"rw1234567","title":"Best action movie!","rating":"9",...}
{"review_id":"rw2345678","title":"Good but not great","rating":"6",...}
{"review_id":"rw3456789","title":"Amazing thriller!","rating":"10",...}
```

**Преимущества:**
- Построчная обработка
- Удобно для больших датасетов
- Легко добавлять новые записи

### 3. CSV (imdb_reviews.csv)

```csv
review_id,title,rating,review_text,author,review_date,helpful_count,sentiment,word_count,scraped_at
"rw1234567","Best action movie!","9","This movie is...","JohnDoe","15 Jan 2020","542 out of 678","positive","42","2026-02-10T14:30:00"
"rw2345678","Good but not great","6","The movie has...","MovieCritic","22 Mar 2019","123 out of 234","neutral","28","2026-02-10T14:30:00"
```

**Использование:**
- Анализ в Excel/Google Sheets
- Импорт в базы данных
- Машинное обучение

---

## 🔄 Расширение примера

### Добавление новых полей

```nim
# В extractReviewData()

# Извлечение количества комментариев
let commentsText = reviewElement.css(".comment-count").get()
if commentsText.len > 0:
  result["comments_count"] = %commentsText.strip()

# Проверка на verified purchase
let isVerified = not reviewElement.css(".verified-badge").node.isNil
result["is_verified"] = %isVerified

# Извлечение изображений
let images = reviewElement.css("img").getall()
var imageUrls: seq[string] = @[]
for img in images:
  let imgUrl = img.attrib("src")
  if imgUrl.len > 0:
    imageUrls.add urljoin(BASE_URL, imgUrl)
if imageUrls.len > 0:
  result["images"] = %imageUrls
```

### Новый Pipeline

```nim
type
  FilterByRatingPipeline = ref object of Pipeline
    minRating: int

method processItem(p: FilterByRatingPipeline, item: var Item): bool =
  if item.hasKey("rating"):
    let rating = $(item["rating"])
    try:
      if parseInt(rating) < p.minRating:
        return false  # Отбросить низкий рейтинг
    except:
      discard
  return true

# Использование
let filterPipeline = FilterByRatingPipeline(minRating: 7)
shouldSave = filterPipeline.processItem(item)
```

### Расширенная статистика

```nim
proc analyzeReviews(reviews: seq[Item]) =
  # Распределение по датам
  var dateDistribution = initTable[string, int]()
  
  for review in reviews:
    if review.hasKey("review_date"):
      let date = $(review["review_date"])
      let year = date.split()[^1]  # Последнее слово - год
      dateDistribution[year] = dateDistribution.getOrDefault(year, 0) + 1
  
  echo "Reviews by year:"
  for year, count in dateDistribution:
    echo "  ", year, ": ", count
```

### Экспорт в базу данных

```nim
import db_sqlite

proc saveToDatabase(reviews: seq[Item], dbPath: string) =
  let db = open(dbPath, "", "", "")
  
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS reviews (
      id TEXT PRIMARY KEY,
      title TEXT,
      rating INTEGER,
      review_text TEXT,
      author TEXT,
      review_date TEXT,
      sentiment TEXT,
      scraped_at DATETIME
    )
  """)
  
  for review in reviews:
    db.exec(sql"""
      INSERT OR REPLACE INTO reviews VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """,
      $(review["review_id"]),
      $(review["title"]),
      $(review["rating"]),
      $(review["review_text"]),
      $(review["author"]),
      $(review["review_date"]),
      $(review["sentiment"]),
      $(review["scraped_at"])
    )
  
  db.close()
```

### Retry механизм

```nim
type
  RetryMiddleware = ref object of DownloaderMiddleware
    maxRetries: int
    retryDelay: int

proc fetchWithRetry(url: string, maxRetries: int): Future[Response] {.async.} =
  var attempts = 0
  
  while attempts < maxRetries:
    try:
      result = await fetchAsync(url)
      if result.status == 200:
        return result
    except:
      attempts += 1
      if attempts >= maxRetries:
        raise
      
      echo "Retry ", attempts, "/", maxRetries
      await sleepAsync(2000 * attempts)  # Exponential backoff
```

---

## 🎓 Обучающие моменты

### 2. Извлечение данных

**Без процессоров:**
```nim
var item = newItem()
item["title"] = reviewElement.css("a.title").get().strip()
item["rating"] = reviewElement.css(".rating span").get().replace("/10", "")
# ... много повторяющегося кода
```

**С процессорами данных:**
```nim
# Применение процессоров вручную
let ratingText = reviewElement.css(".rating span").get()
let ratingCleaned = extractRating(@[ratingText])
result["rating"] = %ratingCleaned[0]

# Обработка текста
let text = reviewElement.css(".text").get()
result["text"] = %normalizeWhitespace(text.strip())

# Чище, переиспользуемо, тестируемо
```

### 2. Зачем Pipelines?

**Разделение ответственности:**
- ValidationPipeline — только валидация
- DuplicatesPipeline — только дедупликация
- EnrichmentPipeline — только обогащение

**Преимущества:**
- Легко добавлять/убирать обработку
- Тестировать отдельно
- Переиспользовать в других проектах

### 3. Mock данные для тестирования

```nim
proc createMockResponse(pageNum: int): Response =
  # Реалистичная структура HTML
  # Позволяет тестировать без реальных запросов
  # Важно для разработки и отладки
```

---

## ⚠️ Важные замечания

### Этика скрейпинга

1. **Проверяйте robots.txt**
   ```
   https://www.imdb.com/robots.txt
   ```

2. **Используйте разумные задержки**
   ```nim
   const REQUEST_DELAY = 2000  # 2 секунды
   ```

3. **Уважайте Terms of Service**

4. **Идентифицируйте себя**
   ```nim
   userAgent: "MyBot/1.0 (contact@example.com)"
   ```

### Обработка ошибок

```nim
proc safeScrape(url: string): Future[Response] {.async.} =
  try:
    result = await fetchAsync(url)
  except HttpRequestError:
    echo "Network error"
    result = nil
  except:
    echo "Unknown error: ", getCurrentExceptionMsg()
    result = nil
```

---

## 📚 Дополнительные ресурсы

- [NimBrowser Documentation](./nimbrowser_documentation.md)
- [CSS Selectors Reference](https://www.w3.org/TR/css3-selectors/)
- [XPath Tutorial](https://www.w3schools.com/xml/xpath_intro.asp)
- [Nim Language](https://nim-lang.org/)

---

## ✅ Checklist для реального скрейпинга

- [ ] Проверить robots.txt
- [ ] Добавить User-Agent
- [ ] Реализовать retry механизм
- [ ] Логирование ошибок
- [ ] Обработка капчи (если требуется)
- [ ] Прокси поддержка (для масштабирования)
- [ ] Сохранение прогресса (resume capability)
- [ ] Мониторинг и алерты
- [ ] Тестирование на небольшом датасете
- [ ] Документирование селекторов

---

**Этот пример демонстрирует профессиональный подход к веб-скрейпингу с NimBrowser!** 🚀
