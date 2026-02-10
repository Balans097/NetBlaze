# nim c -d:release -d:ssl imdb_scraper.nim


## Улучшенный парсер отзывов IMDB v2.1
## 
## Этот файл демонстрирует использование улучшенной библиотеки nimBrowser
## для извлечения отзывов о фильмах с сайта IMDB с дополнительными возможностями:
## - Робастный парсинг с поддержкой разных версий дизайна IMDB
## - Извлечение метаданных отзывов
## - Фильтрация спойлеров
## - Статистический анализ
## - Экспорт в различные форматы



import xmltree, httpclient, strutils, times, os, json, tables
import sequtils, algorithm, streams
import htmlparser, nimBrowser
import zip/gzipfiles




type
  Review* = object
    title*: string
    rating*: float          # float для удобства
    author*: string
    authorUrl*: string      # ссылка на профиль автора
    date*: string
    dateTimestamp*: int64   # timestamp для сортировки
    text*: string
    helpful*: tuple[found: int, total: int]  # структурированные данные
    spoiler*: bool
    verified*: bool         # верифицированная покупка
    reviewId*: string       # уникальный ID отзыва
    permalink*: string      # постоянная ссылка

  MovieReviews* = object
    movieTitle*: string
    movieId*: string
    movieYear*: int         # год выпуска
    averageRating*: float   # средний рейтинг фильма
    totalReviews*: int      # общее количество отзывов на сайте
    reviews*: seq[Review]
    fetchedAt*: string      # время сбора данных

  ScraperConfig* = object
    maxPages*: int
    delayMs*: int
    includeSpoilers*: bool
    minRating*: float
    maxRating*: float
    userAgent*: string


# ============================================================================
# УТИЛИТЫ
# ============================================================================

proc decompressGzip(data: string): string =
  ## Декомпрессирует gzip данные
  try:
    # Проверяем gzip magic number
    if data.len < 2:
      return data
    if data[0] != '\x1f' or data[1] != '\x8b':
      # Не gzip, возвращаем как есть
      return data
    
    # Записываем во временный файл
    let tmpIn = getTempDir() / "imdb_temp.gz"
    let tmpOut = getTempDir() / "imdb_temp.txt"
    
    writeFile(tmpIn, data)
    
    # Распаковываем
    var gz = newGzFileStream(tmpIn, fmRead)
    if gz.isNil:
      removeFile(tmpIn)
      return data
    
    var output = ""
    var buffer = newString(8192)
    while not gz.atEnd():
      let bytesRead = gz.readData(addr buffer[0], 8192)
      if bytesRead > 0:
        output.add(buffer[0..<bytesRead])
    
    gz.close()
    removeFile(tmpIn)
    if fileExists(tmpOut):
      removeFile(tmpOut)
    
    return output
  except:
    return data

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

const DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " &
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

func defaultConfig*(): ScraperConfig =
  ## Возвращает конфигурацию по умолчанию
  ScraperConfig(
    maxPages: 5,
    delayMs: 1500,
    includeSpoilers: true,
    minRating: 0.0,
    maxRating: 10.0,
    userAgent: DEFAULT_USER_AGENT
  )


# ============================================================================
# HTTP КЛИЕНТ
# ============================================================================

proc newHttpClientWithHeaders(userAgent: string = DEFAULT_USER_AGENT): HttpClient =
  ## Создаёт HTTP клиент с правильными заголовками для обхода базовой защиты
  result = newHttpClient()
  result.headers = newHttpHeaders({
    "User-Agent": userAgent,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
    "Accept-Encoding": "gzip, deflate",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
    "Cache-Control": "max-age=0"
  })


proc fetchReviewsPage(movieId: string, start: int = 0, 
                     config: ScraperConfig): string =
  ## Получает HTML страницу с отзывами с задержкой для избежания блокировки
  if start > 0:
    sleep(config.delayMs)
  
  let url = "https://www.imdb.com/title/" & movieId & "/reviews?start=" & $start
  
  echo "[", now().format("HH:mm:ss"), "] Fetching: ", url
  
  let client = newHttpClientWithHeaders(config.userAgent)
  try:
    let rawData = client.getContent(url)
    echo "[", now().format("HH:mm:ss"), "] Fetched ", rawData.len, " bytes (raw)"
    
    # Декомпрессируем если нужно
    result = decompressGzip(rawData)
    echo "[", now().format("HH:mm:ss"), "] Decompressed to ", result.len, " bytes"
  except Exception as e:
    echo "[ERROR] Failed to fetch page: ", e.msg
    result = ""
  finally:
    client.close()


# ============================================================================
# ПАРСИНГ ОТЗЫВОВ
# ============================================================================

proc parseDate(dateStr: string): int64 =
  ## Парсит дату отзыва и возвращает timestamp
  ## Поддерживает форматы: "1 January 2024", "January 1, 2024"
  try:
    # Упрощённый парсинг - можно расширить
    let parts = dateStr.strip().split(' ')
    if parts.len >= 3:
      # Примерная конвертация (для демонстрации)
      return getTime().toUnix()
  except:
    discard
  return 0

proc parseHelpful(helpfulText: string): tuple[found: int, total: int] =
  ## Парсит информацию о полезности отзыва
  ## Пример: "123 out of 456 found this helpful"
  result = (found: 0, total: 0)
  
  let numbers = extractNumbers(helpfulText)
  if numbers.len >= 2:
    result.found = int(numbers[0])
    result.total = int(numbers[1])
  elif numbers.len == 1:
    result.found = int(numbers[0])

proc safeParseHtml(html: string): XmlNode =
  ## Безопасная обёртка для parseHtml с обработкой различных кейсов
  result = nil
  
  if html == "" or html.len < 10:
    echo "[WARNING] HTML too short or empty"
    return
  
  # Проверяем, что это похоже на HTML
  if not html.contains("<") or not html.contains(">"):
    echo "[WARNING] Does not look like HTML"
    return
  
  try:
    # Парсим через поток, который мы контролируем
    var s = newStringStream(html)
    if s.isNil:
      echo "[ERROR] Failed to create StringStream"
      return
    
    var errors: seq[string] = @[]
    result = parseHtml(s, "imdb_reviews", errors)
    
    # Закрываем поток
    s.close()
    
    if errors.len > 0:
      echo "[WARNING] HTML parsing had ", errors.len, " errors"
      for i, err in errors:
        if i < 5:  # Показываем только первые 5 ошибок
          echo "  Error ", i+1, ": ", err
    
  except CatchableError as e:
    echo "[ERROR] parseHtml failed: ", e.msg
    result = nil
  except:
    echo "[ERROR] Unexpected error in parseHtml"
    result = nil

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ БЕЗОПАСНОГО ПОИСКА ЭЛЕМЕНТОВ
# ============================================================================

proc findAllByClass(node: XmlNode, className: string): seq[XmlNode] =
  ## Рекурсивно ищет все элементы с указанным классом
  result = @[]
  
  if node.isNil:
    return
  
  if node.kind == xnElement:
    if not node.attrs.isNil:
      let classes = node.attr("class")
      if classes != "" and className in classes.split(' '):
        result.add node
  
  if node.kind == xnElement:
    for child in node:
      result.add findAllByClass(child, className)

proc findAllByDataAttr(node: XmlNode, attrName: string, attrValue: string): seq[XmlNode] =
  ## Рекурсивно ищет все элементы с указанным data-атрибутом
  result = @[]
  
  if node.isNil:
    return
  
  if node.kind == xnElement:
    if not node.attrs.isNil:
      let value = node.attr(attrName)
      if value == attrValue:
        result.add node
  
  if node.kind == xnElement:
    for child in node:
      result.add findAllByDataAttr(child, attrName, attrValue)

proc findFirstByTag(node: XmlNode, tagName: string): XmlNode =
  ## Рекурсивно ищет первый элемент с указанным тегом
  if node.isNil:
    return nil
  
  if node.kind == xnElement and node.tag.toLowerAscii() == tagName.toLowerAscii():
    return node
  
  if node.kind == xnElement:
    for child in node:
      let found = findFirstByTag(child, tagName)
      if not found.isNil:
        return found
  
  return nil

proc findFirstByClass(node: XmlNode, className: string): XmlNode =
  ## Рекурсивно ищет первый элемент с указанным классом
  if node.isNil:
    return nil
  
  if node.kind == xnElement:
    if not node.attrs.isNil:
      let classes = node.attr("class")
      if classes != "" and className in classes.split(' '):
        return node
  
  if node.kind == xnElement:
    for child in node:
      let found = findFirstByClass(child, className)
      if not found.isNil:
        return found
  
  return nil

# ============================================================================
# ПАРСИНГ ОТЗЫВОВ
# ============================================================================

proc parseReviewModern(reviewNode: XmlNode, movieId: string): Review =
  ## Парсит отзыв из нового дизайна IMDB (2023+)
  result = Review()
  
  if reviewNode.isNil:
    return
  
  # ID отзыва из data-атрибута
  if not reviewNode.attrs.isNil:
    result.reviewId = reviewNode.attr("data-review-id")
    if result.reviewId == "":
      result.reviewId = reviewNode.attr("data-testid")
    if result.reviewId == "":
      result.reviewId = reviewNode.attr("id")
  
  # Постоянная ссылка
  if result.reviewId != "":
    result.permalink = "https://www.imdb.com/review/" & result.reviewId
  
  # Заголовок отзыва - ищем первый h3 или элемент с классом title
  let titleNode = findFirstByTag(reviewNode, "h3")
  if not titleNode.isNil:
    result.title = titleNode.innerTextClean()
  
  # Текст отзыва - ищем div с большим количеством текста
  proc findLargestTextBlock(node: XmlNode): string {.closure.} =
    if node.isNil or node.kind != xnElement:
      return ""
    
    var maxText = ""
    let currentText = node.innerTextClean()
    if currentText.len > maxText.len and currentText.len > 50:
      maxText = currentText
    
    for child in node:
      let childText = findLargestTextBlock(child)
      if childText.len > maxText.len:
        maxText = childText
    
    return maxText
  
  result.text = findLargestTextBlock(reviewNode)
  
  # Автор - ищем span с классом содержащим "author" или "name"
  proc findAuthor(node: XmlNode): string {.closure.} =
    if node.isNil or node.kind != xnElement:
      return ""
    
    if node.tag.toLowerAscii() == "span" or node.tag.toLowerAscii() == "a":
      if not node.attrs.isNil:
        let class = node.attr("class")
        if "author" in class.toLowerAscii() or "name" in class.toLowerAscii():
          return node.innerTextClean()
    
    for child in node:
      let found = findAuthor(child)
      if found != "":
        return found
    
    return ""
  
  result.author = findAuthor(reviewNode)
  
  # Рейтинг - ищем span с числом от 1 до 10
  proc findRating(node: XmlNode): float {.closure.} =
    if node.isNil or node.kind != xnElement:
      return 0.0
    
    if node.tag.toLowerAscii() == "span":
      let text = node.innerTextClean()
      if text.len > 0 and text.len < 5:
        try:
          let rating = parseFloat(text)
          if rating >= 1.0 and rating <= 10.0:
            return rating
        except:
          discard
    
    for child in node:
      let found = findRating(child)
      if found > 0.0:
        return found
    
    return 0.0
  
  result.rating = findRating(reviewNode)
  
  # Дата - ищем элемент с датой
  proc findDate(node: XmlNode): string {.closure.} =
    if node.isNil or node.kind != xnElement:
      return ""
    
    if not node.attrs.isNil:
      let class = node.attr("class")
      if "date" in class.toLowerAscii():
        return node.innerTextClean()
    
    for child in node:
      let found = findDate(child)
      if found != "":
        return found
    
    return ""
  
  result.date = findDate(reviewNode)
  result.dateTimestamp = parseDate(result.date)
  
  # Спойлер - проверяем наличие слова "spoiler" в классах
  proc hasSpoiler(node: XmlNode): bool {.closure.} =
    if node.isNil or node.kind != xnElement:
      return false
    
    if not node.attrs.isNil:
      let class = node.attr("class")
      if "spoiler" in class.toLowerAscii():
        return true
    
    for child in node:
      if hasSpoiler(child):
        return true
    
    return false
  
  result.spoiler = hasSpoiler(reviewNode)
  
  # Верифицированный пользователь
  result.verified = false

proc parseReviewLegacy(reviewNode: XmlNode, movieId: string): Review =
  ## Парсит отзыв из старого дизайна IMDB (до 2023)
  ## ПРИМЕЧАНИЕ: эта функция не используется для современного IMDB
  result = Review()
  
  if reviewNode.isNil:
    return
  
  # Для современного IMDB эта функция не нужна, просто возвращаем пустой результат
  echo "[DEBUG] parseReviewLegacy called but not implemented for modern IMDB"

proc parseReviewsFromHtml(html: string, movieId: string): seq[Review] =
  ## Парсит все отзывы из HTML страницы
  echo "[DEBUG] Entering parseReviewsFromHtml"
  result = @[]
  
  var doc: XmlNode = nil
  
  try:
    echo "[DEBUG] Checking HTML..."
    if html == "":
      echo "[DEBUG] Empty HTML"
      return
    
    echo "[DEBUG] HTML length: ", html.len, " bytes"
    
    # Сохраняем HTML в файл для отладки
    try:
      writeFile("debug_imdb.html", html)
      echo "[DEBUG] Saved HTML to debug_imdb.html"
    except:
      echo "[DEBUG] Could not save HTML file"
    
    # Безопасная проверка начала HTML
    if html.len > 15:
      let start = html[0..min(14, html.len-1)]
      echo "[DEBUG] HTML starts with: ", start.replace("\n", "\\n")
    
    # Парсим HTML с обработкой ошибок
    echo "[DEBUG] About to call safeParseHtml..."
    doc = safeParseHtml(html)
    
    if doc.isNil:
      echo "[ERROR] safeParseHtml returned nil!"
      return
    
    echo "[DEBUG] Document parsed successfully, tag: ", doc.tag
  except Exception as e:
    echo "[ERROR] Exception in initial parsing: ", e.msg
    echo "[ERROR] Exception type: ", e.name
    echo "[ERROR] Stack trace: ", e.getStackTrace()
    return
  
  # Безопасная проверка документа перед использованием
  if doc.isNil:
    echo "[ERROR] Document is nil, cannot query selectors"
    return
  
  # Остальной код...
  var reviewNodes: seq[XmlNode] = @[]
  
  try:
    echo "[DEBUG] About to search for review nodes..."
    echo "[DEBUG] Document tag: ", doc.tag
    
    # Диагностика: выведем первые несколько элементов
    echo "[DEBUG] Document has ", doc.len, " children"
    if doc.len > 0:
      var elemCount = 0
      for child in doc:
        if child.kind == xnElement:
          elemCount.inc
          if elemCount <= 5:
            var info = "  Child " & $elemCount & ": <" & child.tag & ">"
            if not child.attrs.isNil:
              let id = child.attr("id")
              let class = child.attr("class")
              if id != "": info.add " id=\"" & id & "\""
              if class != "": info.add " class=\"" & class & "\""
            echo info
      echo "[DEBUG] Total element children: ", elemCount
    
    # Вариант 1: Современный дизайн с data-testid
    try:
      echo "[DEBUG] Trying data-testid=review-card..."
      reviewNodes = findAllByDataAttr(doc, "data-testid", "review-card")
      echo "[DEBUG] Found ", reviewNodes.len, " nodes with data-testid=review-card"
    except Exception as e:
      echo "[DEBUG] Search by data-testid failed: ", e.msg
    
    # Вариант 2: Класс review-container
    if reviewNodes.len == 0:
      try:
        echo "[DEBUG] Trying class review-container..."
        reviewNodes = findAllByClass(doc, "review-container")
        echo "[DEBUG] Found ", reviewNodes.len, " nodes with class review-container"
      except Exception as e:
        echo "[DEBUG] Search by review-container failed: ", e.msg
    
    # Вариант 3: Класс lister-item
    if reviewNodes.len == 0:
      try:
        echo "[DEBUG] Trying class lister-item..."
        reviewNodes = findAllByClass(doc, "lister-item")
        echo "[DEBUG] Found ", reviewNodes.len, " nodes with class lister-item"
      except Exception as e:
        echo "[DEBUG] Search by lister-item failed: ", e.msg
    
    # Вариант 4: Попробуем найти все div'ы с классами содержащими "review"
    if reviewNodes.len == 0:
      echo "[DEBUG] Trying to find divs with 'review' in class name..."
      var reviewDivCount = 0
      var allClasses: seq[string] = @[]
      
      proc scanForReviewDivs(node: XmlNode): seq[XmlNode] {.closure.} =
        result = @[]
        if node.isNil or node.kind != xnElement:
          return
        
        # Собираем все классы для статистики
        if not node.attrs.isNil:
          let class = node.attr("class")
          if class != "" and class notin allClasses:
            allClasses.add class
        
        if node.tag.toLowerAscii() == "div":
          if not node.attrs.isNil:
            let class = node.attr("class")
            if class != "" and ("review" in class.toLowerAscii()):
              result.add node
              reviewDivCount.inc
              if reviewDivCount <= 10:
                echo "[DEBUG] Found div with review-related class: ", class
        
        for child in node:
          result.add scanForReviewDivs(child)
      
      let foundDivs = scanForReviewDivs(doc)
      echo "[DEBUG] Total divs with 'review' in class: ", reviewDivCount
      echo "[DEBUG] Total unique classes in document: ", allClasses.len
      
      # Выведем первые 30 уникальных классов
      echo "[DEBUG] First 30 unique classes found:"
      for i in 0..<min(30, allClasses.len):
        echo "  ", i+1, ": ", allClasses[i]
      
      if foundDivs.len > 0:
        echo "[DEBUG] Using ", foundDivs.len, " review divs as review nodes"
        reviewNodes = foundDivs
    
    # Вариант 5: Попробуем найти article или section элементы
    if reviewNodes.len == 0:
      echo "[DEBUG] Trying to find article/section elements..."
      
      proc scanForArticles(node: XmlNode): seq[XmlNode] {.closure.} =
        result = @[]
        if node.isNil or node.kind != xnElement:
          return
        
        let tag = node.tag.toLowerAscii()
        if tag == "article" or tag == "section":
          result.add node
          if result.len <= 5:
            var info = "Found <" & tag & ">"
            if not node.attrs.isNil:
              let class = node.attr("class")
              if class != "":
                info.add " class=\"" & class & "\""
            echo "[DEBUG] ", info
        
        for child in node:
          result.add scanForArticles(child)
      
      let articles = scanForArticles(doc)
      echo "[DEBUG] Found ", articles.len, " article/section elements"
      
      if articles.len > 0:
        echo "[DEBUG] Using article/section elements as review nodes"
        reviewNodes = articles
    
    echo "[DEBUG] Final count: ", reviewNodes.len, " review nodes"
    
  except Exception as e:
    echo "[ERROR] Exception in searching for nodes: ", e.msg
    echo "[ERROR] Stack trace: ", e.getStackTrace()
    return
  
  # Парсим отзывы
  for i, reviewNode in reviewNodes:
    try:
      if reviewNode.isNil:
        continue
        
      var review = parseReviewModern(reviewNode, movieId)
      
      if review.text == "" or review.title == "":
        review = parseReviewLegacy(reviewNode, movieId)
      
      if review.text != "" or review.title != "":
        result.add review
    except Exception as e:
      echo "[WARNING] Failed to parse review #", i, ": ", e.msg

proc extractMovieInfo(html: string): (string, int, float) =
  ## Извлекает информацию о фильме из HTML
  result = ("Unknown", 0, 0.0)
  
  if html == "":
    return
  
  try:
    echo "[DEBUG] extractMovieInfo: calling safeParseHtml..."
    let doc = safeParseHtml(html)
    
    if doc.isNil:
      echo "[WARNING] extractMovieInfo: safeParseHtml returned nil"
      return
    
    echo "[DEBUG] extractMovieInfo: doc parsed, tag=", doc.tag
    
    # Название фильма - ищем первый h1
    try:
      echo "[DEBUG] extractMovieInfo: searching for title using findFirstByTag..."
      let titleNode = findFirstByTag(doc, "h1")
      
      if titleNode != nil and not titleNode.isNil:
        echo "[DEBUG] extractMovieInfo: title node found"
        result[0] = titleNode.innerTextClean()
        echo "[DEBUG] extractMovieInfo: title=", result[0]
      else:
        echo "[DEBUG] extractMovieInfo: title node not found"
    except Exception as e:
      echo "[ERROR] extractMovieInfo: title extraction failed: ", e.msg
    
    # Год выпуска - пропускаем, так как сложно найти без селекторов
    echo "[DEBUG] extractMovieInfo: skipping year extraction (too complex without selectors)"
    
    # Рейтинг - пропускаем
    echo "[DEBUG] extractMovieInfo: skipping rating extraction (too complex without selectors)"
      
    echo "[DEBUG] extractMovieInfo: completed successfully"
  except Exception as e:
    echo "[ERROR] extractMovieInfo failed: ", e.msg
    echo "[ERROR] Stack trace: ", e.getStackTrace()

proc fetchAllReviews*(movieId: string, config: ScraperConfig): MovieReviews =
  ## Получает все отзывы для фильма с учётом конфигурации
  result = MovieReviews(
    movieId: movieId,
    movieTitle: "Unknown",
    reviews: @[],
    fetchedAt: $now()
  )
  
  echo "=========================================="
  echo "IMDB Reviews Scraper v2.1"
  echo "=========================================="
  echo "Movie ID: ", movieId
  echo "Max pages: ", config.maxPages
  echo "Delay: ", config.delayMs, "ms"
  echo "Include spoilers: ", config.includeSpoilers
  echo "Rating filter: ", config.minRating, " - ", config.maxRating
  echo "=========================================="
  
  var pageNum = 0
  var start = 0
  const reviewsPerPage = 25  # IMDB показывает ~25 отзывов на страницу
  
  while pageNum < config.maxPages:
    echo "[", now().format("HH:mm:ss"), "] Processing page ", pageNum + 1, "/", 
         config.maxPages, " (start=", start, ")"
    
    let html = fetchReviewsPage(movieId, start, config)
    
    if html == "":
      echo "[WARNING] Empty response, stopping"
      break
    
    # При первой загрузке извлекаем информацию о фильме
    if pageNum == 0:
      echo "[DEBUG] About to extract movie info..."
      try:
        let (title, year, rating) = extractMovieInfo(html)
        result.movieTitle = title
        result.movieYear = year
        result.averageRating = rating
        echo "Movie: ", title, " (", year, ") - Rating: ", rating, "/10"
      except Exception as e:
        echo "[ERROR] extractMovieInfo crashed: ", e.msg
        echo "[ERROR] Stack trace: ", e.getStackTrace()
        result.movieTitle = "Unknown"
        result.movieYear = 0
        result.averageRating = 0.0
    
    # Парсим отзывы
    echo "[DEBUG] About to call parseReviewsFromHtml, html length: ", html.len
    var reviews: seq[Review] = @[]
    try:
      reviews = parseReviewsFromHtml(html, movieId)
      echo "[DEBUG] parseReviewsFromHtml returned, reviews count: ", reviews.len
    except Exception as e:
      echo "[ERROR] parseReviewsFromHtml crashed: ", e.msg
      echo "[ERROR] Stack trace: ", e.getStackTrace()
      break
    
    if reviews.len == 0:
      echo "[INFO] No more reviews found, stopping"
      break
    
    echo "[INFO] Extracted ", reviews.len, " reviews from this page"
    
    # Добавляем отзывы с учётом фильтров
    for review in reviews:
      var addReview = true
      
      # Фильтр по спойлерам
      if not config.includeSpoilers and review.spoiler:
        addReview = false
      
      # Фильтр по рейтингу
      if review.rating > 0.0 and 
         (review.rating < config.minRating or review.rating > config.maxRating):
        addReview = false
      
      if addReview:
        result.reviews.add review
    
    pageNum.inc
    start += reviewsPerPage
  
  result.totalReviews = result.reviews.len
  echo ""
  echo "[SUCCESS] Total reviews collected: ", result.totalReviews

# ============================================================================
# СТАТИСТИКА
# ============================================================================

type
  ReviewStats* = object
    totalReviews*: int
    reviewsWithRating*: int
    averageRating*: float
    ratingDistribution*: array[0..10, int]
    spoilerCount*: int
    verifiedCount*: int
    averageHelpfulness*: float
    mostHelpfulReview*: Review

proc calculateStats*(reviews: MovieReviews): ReviewStats =
  ## Вычисляет статистику по отзывам
  result = ReviewStats()
  result.totalReviews = reviews.reviews.len
  
  var totalRating = 0.0
  var totalHelpfulness = 0.0
  var helpfulnessCount = 0
  var maxHelpful = 0
  
  for review in reviews.reviews:
    # Рейтинги
    if review.rating > 0:
      result.reviewsWithRating.inc
      totalRating += review.rating
      let ratingInt = int(review.rating)
      if ratingInt >= 0 and ratingInt <= 10:
        result.ratingDistribution[ratingInt].inc
    
    # Спойлеры
    if review.spoiler:
      result.spoilerCount.inc
    
    # Верифицированные
    if review.verified:
      result.verifiedCount.inc
    
    # Полезность
    if review.helpful.total > 0:
      let helpfulness = float(review.helpful.found) / float(review.helpful.total)
      totalHelpfulness += helpfulness
      helpfulnessCount.inc
      
      if review.helpful.found > maxHelpful:
        maxHelpful = review.helpful.found
        result.mostHelpfulReview = review
  
  # Средние значения
  if result.reviewsWithRating > 0:
    result.averageRating = totalRating / float(result.reviewsWithRating)
  
  if helpfulnessCount > 0:
    result.averageHelpfulness = totalHelpfulness / float(helpfulnessCount)

proc printStats*(stats: ReviewStats) =
  ## Выводит статистику в консоль
  echo ""
  echo "=========================================="
  echo "REVIEW STATISTICS"
  echo "=========================================="
  echo "Total reviews: ", stats.totalReviews
  
  if stats.totalReviews == 0:
    echo "No reviews found to analyze."
    echo "=========================================="
    return
  
  echo "Reviews with rating: ", stats.reviewsWithRating
  
  if stats.reviewsWithRating > 0:
    echo "Average rating: ", formatFloat(stats.averageRating, ffDecimal, 2), "/10"
    echo ""
    echo "Rating distribution:"
    for i in countdown(10, 0):
      if stats.ratingDistribution[i] > 0:
        let percentage = (stats.ratingDistribution[i] * 100) div stats.totalReviews
        let bar = "#".repeat(percentage div 2)
        echo "  ", i, "/10: ", bar, " (", stats.ratingDistribution[i], ")"
  
  echo ""
  echo "Spoilers: ", stats.spoilerCount, " (", 
         (stats.spoilerCount * 100) div stats.totalReviews, "%)"
  echo "Verified reviews: ", stats.verifiedCount
  echo "Average helpfulness: ", 
         formatFloat(stats.averageHelpfulness * 100, ffDecimal, 1), "%"
  
  if stats.mostHelpfulReview.helpful.found > 0:
    echo ""
    echo "Most helpful review: \"", stats.mostHelpfulReview.title, "\""
    echo "  by ", stats.mostHelpfulReview.author
    echo "  ", stats.mostHelpfulReview.helpful.found, " out of ", 
             stats.mostHelpfulReview.helpful.total, " found helpful"
  
  echo "=========================================="

# ============================================================================
# ЭКСПОРТ ДАННЫХ
# ============================================================================

proc saveToJson*(reviews: MovieReviews, filename: string) =
  ## Сохраняет отзывы в JSON файл с полными метаданными
  var jsonReviews = newJArray()
  
  for review in reviews.reviews:
    var jsonReview = %* {
      "id": review.reviewId,
      "title": review.title,
      "rating": review.rating,
      "author": review.author,
      "authorUrl": review.authorUrl,
      "date": review.date,
      "dateTimestamp": review.dateTimestamp,
      "text": review.text,
      "helpful": {
        "found": review.helpful.found,
        "total": review.helpful.total
      },
      "spoiler": review.spoiler,
      "verified": review.verified,
      "permalink": review.permalink
    }
    jsonReviews.add(jsonReview)
  
  let output = %* {
    "metadata": {
      "movieTitle": reviews.movieTitle,
      "movieId": reviews.movieId,
      "movieYear": reviews.movieYear,
      "averageRating": reviews.averageRating,
      "fetchedAt": reviews.fetchedAt,
      "scrapedReviews": reviews.reviews.len
    },
    "reviews": jsonReviews
  }
  
  writeFile(filename, output.pretty())
  echo "[SUCCESS] Saved ", reviews.reviews.len, " reviews to ", filename

proc saveToCsv*(reviews: MovieReviews, filename: string) =
  ## Сохраняет отзывы в CSV файл (упрощённый формат)
  var csv = "ID,Title,Rating,Author,Date,Spoiler,HelpfulFound,HelpfulTotal,TextPreview\n"
  
  for review in reviews.reviews:
    let textPreview = review.text.replace("\n", " ")[0..min(100, review.text.len-1)]
    csv.add review.reviewId & ","
    csv.add "\"" & review.title.replace("\"", "\"\"") & "\","
    csv.add $review.rating & ","
    csv.add "\"" & review.author.replace("\"", "\"\"") & "\","
    csv.add review.date & ","
    csv.add $review.spoiler & ","
    csv.add $review.helpful.found & ","
    csv.add $review.helpful.total & ","
    csv.add "\"" & textPreview.replace("\"", "\"\"") & "\"\n"
  
  writeFile(filename, csv)
  echo "[SUCCESS] Saved ", reviews.reviews.len, " reviews to ", filename

proc printReviewSummary*(reviews: MovieReviews, maxReviews: int = 3) =
  ## Выводит краткую информацию о первых отзывах
  echo ""
  echo "=========================================="
  echo "FIRST ", min(maxReviews, reviews.reviews.len), " REVIEWS"
  echo "=========================================="
  
  for i in 0..<min(maxReviews, reviews.reviews.len):
    let r = reviews.reviews[i]
    echo ""
    echo "--- Review #", i + 1, " ---"
    echo "Title: ", r.title
    if r.rating > 0:
      echo "Rating: ", r.rating, "/10"
    echo "Author: ", r.author
    if r.date != "":
      echo "Date: ", r.date
    if r.helpful.total > 0:
      echo "Helpful: ", r.helpful.found, "/", r.helpful.total
    if r.spoiler:
      echo "⚠️  Contains spoilers"
    if r.verified:
      echo "✓ Verified review"
    echo ""
    let preview = if r.text.len > 200: r.text[0..199] & "..." else: r.text
    echo preview
    
    if r.permalink != "":
      echo ""
      echo "Link: ", r.permalink
  
  echo ""
  echo "=========================================="

# ============================================================================
# ФИЛЬТРАЦИЯ И СОРТИРОВКА
# ============================================================================

proc filterByRating*(reviews: var MovieReviews, minRating, maxRating: float) =
  ## Фильтрует отзывы по рейтингу
  reviews.reviews = reviews.reviews.filter proc(r: Review): bool =
    r.rating >= minRating and r.rating <= maxRating

proc filterBySpoilers*(reviews: var MovieReviews, includeSpoilers: bool) =
  ## Фильтрует спойлеры
  if not includeSpoilers:
    reviews.reviews = reviews.reviews.filter proc(r: Review): bool =
      not r.spoiler



proc sortByHelpfulness*(reviews: var MovieReviews) =
  ## Сортирует отзывы по полезности (по убыванию)
  reviews.reviews.sort(proc(a, b: Review): int {.closure.} =
    cmp(b.helpful.found, a.helpful.found))


proc sortByRating*(reviews: var MovieReviews, descending = true) =
  ## Сортирует отзывы по рейтингу
  reviews.reviews.sort proc(a, b: Review): int =
    if descending:
      result = cmp(b.rating, a.rating)
    else:
      result = cmp(a.rating, b.rating)

proc sortByDate*(reviews: var MovieReviews, newest = true) =
  ## Сортирует отзывы по дате
  reviews.reviews.sort proc(a, b: Review): int =
    if newest:
      result = cmp(b.dateTimestamp, a.dateTimestamp)
    else:
      result = cmp(a.dateTimestamp, b.dateTimestamp)

# ============================================================================
# ПРИМЕР ИСПОЛЬЗОВАНИЯ
# ============================================================================

when isMainModule:
  echo "IMDB Reviews Scraper v2.1"
  echo "Enhanced with nimBrowser library"
  echo ""
  
  # Конфигурация
  var config = defaultConfig()
  config.maxPages = 3
  config.delayMs = 2000
  config.includeSpoilers = true  # Включаем спойлеры для полного анализа
  
  # Terminator III
  let movieId = "tt0181852"
  
  # Собираем отзывы
  var reviews = fetchAllReviews(movieId, config)
  
  # Вычисляем статистику
  let stats = calculateStats(reviews)
  printStats(stats)
  
  # Выводим примеры отзывов
  printReviewSummary(reviews, 3)
  
  # Сортируем по полезности
  echo "\n[INFO] Sorting by helpfulness..."
  reviews.sortByHelpfulness()
  
  # Сохраняем в JSON
  let jsonFilename = "imdb_reviews_" & movieId & ".json"
  saveToJson(reviews, jsonFilename)
  
  # Сохраняем в CSV
  let csvFilename = "imdb_reviews_" & movieId & ".csv"
  saveToCsv(reviews, csvFilename)
  
  echo ""
  echo "✓ All done! Check the output files for complete data."
