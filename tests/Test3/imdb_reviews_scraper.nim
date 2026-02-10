## ============================================================================
## IMDB Reviews Scraper - Комплексный пример использования NimBrowser
## ============================================================================
## 
## Этот пример демонстрирует все основные возможности библиотеки NimBrowser:
## 
## ✓ CSS селекторы (простые и сложные)
## ✓ XPath запросы
## ✓ Response и Selector API
## ✓ ItemLoader с процессорами данных
## ✓ Middleware система
## ✓ Pipeline обработка
## ✓ Асинхронная загрузка
## ✓ Обработка пагинации
## ✓ Извлечение вложенных данных
## ✓ Экспорт в различные форматы
## ✓ Кэширование
## ✓ Обработка ошибок
## 
## Цель: Извлечение отзывов на фильм "Terminator 3: Rise of the Machines" (2003)
## URL: https://www.imdb.com/title/tt0181852/reviews
##
## ============================================================================

import nimbrowser
import asyncdispatch
import strutils
import times
import json
import re
import tables
import sets
import httpclient

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

const
  MOVIE_ID = "tt0181852"  # Terminator 3: Rise of the Machines
  BASE_URL = "https://www.imdb.com"
  REVIEWS_URL = BASE_URL & "/title/" & MOVIE_ID & "/reviews"
  MAX_PAGES = 3  # Максимум страниц для скрейпинга
  REQUEST_DELAY = 2000  # Задержка между запросами в миллисекундах

# ============================================================================
# DATA PROCESSORS - Обработчики данных
# ============================================================================

proc cleanText(values: seq[string]): seq[string] =
  ## Очищает текст от лишних пробелов и переносов строк
  result = @[]
  for value in values:
    var cleaned = value
    cleaned = cleaned.strip()
    cleaned = normalizeWhitespace(cleaned)
    if cleaned.len > 0:
      result.add cleaned

proc extractRating(values: seq[string]): seq[string] =
  ## Извлекает числовой рейтинг из строки "8/10"
  result = @[]
  for value in values:
    let pattern = re"(\d+)/10"
    var matches: array[1, string]
    if value.find(pattern, matches) != -1:
      result.add matches[0]
    else:
      result.add ""

proc parseDate(values: seq[string]): seq[string] =
  ## Парсит дату из формата IMDB
  result = @[]
  for value in values:
    var cleaned = value.strip()
    # IMDB использует формат типа "12 January 2020"
    result.add cleaned

proc joinWithNewline(values: seq[string]): string =
  ## Объединяет значения с переносом строки
  return values.join("\n")

proc takeFirst(values: seq[string]): string =
  ## Берёт первое непустое значение
  for value in values:
    if value.strip().len > 0:
      return value
  return ""

proc cleanUrl(values: seq[string]): seq[string] =
  ## Очищает и преобразует URL в абсолютные
  result = @[]
  for value in values:
    var url = value.strip()
    if url.len > 0:
      if not url.startsWith("http"):
        url = urljoin(BASE_URL, url)
      result.add url

# ============================================================================
# MIDDLEWARE - Логирование и обработка запросов
# ============================================================================

type
  LoggingMiddleware = ref object of DownloaderMiddleware
    requestCount: int
    
  UserAgentMiddleware = ref object of DownloaderMiddleware
    userAgent: string

method processRequest*(m: LoggingMiddleware,
                      req: var string,
                      resp: var Response) =
  m.requestCount += 1
  echo "┌────────────────────────────────────────────────────────────"
  echo "│ REQUEST #", m.requestCount
  echo "│ URL: ", req
  echo "└────────────────────────────────────────────────────────────"

method processResponse*(m: LoggingMiddleware,
                       req: string,
                       resp: var Response) =
  echo "┌────────────────────────────────────────────────────────────"
  echo "│ RESPONSE"
  echo "│ Status: ", resp.status
  echo "│ Body length: ", resp.body.len, " bytes"
  echo "└────────────────────────────────────────────────────────────"

method processRequest*(m: UserAgentMiddleware,
                      req: var string,
                      resp: var Response) =
  # В реальном приложении здесь бы устанавливался User-Agent
  discard

# ============================================================================
# PIPELINES - Обработка извлечённых данных
# ============================================================================

type
  ValidationPipeline = ref object of Pipeline
    
  EnrichmentPipeline = ref object of Pipeline
    
  DuplicatesPipeline = ref object of Pipeline
    seenReviews: HashSet[string]

method processItem*(p: ValidationPipeline, item: var Item): bool =
  ## Валидация обязательных полей
  echo "  [PIPELINE] Validating item..."
  
  # Проверка обязательных полей
  if not item.hasKey("review_text"):
    echo "  [PIPELINE] ❌ Skipped: missing review_text"
    return false
  
  let text = $(item["review_text"])
  if text.strip().len < 10:
    echo "  [PIPELINE] ❌ Skipped: review too short"
    return false
  
  echo "  [PIPELINE] ✓ Valid"
  return true

method processItem*(p: EnrichmentPipeline, item: var Item): bool =
  ## Обогащение данных
  echo "  [PIPELINE] Enriching item..."
  
  # Добавление timestamp
  item["scraped_at"] = %($now())
  
  # Вычисление длины отзыва
  if item.hasKey("review_text"):
    let text = $(item["review_text"])
    item["review_length"] = %(text.len)
    item["word_count"] = %(text.split().len)
  
  # Определение тональности (простая эвристика)
  if item.hasKey("rating"):
    let rating = $(item["rating"])
    if rating.len > 0:
      try:
        let ratingValue = parseInt(rating)
        if ratingValue >= 8:
          item["sentiment"] = %"positive"
        elif ratingValue >= 5:
          item["sentiment"] = %"neutral"
        else:
          item["sentiment"] = %"negative"
      except:
        item["sentiment"] = %"unknown"
  
  echo "  [PIPELINE] ✓ Enriched"
  return true

method processItem*(p: DuplicatesPipeline, item: var Item): bool =
  ## Фильтрация дубликатов
  if item.hasKey("review_id"):
    let reviewId = $(item["review_id"])
    if reviewId in p.seenReviews:
      echo "  [PIPELINE] ❌ Skipped: duplicate review"
      return false
    p.seenReviews.incl(reviewId)
  
  echo "  [PIPELINE] ✓ Unique"
  return true

# ============================================================================
# SCRAPER CLASS - Основной класс скрейпера
# ============================================================================

type
  IMDBReviewsScraper = ref object
    stats: ScrapingStats
    loggingMiddleware: LoggingMiddleware
    userAgentMiddleware: UserAgentMiddleware
    validationPipeline: ValidationPipeline
    enrichmentPipeline: EnrichmentPipeline
    duplicatesPipeline: DuplicatesPipeline
    allReviews: seq[Item]

proc newIMDBReviewsScraper(): IMDBReviewsScraper =
  result = IMDBReviewsScraper()
  result.stats = newScrapingStats()
  result.loggingMiddleware = LoggingMiddleware()
  result.userAgentMiddleware = UserAgentMiddleware(userAgent: "Mozilla/5.0")
  result.validationPipeline = ValidationPipeline()
  result.enrichmentPipeline = EnrichmentPipeline()
  result.duplicatesPipeline = DuplicatesPipeline()
  result.allReviews = @[]

proc extractReviewData(scraper: IMDBReviewsScraper, reviewElement: Selector): Item =
  ## Извлекает данные одного отзыва
  echo "  → Extracting review data..."
  
  result = initTable[string, JsonNode]()
  
  # === БАЗОВАЯ ИНФОРМАЦИЯ ===
  
  # ID отзыва (из data-review-id атрибута)
  let reviewNode = reviewElement.node
  if not reviewNode.isNil:
    let reviewId = reviewNode.getAttr("data-review-id", "")
    if reviewId.len > 0:
      result["review_id"] = %reviewId
  
  # Заголовок отзыва - несколько вариантов селекторов
  var title = reviewElement.css("a.title").get()
  if title.len == 0:
    title = reviewElement.css(".review-summary").get()
  if title.len > 0:
    result["title"] = %title.strip()
  
  # === РЕЙТИНГ ===
  
  # Рейтинг пользователя (например, "8/10")
  let ratingElements = reviewElement.css(".rating-other-user-rating span")
  if not ratingElements.node.isNil:
    let ratingText = ratingElements.get()
    let ratingCleaned = extractRating(@[ratingText])
    if ratingCleaned.len > 0 and ratingCleaned[0].len > 0:
      result["rating"] = %ratingCleaned[0]
  
  # === ТЕКСТ ОТЗЫВА ===
  
  # Полный текст отзыва
  var reviewText = reviewElement.css(".text.show-more__control").get()
  if reviewText.len == 0:
    reviewText = reviewElement.css(".content .text").get()
  if reviewText.len > 0:
    result["review_text"] = %normalizeWhitespace(reviewText.strip())
  
  # === ИНФОРМАЦИЯ ОБ АВТОРЕ ===
  
  # Имя автора
  var author = reviewElement.css(".display-name-link").get()
  if author.len == 0:
    author = reviewElement.css("span[itemprop='author']").get()
  if author.len > 0:
    result["author"] = %author.strip()
  
  # Ссылка на профиль автора
  let authorUrl = reviewElement.css(".display-name-link").attrib("href")
  if authorUrl.len > 0:
    let absoluteUrl = urljoin(BASE_URL, authorUrl)
    result["author_url"] = %absoluteUrl
  
  # === ДАТА ПУБЛИКАЦИИ ===
  
  # Дата отзыва
  let reviewDate = reviewElement.css(".review-date").get()
  if reviewDate.len > 0:
    result["review_date"] = %reviewDate.strip()
  
  # === ПОЛЕЗНОСТЬ ОТЗЫВА ===
  
  # Количество людей, которые нашли отзыв полезным
  let helpfulText = reviewElement.css(".actions.text-muted").get()
  if helpfulText.len > 0:
    result["helpful_count"] = %helpfulText.strip()
  
  # === СПОЙЛЕРЫ ===
  
  # Проверка на спойлеры
  let hasSpoiler = not reviewElement.css(".spoiler-warning").node.isNil
  result["has_spoiler"] = %hasSpoiler
  
  echo "  ✓ Review extracted"

proc scrapePage(scraper: IMDBReviewsScraper, 
                response: Response): seq[Item] =
  ## Извлекает все отзывы со страницы
  result = @[]
  
  echo ""
  echo "╔════════════════════════════════════════════════════════════"
  echo "║ PARSING PAGE"
  echo "╚════════════════════════════════════════════════════════════"
  
  # Получаем корневой узел документа
  if response.root.isNil:
    echo "Error: Response root is nil"
    return
  
  # CSS селектор для контейнера отзыва - работаем с XmlNode напрямую
  let reviewNodes = response.root.querySelectorAll(".review-container")
  
  echo "Found ", reviewNodes.len, " reviews on this page"
  echo ""
  
  for i, reviewNode in reviewNodes:
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Review #", i + 1
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Создаём Selector из XmlNode
    var reviewSelector = Selector()
    new(reviewSelector)
    reviewSelector.node = reviewNode
    reviewSelector.response = response
    reviewSelector.selectorType = stCss
    
    var item = scraper.extractReviewData(reviewSelector)
    
    # Применение pipelines
    var shouldSave = true
    
    # Pipeline 1: Validation
    shouldSave = scraper.validationPipeline.processItem(item)
    
    if shouldSave:
      # Pipeline 2: Deduplication
      shouldSave = scraper.duplicatesPipeline.processItem(item)
    
    if shouldSave:
      # Pipeline 3: Enrichment
      shouldSave = scraper.enrichmentPipeline.processItem(item)
    
    if shouldSave:
      result.add item
      scraper.stats.itemsScraped += 1
      echo "  ✓ Review saved"
    
    echo ""

proc getNextPageUrl(response: Response): string =
  ## Извлекает URL следующей страницы
  let nextButton = response.css(".load-more-trigger")
  if not nextButton.node.isNil:
    let nextKey = nextButton.attrib("data-key")
    if nextKey.len > 0:
      return REVIEWS_URL & "/_ajax?paginationKey=" & nextKey
  return ""

# ============================================================================
# MOCK DATA - Для демонстрации без реальных запросов
# ============================================================================

proc createMockResponse(pageNum: int): Response =
  ## Создаёт mock Response с примером HTML структуры IMDB
  let mockHtml = """
  <html>
  <body>
    <div class="review-container" data-review-id="rw123456""" & $pageNum & """">
      <div class="review-header">
        <a class="title" href="/review/rw123456""" & $pageNum & """">
          Best action movie of 2003!
        </a>
        <span class="rating-other-user-rating">
          <span>9</span>/10
        </span>
      </div>
      <div class="content">
        <div class="text show-more__control">
          This movie is absolutely fantastic! Arnold Schwarzenegger returns as the T-800 in an epic battle. 
          The action sequences are intense and well-choreographed. The plot keeps you on the edge of your seat. 
          Highly recommended for Terminator fans!
        </div>
        <div class="review-author">
          <span itemprop="author">
            <a class="display-name-link" href="/user/ur12345""" & $pageNum & """">
              JohnDoe""" & $pageNum & """
            </a>
          </span>
        </div>
        <span class="review-date">15 January 2020</span>
        <div class="actions text-muted">
          542 out of 678 found this helpful
        </div>
      </div>
    </div>
    
    <div class="review-container" data-review-id="rw234567""" & $pageNum & """">
      <div class="review-header">
        <a class="title" href="/review/rw234567""" & $pageNum & """">
          Good but not great
        </a>
        <span class="rating-other-user-rating">
          <span>6</span>/10
        </span>
      </div>
      <div class="content">
        <div class="text show-more__control">
          The movie has great action scenes, but the plot is a bit predictable.
          Arnold is good, but I expected more character development.
        </div>
        <div class="spoiler-warning">Warning: Contains spoilers</div>
        <div class="review-author">
          <span itemprop="author">
            <a class="display-name-link" href="/user/ur67890""" & $pageNum & """">
              MovieCritic""" & $pageNum & """
            </a>
          </span>
        </div>
        <span class="review-date">22 March 2019</span>
        <div class="actions text-muted">
          123 out of 234 found this helpful
        </div>
      </div>
    </div>
    
    <div class="review-container" data-review-id="rw345678""" & $pageNum & """">
      <div class="review-header">
        <a class="title" href="/review/rw345678""" & $pageNum & """">
          Amazing sci-fi action!
        </a>
        <span class="rating-other-user-rating">
          <span>10</span>/10
        </span>
      </div>
      <div class="content">
        <div class="text show-more__control">
          Perfect movie from start to finish. The special effects are incredible, 
          the soundtrack is memorable, and the story is engaging. 
          This is how sci-fi action should be made!
        </div>
        <div class="review-author">
          <span itemprop="author">
            <a class="display-name-link" href="/user/ur11111""" & $pageNum & """">
              ActionFan""" & $pageNum & """
            </a>
          </span>
        </div>
        <span class="review-date">5 July 2018</span>
        <div class="actions text-muted">
          892 out of 945 found this helpful
        </div>
      </div>
    </div>
    
    """ & (if pageNum < MAX_PAGES: """<button class="load-more-trigger" data-key="page""" & $(pageNum + 1) & """"></button>""" else: "") & """
  </body>
  </html>
  """
  
  result = newResponse(
    url = REVIEWS_URL & (if pageNum > 1: "?page=" & $pageNum else: ""),
    status = 200,
    headers = newHttpHeaders(),
    body = mockHtml
  )

proc scrapeAllPages(scraper: IMDBReviewsScraper) {.async.} =
  ## Скрейпит все страницы с отзывами
  echo "╔════════════════════════════════════════════════════════════════════"
  echo "║ STARTING SCRAPING SESSION"
  echo "║ Movie: Terminator 3: Rise of the Machines (2003)"
  echo "║ URL: ", REVIEWS_URL
  echo "║ Max pages: ", MAX_PAGES
  echo "╚════════════════════════════════════════════════════════════════════"
  echo ""
  
  var currentPage = 1
  var currentUrl = REVIEWS_URL
  
  while currentPage <= MAX_PAGES:
    echo "╔════════════════════════════════════════════════════════════════════"
    echo "║ PAGE ", currentPage, " / ", MAX_PAGES
    echo "╚════════════════════════════════════════════════════════════════════"
    
    # Middleware: processRequest
    var request = currentUrl
    var dummyResponse: Response
    scraper.loggingMiddleware.processRequest(request, dummyResponse)
    scraper.userAgentMiddleware.processRequest(request, dummyResponse)
    
    # В реальном приложении здесь был бы fetchAsync
    # let response = await fetchAsync(currentUrl)
    
    # Для демонстрации используем mock данные
    let response = createMockResponse(currentPage)
    
    scraper.stats.requestsCount += 1
    
    # Middleware: processResponse
    scraper.loggingMiddleware.processResponse(request, response)
    
    # Извлечение отзывов
    let reviews = scraper.scrapePage(response)
    scraper.allReviews.add reviews
    
    # Получение URL следующей страницы
    currentUrl = getNextPageUrl(response)
    
    if currentUrl.len == 0 or currentPage >= MAX_PAGES:
      break
    
    currentPage += 1
    
    # Задержка между запросами
    if currentPage <= MAX_PAGES:
      echo "⏳ Waiting ", REQUEST_DELAY, "ms before next page..."
      await sleepAsync(REQUEST_DELAY)
  
  scraper.stats.finish()

# ============================================================================
# EXPORT AND REPORTING
# ============================================================================

proc exportResults(scraper: IMDBReviewsScraper) =
  ## Экспортирует результаты в различные форматы
  echo ""
  echo "╔════════════════════════════════════════════════════════════════════"
  echo "║ EXPORTING RESULTS"
  echo "╚════════════════════════════════════════════════════════════════════"
  
  # JSON
  echo "  → Exporting to JSON..."
  let jsonData = %scraper.allReviews
  writeFile("imdb_reviews.json", $jsonData.pretty())
  echo "  ✓ Saved: imdb_reviews.json"
  
  # JSON Lines
  echo "  → Exporting to JSON Lines..."
  let jsonLines = scraper.allReviews.toJsonLines()
  writeFile("imdb_reviews.jsonl", jsonLines)
  echo "  ✓ Saved: imdb_reviews.jsonl"
  
  # CSV
  echo "  → Exporting to CSV..."
  let headers = @[
    "review_id", "title", "rating", "review_text",
    "author", "review_date", "helpful_count",
    "sentiment", "word_count", "scraped_at"
  ]
  let csvData = scraper.allReviews.toCsv(headers)
  writeFile("imdb_reviews.csv", csvData)
  echo "  ✓ Saved: imdb_reviews.csv"

proc printStatistics(scraper: IMDBReviewsScraper) =
  ## Выводит статистику скрейпинга
  echo ""
  echo "╔════════════════════════════════════════════════════════════════════"
  echo "║ SCRAPING STATISTICS"
  echo "╚════════════════════════════════════════════════════════════════════"
  echo ""
  echo "  📊 Total requests:      ", scraper.stats.requestsCount
  echo "  📝 Reviews scraped:     ", scraper.stats.itemsScraped
  echo "  ⏱️  Duration:            ", scraper.stats.duration()
  echo "  🎯 Success rate:        ", 
    if scraper.stats.requestsCount > 0:
      formatFloat(
        scraper.stats.itemsScraped.float / scraper.stats.requestsCount.float * 100,
        ffDecimal, 2
      ) & "%"
    else: "N/A"
  echo ""
  
  # Анализ по рейтингам
  var ratingCounts = initTable[string, int]()
  var sentimentCounts = initTable[string, int]()
  var totalWordCount = 0
  
  for review in scraper.allReviews:
    # Подсчёт рейтингов
    if review.hasKey("rating"):
      let rating = $(review["rating"])
      if rating.len > 0:
        ratingCounts[rating] = ratingCounts.getOrDefault(rating, 0) + 1
    
    # Подсчёт тональности
    if review.hasKey("sentiment"):
      let sentiment = $(review["sentiment"])
      sentimentCounts[sentiment] = sentimentCounts.getOrDefault(sentiment, 0) + 1
    
    # Подсчёт слов
    if review.hasKey("word_count"):
      let wc = $(review["word_count"])
      try:
        totalWordCount += parseInt(wc)
      except:
        discard
  
  echo "  📈 RATINGS DISTRIBUTION:"
  for rating in ["10", "9", "8", "7", "6", "5", "4", "3", "2", "1"]:
    if ratingCounts.hasKey(rating):
      let count = ratingCounts[rating]
      let bar = "█".repeat(count)
      echo "     ", rating, "/10: ", bar, " (", count, ")"
  
  echo ""
  echo "  😊 SENTIMENT ANALYSIS:"
  for sentiment in ["positive", "neutral", "negative", "unknown"]:
    if sentimentCounts.hasKey(sentiment):
      let count = sentimentCounts[sentiment]
      echo "     ", sentiment.capitalizeAscii(), ": ", count
  
  echo ""
  echo "  ✍️  AVERAGE REVIEW LENGTH: ", 
    if scraper.allReviews.len > 0:
      $(totalWordCount div scraper.allReviews.len) & " words"
    else: "N/A"
  echo ""

proc printSampleReviews(scraper: IMDBReviewsScraper, count: int = 2) =
  ## Выводит примеры извлечённых отзывов
  echo "╔════════════════════════════════════════════════════════════════════"
  echo "║ SAMPLE REVIEWS"
  echo "╚════════════════════════════════════════════════════════════════════"
  echo ""
  
  let samplesToShow = min(count, scraper.allReviews.len)
  
  for i in 0..<samplesToShow:
    let review = scraper.allReviews[i]
    
    echo "  ┌─ Review #", i + 1, " ", "─".repeat(60)
    
    if review.hasKey("title"):
      echo "  │ 📌 Title: ", $(review["title"])
    
    if review.hasKey("rating"):
      echo "  │ ⭐ Rating: ", $(review["rating"]), "/10"
    
    if review.hasKey("author"):
      echo "  │ 👤 Author: ", $(review["author"])
    
    if review.hasKey("review_date"):
      echo "  │ 📅 Date: ", $(review["review_date"])
    
    if review.hasKey("sentiment"):
      echo "  │ 😊 Sentiment: ", $(review["sentiment"])
    
    if review.hasKey("word_count"):
      echo "  │ ✍️  Words: ", $(review["word_count"])
    
    if review.hasKey("review_text"):
      var text = $(review["review_text"])
      if text.len > 200:
        text = text[0..200] & "..."
      echo "  │"
      echo "  │ 📝 Review:"
      for line in text.split("\n"):
        if line.strip().len > 0:
          echo "  │    ", line
    
    echo "  └─", "─".repeat(70)
    echo ""

# ============================================================================
# MAIN - Точка входа
# ============================================================================

proc main() {.async.} =
  echo """
  ╔════════════════════════════════════════════════════════════════════════╗
  ║                                                                        ║
  ║              IMDB REVIEWS SCRAPER - NimBrowser Demo                    ║
  ║                                                                        ║
  ║  Демонстрация возможностей библиотеки NimBrowser v1.0                 ║
  ║                                                                        ║
  ╚════════════════════════════════════════════════════════════════════════╝
  """
  echo ""
  
  # Инициализация скрейпера
  let scraper = newIMDBReviewsScraper()
  
  # Включение кэша селекторов
  enableQueryCache()
  echo "✓ Query cache enabled"
  echo ""
  
  # Запуск скрейпинга
  await scraper.scrapeAllPages()
  
  # Экспорт результатов
  scraper.exportResults()
  
  # Вывод статистики
  scraper.printStatistics()
  
  # Вывод примеров
  scraper.printSampleReviews(2)
  
  echo "╔════════════════════════════════════════════════════════════════════"
  echo "║ SCRAPING COMPLETED SUCCESSFULLY! 🎉"
  echo "╚════════════════════════════════════════════════════════════════════"
  echo ""
  echo "Files created:"
  echo "  • imdb_reviews.json  - Полный JSON массив"
  echo "  • imdb_reviews.jsonl - JSON Lines формат"
  echo "  • imdb_reviews.csv   - CSV файл"
  echo ""

# Запуск программы
when isMainModule:
  waitFor main()

## ============================================================================
## ИНСТРУКЦИИ ПО ЗАПУСКУ
## ============================================================================
##
## 1. Убедитесь, что у вас установлен Nim (версия 1.6.0 или выше)
##
## 2. Скомпилируйте программу:
##    nim c -d:release imdb_reviews_scraper.nim
##
## 3. Запустите:
##    ./imdb_reviews_scraper
##
## ПРИМЕЧАНИЕ: Этот пример использует mock данные для демонстрации.
## Для реального скрейпинга IMDB:
##   - Раскомментируйте строку с fetchAsync()
##   - Убедитесь, что соблюдаете robots.txt
##   - Используйте разумные задержки между запросами
##   - Добавьте обработку ошибок и повторные попытки
##
## ============================================================================
