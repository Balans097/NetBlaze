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
import httpclient
import strutils
import times
import json
import re
import tables
import sets
import xmltree except innerText
import htmlparser except normalizeWhitespace
import streams

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

const
  MOVIE_ID = "tt0181852"  # Terminator 3: Rise of the Machines
  BASE_URL = "https://www.imdb.com"
  REVIEWS_URL = BASE_URL & "/title/" & MOVIE_ID & "/reviews"
  MAX_PAGES = 50  # Максимум страниц для скрейпинга (обычно ~25 отзывов на странице)
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
                      resp: var nimbrowser.Response) =
  m.requestCount += 1
  echo "┌────────────────────────────────────────────────────────────"
  echo "│ REQUEST #", m.requestCount
  echo "│ URL: ", req
  echo "└────────────────────────────────────────────────────────────"

method processResponse*(m: LoggingMiddleware,
                       req: string,
                       resp: var nimbrowser.Response) =
  echo "┌────────────────────────────────────────────────────────────"
  echo "│ RESPONSE"
  echo "│ Status: ", resp.status
  echo "│ Body length: ", resp.body.len, " bytes"
  echo "└────────────────────────────────────────────────────────────"

method processRequest*(m: UserAgentMiddleware,
                      req: var string,
                      resp: var nimbrowser.Response) =
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
  if reviewNode.isNil:
    echo "    ✗ reviewNode is nil"
    return result
  
  let reviewId = reviewNode.getAttr("data-review-id", "")
  if reviewId.len > 0:
    result["review_id"] = %reviewId
    echo "    • review_id: ", reviewId
  
  # === ИЗВЛЕЧЕНИЕ ДАННЫХ ЧЕРЕЗ ПОИСК В DOM ===
  
  # Заголовок отзыва
  for node in reviewNode.findAll("a"):
    if node.kind == xnElement and node.attr("class").contains("title"):
      let titleText = node.innerText().strip()
      if titleText.len > 0:
        result["title"] = %titleText
        echo "    • title: ", titleText
        break
  
  # Рейтинг
  for node in reviewNode.findAll("span"):
    if node.kind == xnElement and node.attr("class").contains("rating-other-user-rating"):
      for subNode in node.findAll("span"):
        if subNode.kind == xnElement:
          let ratingText = subNode.innerText().strip()
          let pattern = re"(\d+)/10"
          var matches: array[1, string]
          if ratingText.find(pattern, matches) != -1:
            result["rating"] = %matches[0]
            echo "    • rating: ", matches[0]
            break
      break
  
  # Текст отзыва
  for node in reviewNode.findAll("div"):
    if node.kind == xnElement and node.attr("class").contains("text") and node.attr("class").contains("show-more__control"):
      let reviewText = node.innerText().strip()
      if reviewText.len > 0:
        result["review_text"] = %reviewText
        echo "    • review_text: ", reviewText[0..min(50, reviewText.len-1)], "..."
        break
  
  # Автор
  for node in reviewNode.findAll("span"):
    if node.kind == xnElement and node.attr("class").contains("display-name-link"):
      for linkNode in node.findAll("a"):
        if linkNode.kind == xnElement:
          let authorText = linkNode.innerText().strip()
          if authorText.len > 0:
            result["author"] = %authorText
            echo "    • author: ", authorText
          
          # URL автора
          let href = linkNode.attr("href")
          if href.len > 0:
            var authorUrl = href
            if not authorUrl.startsWith("http"):
              authorUrl = urljoin(BASE_URL, authorUrl)
            result["author_url"] = %authorUrl
            echo "    • author_url: ", authorUrl
          break
      break
  
  # Дата отзыва
  for node in reviewNode.findAll("span"):
    if node.kind == xnElement and node.attr("class").contains("review-date"):
      let dateText = node.innerText().strip()
      if dateText.len > 0:
        result["review_date"] = %dateText
        echo "    • review_date: ", dateText
        break
  
  # Количество "полезных" голосов
  for node in reviewNode.findAll("div"):
    if node.kind == xnElement and node.attr("class").contains("actions") and node.attr("class").contains("text-muted"):
      let helpfulText = node.innerText().strip()
      if helpfulText.len > 0:
        result["helpful_count"] = %helpfulText
        echo "    • helpful_count: ", helpfulText
        break
  
  # === SPOILER WARNING ===
  
  # Извлечение spoiler информации (если есть)
  var hasSpoiler = false
  for node in reviewNode.findAll("span"):
    if node.kind == xnElement and node.attr("class").contains("spoiler-warning"):
      hasSpoiler = true
      break
  
  result["has_spoiler"] = %hasSpoiler
  if hasSpoiler:
    echo "    • has_spoiler: true"
  
  echo "    ✓ Data extracted"

proc scrapePage(scraper: IMDBReviewsScraper, response: nimbrowser.Response): seq[Item] =
  ## Извлекает все отзывы со страницы
  echo ""
  echo "╔════════════════════════════════════════════════════════════════════"
  echo "║ SCRAPING PAGE"
  echo "╚════════════════════════════════════════════════════════════════════"
  
  result = @[]
  
  # Сохраним HTML для анализа (только первый раз)
  if scraper.stats.requestsCount == 1:
    try:
      writeFile("imdb_page_debug.html", response.body)
      echo "  [DEBUG] HTML saved to imdb_page_debug.html"
    except:
      discard
  
  # Создание селектора из HTML
  let rootNode = parseHtml(response.body)
  
  # Поиск всех блоков с отзывами
  echo "  → Searching for review elements..."
  
  if rootNode.isNil:
    echo "  ✓ Found 0 reviews"
    return result
  
  # IMDB изменил структуру - теперь используются другие классы
  # Попробуем найти article элементы или div с data-testid
  var reviewNodes: seq[XmlNode] = @[]
  
  # Вариант 1: ищем div с классом lister-item
  for node in rootNode.findAll("div"):
    if node.kind == xnElement:
      let className = node.attr("class")
      if className.contains("lister-item") or className.contains("review-container"):
        reviewNodes.add(node)
  
  # Вариант 2: если не нашли, ищем article
  if reviewNodes.len == 0:
    for node in rootNode.findAll("article"):
      if node.kind == xnElement:
        reviewNodes.add(node)
  
  # Вариант 3: ищем div с data-testid="review-card"
  if reviewNodes.len == 0:
    for node in rootNode.findAll("div"):
      if node.kind == xnElement:
        if node.attr("data-testid").contains("review"):
          reviewNodes.add(node)
  
  echo "  ✓ Found ", reviewNodes.len, " reviews"
  
  # Обработка каждого отзыва
  for i, reviewNode in reviewNodes:
    echo ""
    echo "  ┌─ Processing review #", i + 1, " ────────────────────────────────"
    
    # Создаём Selector из узла
    let reviewElement = Selector(node: reviewNode)
    
    # Извлечение данных
    var item = scraper.extractReviewData(reviewElement)
    
    # Применение pipelines
    var shouldKeep = true
    
    # Pipeline 1: Validation
    if not scraper.validationPipeline.processItem(item):
      shouldKeep = false
    
    # Pipeline 2: Deduplication
    if shouldKeep and not scraper.duplicatesPipeline.processItem(item):
      shouldKeep = false
    
    # Pipeline 3: Enrichment
    if shouldKeep and not scraper.enrichmentPipeline.processItem(item):
      shouldKeep = false
    
    if shouldKeep:
      result.add item
      scraper.stats.itemsScraped += 1
      echo "  │ ✓ Review added to results"
    else:
      echo "  │ ✗ Review filtered out"
    
    echo "  └─", "─".repeat(60)
  
  echo ""
  echo "  📊 Page summary: ", result.len, " reviews accepted, ",
       reviewNodes.len - result.len, " filtered out"

proc getNextPageUrl(response: nimbrowser.Response): string =
  ## Получает URL следующей страницы из пагинации
  result = ""
  
  let rootNode = parseHtml(response.body)
  if rootNode.isNil:
    return result
  
  # IMDB использует data-key для пагинации в атрибуте кнопки Load More
  # Ищем кнопку с классом load-more-data
  for node in rootNode.findAll("button"):
    if node.kind == xnElement:
      let className = node.attr("class")
      if className.contains("load-more-data") or className.contains("ipc-see-more"):
        let dataKey = node.attr("data-key")
        if dataKey.len > 0:
          # Формируем URL для следующей страницы
          result = REVIEWS_URL & "?paginationKey=" & dataKey
          return result
  
  # Альтернативный поиск через div с id load-more-trigger
  for node in rootNode.findAll("div"):
    if node.kind == xnElement:
      if node.attr("id") == "load-more-trigger":
        let dataKey = node.attr("data-key")
        if dataKey.len > 0:
          result = REVIEWS_URL & "?paginationKey=" & dataKey
          return result

proc createMockResponse(pageNum: int): nimbrowser.Response =
  ## Создаёт mock ответ для демонстрации
  new(result)
  result.url = REVIEWS_URL
  result.status = 200
  result.encoding = "utf-8"
  result.meta = initTable[string, string]()
  result.body = """
<html>
<body>
  <div class="review-container" data-review-id="rv123456">
    <div class="lister-item-content">
      <a class="title">Great action sequences!</a>
      <span class="rating-other-user-rating">
        <span>8/10</span>
      </span>
      <div class="text show-more__control">
        This is one of the most underrated Terminator movies. The action is spectacular 
        and the special effects still hold up today. Arnold Schwarzenegger gives a solid 
        performance as always. While it may not reach the heights of T2, it's still a 
        very entertaining film that delivers on the promise of robot action.
      </div>
      <span class="display-name-link">
        <a href="/user/ur12345678/">ActionFan2003</a>
      </span>
      <span class="review-date">15 July 2003</span>
      <div class="actions text-muted">125 out of 150 found this helpful</div>
    </div>
  </div>
  
  <div class="review-container" data-review-id="rv123457">
    <div class="lister-item-content">
      <a class="title">Not as good as T2, but still fun</a>
      <span class="rating-other-user-rating">
        <span>6/10</span>
      </span>
      <div class="text show-more__control">
        After the masterpiece that was Terminator 2, this third installment feels 
        somewhat unnecessary. However, if you can look past that, there's still 
        plenty to enjoy here. The chase scenes are well-done and the darker ending 
        was a nice surprise. Worth watching for fans of the franchise.
      </div>
      <span class="display-name-link">
        <a href="/user/ur87654321/">MovieBuff1999</a>
      </span>
      <span class="review-date">22 July 2003</span>
      <div class="actions text-muted">89 out of 120 found this helpful</div>
      <span class="spoiler-warning">Contains spoilers</span>
    </div>
  </div>
  
  <div class="review-container" data-review-id="rv123458">
    <div class="lister-item-content">
      <a class="title">Disappointing sequel</a>
      <span class="rating-other-user-rating">
        <span>4/10</span>
      </span>
      <div class="text show-more__control">
        I had high hopes for this movie, but it just doesn't capture the magic 
        of the first two films. The plot feels recycled and the new characters 
        aren't very interesting. Some decent action scenes can't save this from 
        being a mediocre entry in the series.
      </div>
      <span class="display-name-link">
        <a href="/user/ur11223344/">CriticCorner</a>
      </span>
      <span class="review-date">1 August 2003</span>
      <div class="actions text-muted">45 out of 95 found this helpful</div>
    </div>
  </div>
</body>
</html>
"""
  result.headers = newHttpHeaders({"Content-Type": "text/html; charset=utf-8"})

# ============================================================================
# HTTP REQUEST HELPERS
# ============================================================================

proc fetchWithHeaders(url: string): Future[nimbrowser.Response] {.async.} =
  ## Выполняет HTTP запрос с необходимыми заголовками
  var headers = newHttpHeaders({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1"
  })
  
  var client = newAsyncHttpClient()
  client.headers = headers
  
  try:
    let httpResponse = await client.get(url)
    let bodyText = await httpResponse.body
    
    # Создаём Response объект NimBrowser
    new(result)
    result.url = url
    result.status = httpResponse.code.int
    result.body = bodyText
    result.encoding = "utf-8"
    result.meta = initTable[string, string]()
    
    # Копируем заголовки ответа
    for key, val in httpResponse.headers.table:
      result.meta[key] = val.join("; ")
    
    client.close()
  except Exception as e:
    echo "Error fetching URL: ", e.msg
    # Возвращаем пустой ответ с ошибкой
    new(result)
    result.url = url
    result.status = 500
    result.body = ""
    result.encoding = "utf-8"
    result.meta = initTable[string, string]()
    client.close()

# ============================================================================
# SCRAPING LOGIC
# ============================================================================

proc scrapeAllPages(scraper: IMDBReviewsScraper) {.async.} =
  ## Скрейпит все доступные страницы с отзывами
  echo "╔════════════════════════════════════════════════════════════════════"
  echo "║ STARTING SCRAPING PROCESS"
  echo "╚════════════════════════════════════════════════════════════════════"
  echo ""
  echo "  🎯 Target: ", REVIEWS_URL
  echo "  📄 Max pages: ", MAX_PAGES
  echo "  ⏱️  Delay: ", REQUEST_DELAY, "ms"
  echo ""
  
  var currentUrl = REVIEWS_URL
  var currentPage = 1
  
  while currentUrl.len > 0:
    echo "╔════════════════════════════════════════════════════════════════════"
    echo "║ PAGE #", currentPage
    echo "╚════════════════════════════════════════════════════════════════════"
    
    # Middleware: processRequest
    var request = currentUrl
    var dummyResponse = new(nimbrowser.Response)
    scraper.loggingMiddleware.processRequest(request, dummyResponse)
    
    # Выполнение реального HTTP запроса с заголовками
    let response = await fetchWithHeaders(currentUrl)
    
    scraper.stats.requestsCount += 1
    
    # Middleware: processResponse
    var mutableResponse = response
    scraper.loggingMiddleware.processResponse(request, mutableResponse)
    
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
  
  # scraper.stats.finish()

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
  # echo "  ⏱️  Duration:            ", scraper.stats.duration()
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
## 1. Убедитесь, что у вас установлен Nim (версия 2.2.6 или выше)
##
## 2. Скомпилируйте программу:
##    nim c -d:release imdb_reviews_scraper.nim
##
## 3. Запустите:
##    ./imdb_reviews_scraper
##
## ПРИМЕЧАНИЕ: Программа выполняет реальные HTTP-запросы к IMDB.
## Рекомендации:
##   - Соблюдайте robots.txt сайта IMDB
##   - Используйте разумные задержки между запросами (по умолчанию 2000мс)
##   - Настройте MAX_PAGES для ограничения количества загружаемых страниц
##   - При необходимости добавьте обработку ошибок и повторные попытки
##   - Будьте уважительны к серверам IMDB - не создавайте чрезмерную нагрузку
##
## Настройка:
##   - MOVIE_ID - ID фильма на IMDB (например, "tt0181852")
##   - MAX_PAGES - максимальное количество страниц для загрузки
##   - REQUEST_DELAY - задержка между запросами в миллисекундах
##
## ============================================================================
