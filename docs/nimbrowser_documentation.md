# NimBrowser - Документация

> **Версия:** 1.0  
> **Дата релиза:** 2026-02-10  
> **Язык:** Nim  
> **Лицензия:** MIT

---

## Оглавление

1. [Введение](#введение)
2. [Установка](#установка)
3. [Быстрый старт](#быстрый-старт)
4. [Архитектура](#архитектура)
5. [CSS Селекторы](#css-селекторы)
6. [XPath Поддержка](#xpath-поддержка)
7. [Работа с Response](#работа-с-response)
8. [Selector API](#selector-api)
9. [ItemLoader](#itemloader)
10. [LinkExtractor](#linkextractor)
11. [Middleware система](#middleware-система)
12. [Pipelines](#pipelines)
13. [Асинхронная загрузка](#асинхронная-загрузка)
14. [Экспорт данных](#экспорт-данных)
15. [Утилиты](#утилиты)
16. [Оптимизация и кэширование](#оптимизация-и-кэширование)
17. [Примеры использования](#примеры-использования)
18. [API Reference](#api-reference)
19. [Changelog](#changelog)

---

## Введение

**NimBrowser** — это мощная библиотека для веб-скрейпинга на языке Nim, предоставляющая надёжные возможности разбора CSS-селекторов и запросов к HTML/XML-документам.

### Основные возможности

- ✅ **Полная поддержка CSS3-селекторов** — все стандартные селекторы согласно спецификации W3C
- ✅ **XPath поддержка** — базовая поддержка XPath-выражений
- ✅ **Кэширование** — автоматическое кэширование скомпилированных селекторов для повышения производительности
- ✅ **Асинхронность** — поддержка async/await для неблокирующих HTTP запросов
- ✅ **Middleware** — система обработки запросов и ответов
- ✅ **Pipelines** — конвейерная обработка извлечённых данных
- ✅ **Экспорт** — поддержка форматов JSON, CSV, JSON Lines
- ✅ **Chainable API** — удобный цепочечный синтаксис для работы с селекторами

### Когда использовать NimBrowser

- Извлечение структурированных данных с веб-сайтов
- Парсинг HTML/XML документов
- Автоматизация сбора информации
- Мониторинг изменений на веб-страницах
- Создание веб-краулеров и пауков

---

## Установка

### Требования

- Nim 2.0.4 или выше
- Стандартные библиотеки Nim

### Установка через Nimble

```bash
nimble install netblaze
```

### Ручная установка

1. Скачайте файл `nimbrowser.nim`
2. Поместите его в директорию вашего проекта или в `~/.nimble/pkgs/`
3. Импортируйте в своём коде:

```nim
import netblaze/nimbrowser
```

---

## Быстрый старт

### Пример 1: Базовый разбор HTML

```nim
import netblaze/nimbrowser

# Парсинг HTML строки
let html = parseHtml("""
  <div class="container">
    <h1>Заголовок</h1>
    <p class="text">Первый параграф</p>
    <p class="text">Второй параграф</p>
  </div>
""")

# Извлечение одного элемента
let header = html.querySelector("h1")
echo header.innerText()  # "Заголовок"

# Извлечение нескольких элементов
let paragraphs = html.querySelectorAll("p.text")
for p in paragraphs:
  echo p.innerText()
```

### Пример 2: Работа с Response

```nim
import nimbrowser

# Создание Response объекта
let response = newResponse(
  url = "https://example.com",
  status = 200,
  body = """<div class="item">Content</div>"""
)

# Использование chainable API
let items = response.css(".item").getall()
for item in items:
  echo item.get()  # Получение текста
```

### Пример 3: Асинхронная загрузка

```nim
import nimbrowser, asyncdispatch

proc scrape() {.async.} =
  let response = await fetchAsync("https://example.com")
  let title = response.css("title").get()
  echo "Title: ", title

waitFor scrape()
```

---

## Архитектура

### Основные компоненты

```
┌─────────────────────────────────────────────────────────┐
│                      NimBrowser                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐   ┌──────────────┐  ┌─────────────┐  │
│  │   Lexer      │──▶│   Parser     │─▶│   Query     │  │
│  │  (Токенизация)│   │ (Синтаксис)  │  │ (Селектор)  │  │
│  └──────────────┘   └──────────────┘  └─────────────┘  │
│                                                         │
│  ┌──────────────┐   ┌──────────────┐  ┌─────────────┐  │
│  │  Response    │──▶│  Selector    │─▶│  XmlNode    │  │
│  │   (HTTP)     │   │   (API)      │  │   (DOM)     │  │
│  └──────────────┘   └──────────────┘  └─────────────┘  │
│                                                         │
│  ┌──────────────┐   ┌──────────────┐  ┌─────────────┐  │
│  │ ItemLoader   │──▶│  Pipeline    │─▶│    Item     │  │
│  │ (Загрузка)   │   │ (Обработка)  │  │   (Данные)  │  │
│  └──────────────┘   └──────────────┘  └─────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Потоки данных

1. **HTML → XmlNode** — парсинг HTML в DOM дерево
2. **CSS → Query** — компиляция селектора в структуру Query
3. **Query + XmlNode → Результаты** — поиск элементов
4. **Response → Selector → Данные** — извлечение информации

---

## CSS Селекторы

### Поддерживаемые селекторы

#### Базовые селекторы

| Селектор | Описание | Пример |
|----------|----------|--------|
| `*` | Универсальный селектор | `*` |
| `element` | Селектор по тегу | `div`, `p`, `span` |
| `.class` | Селектор по классу | `.container`, `.item` |
| `#id` | Селектор по ID | `#header`, `#main` |

#### Комбинаторы

| Комбинатор | Описание | Пример |
|------------|----------|--------|
| `(пробел)` | Потомок | `div p` |
| `>` | Прямой потомок | `div > p` |
| `+` | Следующий соседний элемент | `h1 + p` |
| `~` | Все последующие соседи | `h1 ~ p` |

#### Атрибутные селекторы

| Селектор | Описание | Пример |
|----------|----------|--------|
| `[attr]` | Атрибут существует | `[href]` |
| `[attr=value]` | Точное совпадение | `[type=text]` |
| `[attr~=value]` | Слово в списке | `[class~=item]` |
| `[attr\|=value]` | Начинается с (с дефисом) | `[lang\|=en]` |
| `[attr^=value]` | Начинается с | `[href^=https]` |
| `[attr$=value]` | Заканчивается на | `[src$=.jpg]` |
| `[attr*=value]` | Содержит подстроку | `[href*=example]` |

**Примеры:**

```nim
# Атрибут с дефисом (data-*, aria-*)
let elements = html.querySelectorAll("[data-id]")
let buttons = html.querySelectorAll("[aria-label='Close']")

# Сложные атрибутные селекторы
let links = html.querySelectorAll("a[href^='https'][target='_blank']")
```

#### Псевдо-классы

##### Позиционные

| Псевдо-класс | Описание | Пример |
|--------------|----------|--------|
| `:first-child` | Первый потомок | `li:first-child` |
| `:last-child` | Последний потомок | `li:last-child` |
| `:only-child` | Единственный потомок | `p:only-child` |
| `:first-of-type` | Первый элемент типа | `p:first-of-type` |
| `:last-of-type` | Последний элемент типа | `p:last-of-type` |
| `:only-of-type` | Единственный элемент типа | `p:only-of-type` |
| `:nth-child(n)` | n-ый потомок | `li:nth-child(2)` |
| `:nth-last-child(n)` | n-ый с конца | `li:nth-last-child(1)` |
| `:nth-of-type(n)` | n-ый элемент типа | `p:nth-of-type(odd)` |
| `:nth-last-of-type(n)` | n-ый типа с конца | `p:nth-last-of-type(2)` |

##### Другие псевдо-классы

| Псевдо-класс | Описание | Пример |
|--------------|----------|--------|
| `:empty` | Пустой элемент | `div:empty` |
| `:not(selector)` | Отрицание | `p:not(.exclude)` |

#### nth-селекторы

Формула: **an + b**

```nim
# Чётные элементы (2n)
let even = html.querySelectorAll("li:nth-child(even)")

# Нечётные элементы (2n+1)
let odd = html.querySelectorAll("li:nth-child(odd)")

# Каждый третий элемент
let every3rd = html.querySelectorAll("li:nth-child(3n)")

# Начиная с 5-го элемента
let from5 = html.querySelectorAll("li:nth-child(n+5)")

# Первые 3 элемента
let first3 = html.querySelectorAll("li:nth-child(-n+3)")
```

### Опции парсинга

```nim
type QueryOption = enum
  optUniqueIds          # Предполагать уникальные ID
  optUnicodeIdentifiers # Разрешить Unicode в идентификаторах
  optSimpleNot          # Ограничить :not() простыми селекторами
  optCaseSensitive      # Регистрозависимое сравнение

# Использование опций
let options = {optUniqueIds, optCaseSensitive}
let results = html.querySelectorAll(".item", options)
```

### Сложные примеры

```nim
# Комбинация селекторов
let selector = "div.container > ul.list li:not(.exclude)[data-active='true']:first-child"
let element = html.querySelector(selector)

# Множественные селекторы (OR)
let items = html.querySelectorAll(".item, .product, .entry")

# Вложенные структуры
let nested = html.querySelectorAll("article > header > h1.title")
```

---

## XPath Поддержка

### Основы XPath

```nim
# Создание Response
let response = newResponse(
  url = "https://example.com",
  body = """<div><p>Text</p></div>"""
)

# XPath запросы
let paragraphs = response.xpath("//p").getall()
let firstDiv = response.xpath("//div[1]").get()

# Комбинирование с атрибутами
let links = response.xpath("//a[@href]").getall()
```

### Поддерживаемые XPath выражения

- `//element` — все элементы с заданным именем
- `//element[n]` — n-ый элемент
- `//element[@attr]` — элементы с атрибутом
- `/root/child` — прямые потомки

### Ограничения

> ⚠️ **Внимание:** XPath поддержка в NimBrowser базовая. Для сложных XPath запросов рекомендуется использовать специализированные библиотеки.

---

## Работа с Response

### Создание Response

```nim
# Из строки
let response = newResponse(
  url = "https://example.com",
  status = 200,
  body = "<html>...</html>"
)

# Из HTTP запроса
let httpResponse = newAsyncHttpClient().get("https://example.com")
let response = newResponse(
  url = "https://example.com",
  status = httpResponse.code.int,
  headers = httpResponse.headers,
  body = httpResponse.body
)
```

### Методы Response

```nim
# CSS селекторы
let selector = response.css(".item")
let selectors = response.css(".item").getall()

# XPath
let xpathResult = response.xpath("//div")

# Доступ к данным
echo response.url      # URL страницы
echo response.status   # HTTP статус
echo response.body     # HTML контент

# Работа с заголовками
echo response.headers["Content-Type"]
```

### Chainable методы

```nim
# Цепочка вызовов
let price = response
  .css(".product")
  .css(".price")
  .get()

# Множественные элементы
let titles = response
  .css(".item")
  .getall()
  .mapIt(it.css(".title").get())
```

---

## Selector API

### Основные методы

```nim
type Selector = ref object
  node: XmlNode
  selectorType: SelectorType
  response: Response
```

#### get() / extract()

Извлечение текста из элемента:

```nim
let selector = response.css(".title")
let text = selector.get()  # Текст элемента
```

#### getall() / extractAll()

Извлечение всех совпадений:

```nim
let selectors = response.css(".item").getall()
for item in selectors:
  echo item.get()
```

#### css()

Вложенный CSS поиск:

```nim
let items = response.css(".container")
let titles = items.css(".title").getall()
```

#### xpath()

Вложенный XPath поиск:

```nim
let divs = response.xpath("//div")
let paragraphs = divs.xpath(".//p").getall()
```

#### attrib()

Получение значения атрибута:

```nim
let link = response.css("a").attrib("href")
echo link  # "https://example.com"
```

### Дополнительные методы

```nim
# Проверка содержания текста
if selector.contains("keyword"):
  echo "Найдено!"

# Проверка по регулярному выражению
if selector.matches(re"pattern"):
  echo "Совпадение!"
```

---

## ItemLoader

ItemLoader упрощает извлечение и валидацию данных.

### Базовое использование

```nim
# Создание загрузчика
let loader = newItemLoader(response.css(".product"))

# Добавление полей
loader.addCss("name", ".product-name")
loader.addCss("price", ".price")
loader.addXPath("description", "//div[@class='desc']")

# Получение результата
let item = loader.loadItem()
echo item["name"]
```

### Обработчики (processors)

```nim
# Очистка данных
proc cleanPrice(values: seq[string]): seq[string] =
  result = @[]
  for v in values:
    result.add v.strip().replace("$", "")

# Применение обработчика
loader.addCss("price", ".price", inputProcessor = cleanPrice)
```

### Процессоры вывода

```nim
proc joinTexts(values: seq[string]): string =
  return values.join(", ")

# Применение к финальному значению
loader.addCss("tags", ".tag", outputProcessor = joinTexts)
```

### Вложенные загрузчики

```nim
# Главный загрузчик
let mainLoader = newItemLoader(response.css(".product"))

# Вложенный для характеристик
let specsSelector = response.css(".specs")
mainLoader.addCss("specs.color", ".color")
mainLoader.addCss("specs.size", ".size")
```

---

## LinkExtractor

Автоматическое извлечение ссылок из страницы.

### Создание экстрактора

```nim
# Базовый экстрактор
let extractor = newLinkExtractor()

# С фильтрами
let extractor = newLinkExtractor(
  allowDomains = @["example.com"],
  denyDomains = @["spam.com"],
  allowPatterns = @[re"\/products\/.*"],
  denyPatterns = @[re"\/admin\/.*"],
  unique = true
)
```

### Извлечение ссылок

```nim
# Из Response
let links = extractor.extractLinks(response)

# Из Selector
let container = response.css(".links-container")
let links = extractor.extractLinks(container)

# Обработка ссылок
for link in links:
  echo "URL: ", link.url
  echo "Text: ", link.text
  echo "NoFollow: ", link.nofollow
```

### Параметры LinkExtractor

| Параметр | Тип | Описание |
|----------|-----|----------|
| `allowDomains` | `seq[string]` | Разрешённые домены |
| `denyDomains` | `seq[string]` | Запрещённые домены |
| `allowPatterns` | `seq[Regex]` | Разрешённые шаблоны URL |
| `denyPatterns` | `seq[Regex]` | Запрещённые шаблоны URL |
| `unique` | `bool` | Убирать дубликаты |
| `canonicalize` | `bool` | Канонизировать URL |

---

## Middleware система

Middleware позволяет обрабатывать запросы и ответы.

### Типы Middleware

```nim
type
  DownloaderMiddleware* = ref object of RootObj
  SpiderMiddleware* = ref object of RootObj
```

### Создание Middleware

```nim
type
  MyMiddleware = ref object of DownloaderMiddleware

method processRequest(middleware: MyMiddleware,
                     request: var string,
                     response: var Response) =
  # Обработка перед запросом
  echo "Processing request: ", request

method processResponse(middleware: MyMiddleware,
                      request: string,
                      response: var Response) =
  # Обработка после получения ответа
  echo "Processing response from: ", response.url
  
  # Модификация ответа
  if response.status == 404:
    response.body = "Page not found"
```

### Использование Middleware

```nim
let middleware = MyMiddleware()

# Применение к запросу
var request = "https://example.com"
var response = newResponse(...)

middleware.processRequest(request, response)
# ... выполнение запроса ...
middleware.processResponse(request, response)
```

### Практические примеры

#### User-Agent Middleware

```nim
type UserAgentMiddleware = ref object of DownloaderMiddleware
  userAgent: string

method processRequest(m: UserAgentMiddleware,
                     req: var string,
                     resp: var Response) =
  # Добавление User-Agent к запросу
  discard
```

#### Retry Middleware

```nim
type RetryMiddleware = ref object of DownloaderMiddleware
  maxRetries: int

method processResponse(m: RetryMiddleware,
                      req: string,
                      resp: var Response) =
  if resp.status >= 500:
    # Логика повтора запроса
    discard
```

---

## Pipelines

Pipelines обрабатывают извлечённые данные перед сохранением.

### Базовый Pipeline

```nim
type
  Pipeline* = ref object of RootObj

method processItem(pipeline: Pipeline, item: var Item): bool {.base.} =
  # Возвращает true если item нужно сохранить
  return true
```

### Создание Pipeline

```nim
type
  ValidationPipeline = ref object of Pipeline

method processItem(p: ValidationPipeline, item: var Item): bool =
  # Валидация данных
  if not item.hasKey("name"):
    return false  # Отбросить item
  
  # Очистка данных
  if item.hasKey("price"):
    let price = $item["price"]
    item["price"] = %price.strip()
  
  return true  # Сохранить item
```

### Цепочка Pipelines

```nim
# Множественные pipelines
let pipelines = @[
  ValidationPipeline(),
  CleanupPipeline(),
  EnrichmentPipeline()
]

# Обработка item
var item = %*{"name": "Product"}
var shouldSave = true

for pipeline in pipelines:
  shouldSave = pipeline.processItem(item)
  if not shouldSave:
    break  # Остановить обработку

if shouldSave:
  # Сохранить item
  discard
```

### Примеры Pipelines

#### Дедупликация

```nim
type
  DuplicatesPipeline = ref object of Pipeline
    seenIds: HashSet[string]

method processItem(p: DuplicatesPipeline, item: var Item): bool =
  if item.hasKey("id"):
    let id = $(item["id"])
    if id in p.seenIds:
      return false  # Дубликат
    p.seenIds.incl(id)
  return true
```

#### Обогащение данных

```nim
type
  EnrichmentPipeline = ref object of Pipeline

method processItem(p: EnrichmentPipeline, item: var Item): bool =
  # Добавление timestamp
  item["scraped_at"] = %now()
  
  # Вычисляемые поля
  if item.hasKey("price"):
    let price = $(item["price"]).parseFloat()
    item["price_with_tax"] = %(price * 1.2)
  
  return true
```

---

## Асинхронная загрузка

### Базовая асинхронность

```nim
import asyncdispatch

proc fetchPage(url: string): Future[Response] {.async.} =
  result = await fetchAsync(url)

proc main() {.async.} =
  let response = await fetchPage("https://example.com")
  echo response.css("title").get()

waitFor main()
```

### Параллельная загрузка

```nim
proc scrapeMultiple(urls: seq[string]): Future[seq[Response]] {.async.} =
  var futures: seq[Future[Response]] = @[]
  
  for url in urls:
    futures.add fetchAsync(url)
  
  result = await all(futures)

proc main() {.async.} =
  let urls = @[
    "https://example.com/page1",
    "https://example.com/page2",
    "https://example.com/page3"
  ]
  
  let responses = await scrapeMultiple(urls)
  
  for response in responses:
    let title = response.css("title").get()
    echo "Title: ", title

waitFor main()
```

### Обработка ошибок

```nim
proc safeFetch(url: string): Future[Response] {.async.} =
  try:
    result = await fetchAsync(url)
  except:
    echo "Error fetching: ", url
    result = newResponse(
      url = url,
      status = 0,
      body = ""
    )
```

---

## Экспорт данных

### JSON

```nim
# Один item
let item = %*{"name": "Product", "price": 100}
let jsonStr = item.toJson()
echo jsonStr  # {"name":"Product","price":100}

# Сохранение в файл
writeFile("data.json", jsonStr)
```

### JSON Lines

```nim
# Множество items
let items = @[
  %*{"name": "Product 1", "price": 100},
  %*{"name": "Product 2", "price": 200}
]

let jsonLines = items.toJsonLines()
echo jsonLines
# {"name":"Product 1","price":100}
# {"name":"Product 2","price":200}

# Сохранение
writeFile("data.jsonl", jsonLines)
```

### CSV

```nim
let items = @[
  %*{"name": "Product 1", "price": "100", "stock": "50"},
  %*{"name": "Product 2", "price": "200", "stock": "30"}
]

# Автоматические заголовки
let csv = items.toCsv()

# Явные заголовки
let headers = @["name", "price", "stock"]
let csv = items.toCsv(headers)

echo csv
# name,price,stock
# "Product 1","100","50"
# "Product 2","200","30"

# Сохранение
writeFile("data.csv", csv)
```

### Экспорт с обработкой

```nim
# Предобработка перед экспортом
var processedItems: seq[Item] = @[]

for item in items:
  var processed = item
  
  # Очистка данных
  if processed.hasKey("price"):
    let price = $(processed["price"])
    processed["price"] = %price.replace("$", "")
  
  processedItems.add processed

# Экспорт
writeFile("cleaned_data.json", processedItems.toJsonLines())
```

---

## Утилиты

### Работа с URL

```nim
# urljoin - объединение базового URL и относительного
let baseUrl = "https://example.com/products/"
let relativeUrl = "../categories/tech"
let absoluteUrl = urljoin(baseUrl, relativeUrl)
echo absoluteUrl  # "https://example.com/categories/tech"

# Примеры
urljoin("https://example.com/page", "other")
# -> "https://example.com/other"

urljoin("https://example.com/dir/page", "/absolute")
# -> "https://example.com/absolute"

urljoin("https://example.com/", "https://other.com/page")
# -> "https://other.com/page"
```

### Очистка HTML

```nim
# Удаление тегов
let html = "<p>Hello <b>World</b></p>"
let clean = stripTags(html)
echo clean  # "Hello World"

# Нормализация пробелов
let text = "Too    many   \n\n\n  spaces"
let normalized = normalizeWhitespace(text)
echo normalized  # "Too many\n\nspaces"

# Удаление комментариев
let html = "Text <!-- comment --> more"
let noComments = removeComments(html)
echo noComments  # "Text  more"
```

### Безопасный парсинг

```nim
# Обработка некорректного HTML
let brokenHtml = "<div><p>Unclosed tag"
let node = safeParse(brokenHtml)

# safeParse не выбросит исключение
# даже при невалидном HTML
```

### Работа с текстом

```nim
# innerText - весь текст включая вложенные элементы
let html = parseHtml("<div>Hello <span>World</span></div>")
echo html.innerText()  # "Hello World"

# innerTextClean - очищенный текст
echo html.innerTextClean()  # "Hello World" (без лишних пробелов)

# outerHtml - HTML представление
echo html.outerHtml()  # "<div>Hello <span>World</span></div>"
```

### Работа с атрибутами

```nim
let element = html.querySelector("a")

# Получение атрибута
let href = element.getAttr("href", "default")

# Проверка наличия атрибута
if element.hasAttr("target"):
  echo "Has target attribute"

# Установка атрибута
element.setAttr("rel", "nofollow")
```

---

## Оптимизация и кэширование

### Кэш селекторов

NimBrowser автоматически кэширует скомпилированные селекторы:

```nim
# Первый вызов - селектор компилируется
let items1 = html.querySelectorAll(".item")

# Второй вызов - используется кэшированная версия (быстрее)
let items2 = html.querySelectorAll(".item")
```

### Управление кэшем

```nim
# Очистка кэша
clearQueryCache()

# Отключение кэша
disableQueryCache()

# Включение кэша
enableQueryCache()
```

### Batch обработка

Выполнение нескольких селекторов за один проход:

```nim
let selectors = @[
  ".product-name",
  ".price",
  ".description",
  ".rating"
]

let results = html.querySelectorAllBatch(selectors)

for selector, nodes in results:
  echo "Selector: ", selector
  echo "Found: ", nodes.len, " elements"
```

### Оптимизация селекторов

#### Используйте ID когда возможно

```nim
# Быстро (с optUniqueIds)
let element = html.querySelector("#unique-id", {optUniqueIds})

# Медленнее
let element = html.querySelector(".many-items")
```

#### Ограничивайте область поиска

```nim
# Медленно - поиск по всему документу
let items = html.querySelectorAll(".item .title")

# Быстрее - поиск в контейнере
let container = html.querySelector(".container")
let items = container.querySelectorAll(".item .title")
```

#### Избегайте сложных селекторов

```nim
# Медленно
let complex = html.querySelector("div > ul > li:nth-child(2n+1) > a[href^='https']")

# Быстрее - разбить на части
let list = html.querySelector("div > ul")
let items = list.querySelectorAll("li")
let links = items[0].querySelectorAll("a[href^='https']")
```

---

## Примеры использования

### Пример 1: Скрейпинг новостного сайта

```nim
import nimbrowser, asyncdispatch

proc scrapeNews() {.async.} =
  let response = await fetchAsync("https://news-site.com")
  
  let articles = response.css(".article")
  
  var items: seq[Item] = @[]
  
  for article in articles.getall():
    let loader = newItemLoader(article)
    
    loader.addCss("title", ".article-title")
    loader.addCss("date", ".publish-date")
    loader.addCss("author", ".author-name")
    loader.addCss("summary", ".summary")
    loader.addCss("url", "a", attrib = "href")
    
    items.add loader.loadItem()
  
  # Экспорт в JSON
  writeFile("news.json", items.toJsonLines())
  
  echo "Scraped ", items.len, " articles"

waitFor scrapeNews()
```

### Пример 2: Скрейпинг интернет-магазина

```nim
import nimbrowser, asyncdispatch, strutils

proc cleanPrice(values: seq[string]): seq[string] =
  result = @[]
  for v in values:
    let cleaned = v.strip().replace("$", "").replace(",", "")
    result.add cleaned

proc scrapeProducts(category: string) {.async.} =
  let url = "https://shop.com/category/" & category
  let response = await fetchAsync(url)
  
  let products = response.css(".product-card")
  
  var items: seq[Item] = @[]
  
  for product in products.getall():
    let loader = newItemLoader(product)
    
    loader.addCss("name", ".product-name")
    loader.addCss("price", ".price", inputProcessor = cleanPrice)
    loader.addCss("rating", ".rating", attrib = "data-rating")
    loader.addCss("image", "img", attrib = "src")
    loader.addCss("availability", ".stock-status")
    
    # Получение URL товара
    let productUrl = product.css("a").attrib("href")
    loader.item["url"] = %urljoin(url, productUrl)
    
    items.add loader.loadItem()
  
  # Экспорт в CSV
  let headers = @["name", "price", "rating", "url", "availability"]
  writeFile(category & ".csv", items.toCsv(headers))
  
  echo "Category ", category, ": ", items.len, " products"

proc main() {.async.} =
  let categories = @["electronics", "books", "clothing"]
  
  for category in categories:
    await scrapeProducts(category)

waitFor main()
```

### Пример 3: Многостраничный скрейпинг с пагинацией

```nim
import nimbrowser, asyncdispatch

proc scrapePage(url: string): Future[seq[Item]] {.async.} =
  let response = await fetchAsync(url)
  
  let items = response.css(".item")
  result = @[]
  
  for item in items.getall():
    let loader = newItemLoader(item)
    loader.addCss("title", ".title")
    loader.addCss("description", ".desc")
    result.add loader.loadItem()

proc scrapeAllPages(baseUrl: string) {.async.} =
  var allItems: seq[Item] = @[]
  var currentPage = 1
  var hasNextPage = true
  
  while hasNextPage:
    let url = baseUrl & "?page=" & $currentPage
    echo "Scraping page ", currentPage
    
    let response = await fetchAsync(url)
    let pageItems = await scrapePage(url)
    
    allItems.add pageItems
    
    # Проверка наличия следующей страницы
    let nextButton = response.css(".pagination .next")
    hasNextPage = nextButton.node != nil
    
    currentPage += 1
    
    # Задержка между запросами
    await sleepAsync(1000)  # 1 секунда
  
  echo "Total items scraped: ", allItems.len
  writeFile("all_items.jsonl", allItems.toJsonLines())

waitFor scrapeAllPages("https://example.com/items")
```

### Пример 4: Извлечение ссылок и краулинг

```nim
import nimbrowser, asyncdispatch, sets

proc crawlSite(startUrl: string, maxDepth: int = 2) {.async.} =
  var visited: HashSet[string]
  var toVisit = @[startUrl]
  var depth = 0
  
  while toVisit.len > 0 and depth < maxDepth:
    var nextLevel: seq[string] = @[]
    
    for url in toVisit:
      if url in visited:
        continue
      
      visited.incl(url)
      echo "Visiting: ", url
      
      let response = await fetchAsync(url)
      
      # Извлечение данных
      let title = response.css("title").get()
      echo "  Title: ", title
      
      # Извлечение ссылок
      let extractor = newLinkExtractor(
        allowDomains = @["example.com"],
        unique = true
      )
      
      let links = extractor.extractLinks(response)
      
      for link in links:
        let absoluteUrl = urljoin(url, link.url)
        if absoluteUrl notin visited:
          nextLevel.add absoluteUrl
      
      await sleepAsync(500)  # Задержка
    
    toVisit = nextLevel
    depth += 1
  
  echo "Crawled ", visited.len, " pages"

waitFor crawlSite("https://example.com")
```

### Пример 5: Использование Middleware и Pipelines

```nim
import nimbrowser, asyncdispatch

# Middleware для логирования
type LoggingMiddleware = ref object of DownloaderMiddleware

method processRequest(m: LoggingMiddleware,
                     req: var string,
                     resp: var Response) =
  echo "[REQUEST] ", req

method processResponse(m: LoggingMiddleware,
                      req: string,
                      resp: var Response) =
  echo "[RESPONSE] ", resp.url, " - ", resp.status

# Pipeline для валидации
type ValidationPipeline = ref object of Pipeline

method processItem(p: ValidationPipeline, item: var Item): bool =
  # Проверка обязательных полей
  if not item.hasKey("title"):
    echo "Skipping item without title"
    return false
  
  # Очистка данных
  for key in item.keys:
    let value = $(item[key])
    item[key] = %value.strip()
  
  return true

# Основная функция
proc scrapeWithMiddleware() {.async.} =
  let middleware = LoggingMiddleware()
  let pipeline = ValidationPipeline()
  
  var request = "https://example.com"
  var response: Response
  
  # Обработка запроса
  middleware.processRequest(request, response)
  
  # Загрузка
  response = await fetchAsync(request)
  
  # Обработка ответа
  middleware.processResponse(request, response)
  
  # Извлечение данных
  let items = response.css(".item")
  var processedItems: seq[Item] = @[]
  
  for item in items.getall():
    let loader = newItemLoader(item)
    loader.addCss("title", ".title")
    loader.addCss("content", ".content")
    
    var extracted = loader.loadItem()
    
    # Обработка через pipeline
    if pipeline.processItem(extracted):
      processedItems.add extracted
  
  echo "Processed ", processedItems.len, " items"

waitFor scrapeWithMiddleware()
```

---

## API Reference

### Основные функции

#### parseHtml

```nim
proc parseHtml(html: string): XmlNode
```

Парсит HTML строку в DOM дерево.

**Параметры:**
- `html: string` — HTML контент

**Возвращает:** `XmlNode` — корневой узел DOM дерева

**Пример:**
```nim
let doc = parseHtml("<div>Hello</div>")
```

---

#### querySelector

```nim
proc querySelector*(root: XmlNode, 
                   query: string,
                   options: set[QueryOption] = DefaultQueryOptions): XmlNode
```

Находит первый элемент, соответствующий селектору.

**Параметры:**
- `root: XmlNode` — корневой узел для поиска
- `query: string` — CSS селектор
- `options: set[QueryOption]` — опции парсинга (опционально)

**Возвращает:** `XmlNode` — найденный элемент или `nil`

**Пример:**
```nim
let element = doc.querySelector(".class")
```

---

#### querySelectorAll

```nim
proc querySelectorAll*(root: XmlNode,
                      query: string,
                      options: set[QueryOption] = DefaultQueryOptions): seq[XmlNode]
```

Находит все элементы, соответствующие селектору.

**Параметры:**
- `root: XmlNode` — корневой узел для поиска
- `query: string` — CSS селектор
- `options: set[QueryOption]` — опции парсинга (опционально)

**Возвращает:** `seq[XmlNode]` — список найденных элементов

**Пример:**
```nim
let elements = doc.querySelectorAll("p.text")
```

---

### Response API

#### newResponse

```nim
proc newResponse*(url: string,
                 status: int = 200,
                 headers: HttpHeaders = nil,
                 body: string = ""): Response
```

Создаёт новый Response объект.

**Параметры:**
- `url: string` — URL страницы
- `status: int` — HTTP статус код
- `headers: HttpHeaders` — HTTP заголовки (опционально)
- `body: string` — HTML контент

**Возвращает:** `Response`

---

#### css (Response)

```nim
proc css*(response: Response, selector: string): Selector
```

Выполняет CSS селектор и возвращает Selector.

**Параметры:**
- `response: Response` — Response объект
- `selector: string` — CSS селектор

**Возвращает:** `Selector`

---

#### xpath (Response)

```nim
proc xpath*(response: Response, query: string): Selector
```

Выполняет XPath запрос и возвращает Selector.

**Параметры:**
- `response: Response` — Response объект
- `query: string` — XPath выражение

**Возвращает:** `Selector`

---

### Selector API

#### get / extract

```nim
proc get*(selector: Selector): string
proc extract*(selector: Selector): string
```

Извлекает текст из элемента.

**Возвращает:** `string` — текст элемента

---

#### getall / extractAll

```nim
proc getall*(selector: Selector): seq[Selector]
proc extractAll*(selector: Selector): seq[Selector]
```

Извлекает все совпадающие элементы.

**Возвращает:** `seq[Selector]` — список Selector'ов

---

#### attrib

```nim
proc attrib*(selector: Selector, name: string): string
```

Получает значение атрибута.

**Параметры:**
- `name: string` — имя атрибута

**Возвращает:** `string` — значение атрибута

---

### ItemLoader API

#### newItemLoader

```nim
proc newItemLoader*(selector: Selector = nil): ItemLoader
```

Создаёт новый ItemLoader.

**Параметры:**
- `selector: Selector` — базовый селектор (опционально)

**Возвращает:** `ItemLoader`

---

#### addCss

```nim
proc addCss*(loader: ItemLoader,
            fieldName: string,
            selector: string,
            attrib: string = "",
            inputProcessor: proc(values: seq[string]): seq[string] = nil,
            outputProcessor: proc(values: seq[string]): string = nil)
```

Добавляет поле с CSS селектором.

**Параметры:**
- `fieldName: string` — имя поля в Item
- `selector: string` — CSS селектор
- `attrib: string` — имя атрибута для извлечения (опционально)
- `inputProcessor` — функция обработки входных значений (опционально)
- `outputProcessor` — функция обработки финального значения (опционально)

---

#### addXPath

```nim
proc addXPath*(loader: ItemLoader,
              fieldName: string,
              query: string,
              attrib: string = "",
              inputProcessor: proc(values: seq[string]): seq[string] = nil,
              outputProcessor: proc(values: seq[string]): string = nil)
```

Добавляет поле с XPath запросом.

**Параметры:** аналогично `addCss`, но с XPath выражением

---

#### loadItem

```nim
proc loadItem*(loader: ItemLoader): Item
```

Загружает и возвращает Item со всеми извлечёнными полями.

**Возвращает:** `Item` — объект с данными

---

### LinkExtractor API

#### newLinkExtractor

```nim
proc newLinkExtractor*(allowDomains: seq[string] = @[],
                      denyDomains: seq[string] = @[],
                      allowPatterns: seq[Regex] = @[],
                      denyPatterns: seq[Regex] = @[],
                      unique: bool = true,
                      canonicalize: bool = true): LinkExtractor
```

Создаёт LinkExtractor с фильтрами.

**Параметры:**
- `allowDomains: seq[string]` — разрешённые домены
- `denyDomains: seq[string]` — запрещённые домены
- `allowPatterns: seq[Regex]` — разрешённые шаблоны URL
- `denyPatterns: seq[Regex]` — запрещённые шаблоны URL
- `unique: bool` — убирать дубликаты
- `canonicalize: bool` — канонизировать URL

**Возвращает:** `LinkExtractor`

---

#### extractLinks

```nim
proc extractLinks*(extractor: LinkExtractor, 
                  response: Response): seq[Link]
proc extractLinks*(extractor: LinkExtractor,
                  selector: Selector): seq[Link]
```

Извлекает ссылки из Response или Selector.

**Возвращает:** `seq[Link]` — список извлечённых ссылок

---

### Утилиты

#### urljoin

```nim
proc urljoin*(base: string, url: string): string
```

Объединяет базовый URL и относительный.

**Параметры:**
- `base: string` — базовый URL
- `url: string` — относительный или абсолютный URL

**Возвращает:** `string` — абсолютный URL

---

#### stripTags

```nim
proc stripTags*(html: string): string
```

Удаляет HTML теги из строки.

---

#### normalizeWhitespace

```nim
proc normalizeWhitespace*(text: string): string
```

Нормализует пробелы в тексте.

---

#### safeParse

```nim
proc safeParse*(html: string): XmlNode
```

Безопасный парсинг HTML с обработкой ошибок.

---

### Асинхронные функции

#### fetchAsync

```nim
proc fetchAsync*(url: string): Future[Response] {.async.}
```

Асинхронная загрузка URL.

**Параметры:**
- `url: string` — URL для загрузки

**Возвращает:** `Future[Response]` — асинхронный Response

---

### Экспорт

#### toJson

```nim
proc toJson*(item: Item): string
```

Конвертирует Item в JSON.

---

#### toJsonLines

```nim
proc toJsonLines*(items: seq[Item]): string
```

Конвертирует Items в JSON Lines формат.

---

#### toCsv

```nim
proc toCsv*(items: seq[Item], headers: seq[string] = @[]): string
```

Конвертирует Items в CSV.

**Параметры:**
- `items: seq[Item]` — список items
- `headers: seq[string]` — заголовки CSV (опционально)

**Возвращает:** `string` — CSV контент

---

### Кэш управление

#### clearQueryCache

```nim
proc clearQueryCache*()
```

Очищает кэш скомпилированных запросов.

---

#### disableQueryCache

```nim
proc disableQueryCache*()
```

Отключает кэширование запросов.

---

#### enableQueryCache

```nim
proc enableQueryCache*()
```

Включает кэширование запросов.

---

## Changelog

### Версия 1.0 (2026-02-10)

#### Исправления

- 🐛 **ИСПРАВЛЕНО:** Баги парсинга атрибутных селекторов с дефисами (`data-*`, `aria-*`)
- 🐛 **ИСПРАВЛЕНО:** Некорректная обработка операторов `*=`, `^=`, `$=` в атрибутах
- 🐛 **ИСПРАВЛЕНО:** Утечки памяти при работе с большими документами
- 🐛 **ИСПРАВЛЕНО:** Обработка селекторов с `data-testid` и другими data-атрибутами

#### Новые возможности

- ✨ **ДОБАВЛЕНО:** XPath поддержка
- ✨ **ДОБАВЛЕНО:** CSS extract с цепочками (`response.css().getall()`)
- ✨ **ДОБАВЛЕНО:** `urljoin` для объединения относительных URL
- ✨ **ДОБАВЛЕНО:** `LinkExtractor` для извлечения ссылок
- ✨ **ДОБАВЛЕНО:** `ItemLoader` для загрузки данных
- ✨ **ДОБАВЛЕНО:** Middleware система для обработки
- ✨ **ДОБАВЛЕНО:** Response объект для работы с ответами
- ✨ **ДОБАВЛЕНО:** Selector с chainable методами
- ✨ **ДОБАВЛЕНО:** Pipelines для обработки данных
- ✨ **ДОБАВЛЕНО:** Кэширование скомпилированных селекторов

#### Улучшения

- ⚡ Улучшена производительность лексера и парсера
- ⚡ Оптимизирована обработка больших документов
- 📝 Улучшена документация и примеры
- 🧹 Рефакторинг кода для лучшей читаемости

---

## Лицензия

NimBrowser распространяется под лицензией MIT.

---

## Контакты и поддержка

- **GitHub:** [ссылка на репозиторий]
- **Документация:** [ссылка на docs]
- **Issues:** [ссылка на issues]

---

## Благодарности

Спасибо сообществу Nim за создание замечательного языка программирования!

---

**NimBrowser v1.0** — делаем веб-скрейпинг простым и эффективным! 🚀
