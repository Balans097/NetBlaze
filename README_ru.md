# NetBlaze 🔥

> Мощный инструментарий для извлечения, обработки и работы с веб-данными на языке Nim

[![Nim Version](https://img.shields.io/badge/nim-2.0.4+-blue.svg)](https://nim-lang.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-stable-brightgreen.svg)]()

NetBlaze — это комплексная библиотека для работы с сетями передачи данных, включающая надёжный HTML-парсер, CSS/XPath селекторы и возможности веб-скрейпинга. Создана для обеспечения надёжности и производительности на языке программирования Nim.

---

## ✨ Возможности

### 🎯 Продвинутый HTML-парсер
- **Толерантный парсинг** — обработка „грязных“ HTML с автоматическим исправлением ошибок
- **Несколько режимов парсинга** - строгий, расслабленный и HTML5-совместимый
- **CSS селекторы** — полная поддержка CSS3 селекторов
- **XPath-запросы** — базовая поддержка XPath выражений
- **Автоисправление** — автоматическое закрытие тегов и исправление вложенности
- **Навигация по DOM** — полный обход и манипуляция деревом элементов

### 🌐 Движок для веб-скрейпинга
- **CSS3 селекторы** — полное соответствие спецификации W3C
- **Поддержка XPath** — извлечение данных с помощью XPath выражений
- **Chainable API** — удобный цепочечный синтаксис
- **Обработка Response** — удобная обёртка для HTTP ответов
- **Извлечение ссылок** — умное извлечение URL с фильтрацией
- **Item loaders** — структурированное извлечение данных

### ⚡ Производительность
- **Кэширование запросов** — автоматическое кэширование скомпилированных селекторов
- **Асинхронная поддержка** — неблокирующие HTTP запросы с async/await
- **Эффективная работа с памятью** — оптимизировано для больших документов
- **Быстрый разбор** - высокопроизводительный лексер и парсер

### 🛠 Дополнительные инструменты
- **Экспорт данных** — форматы JSON, CSV, JSON Lines
- **Система Middleware** — конвейер обработки запросов/ответов
- **Извлечение таблиц** — разбор HTML таблиц в структурированные данные
- **Обработка форм** — извлечение данных и полей форм
- **Текстовые утилиты** — удаление тегов, нормализация пробелов, декодирование сущностей

---

## 📦 Установка

### Через Nimble

```bash
nimble install netblaze
```

### Ручная установка

```bash
git clone https://github.com/Balans097/NetBlaze.git
cd NetBlaze
nimble install
```

---

## 🚀 Быстрый старт

### Базовый парсинг HTML

```nim
import netblaze/htmlparser

# Парсинг HTML с автоматическим исправлением ошибок
let html = """
<div class="container">
  <h1>Привет, мир</h1>
  <p class="text">Первый параграф
  <p class="text">Второй параграф
</div>
"""

let doc = parseHtml(html)

# Поиск элементов с помощью CSS селекторов
let heading = selectOne(doc, "h1")
echo getText(heading)  # "Привет, мир"

let paragraphs = select(doc, "p.text")
for p in paragraphs:
  echo getText(p)
```

### Веб-скрейпинг

```nim
import netblaze/nimbrowser

# Создание объекта response
let response = newResponse(
  url = "https://example.com",
  status = 200,
  body = """
    <div class="product">
      <h2 class="title">Название товара</h2>
      <span class="price">99.99₽</span>
    </div>
  """
)

# Использование chainable API для извлечения данных
let title = response.css(".product .title").get()
let price = response.css(".price").get()

echo "Название: ", title
echo "Цена: ", price
```

### Асинхронная загрузка

```nim
import netblaze/nimbrowser
import asyncdispatch

proc scrapeWebsite() {.async.} =
  let response = await fetchAsync("https://example.com")
  let titles = response.css("h1").getall()
  
  for title in titles:
    echo title.get()

waitFor scrapeWebsite()
```

### Извлечение таблиц

```nim
import netblaze/htmlparser

let html = """
<table>
  <thead>
    <tr><th>Имя</th><th>Возраст</th></tr>
  </thead>
  <tbody>
    <tr><td>Алиса</td><td>30</td></tr>
    <tr><td>Боб</td><td>25</td></tr>
  </tbody>
</table>
"""

let doc = parseHtml(html)
let table = selectOne(doc, "table")
let data = extractTable(table)

echo "Заголовки: ", data.headers
for row in data.rows:
  echo "Строка: ", row

# Экспорт в CSV
let csv = tableToCsv(data)
writeFile("output.csv", csv)
```

---

## 📚 Документация

### HTML парсер

#### Режимы парсинга

NetBlaze поддерживает три режима парсинга:

- **Strict (Строгий)** - Оригинальное поведение XML парсера, без автоисправлений
- **Relaxed (Расслабленный, по умолчанию)** - Автоматическое исправление ошибок, сбалансированный подход
- **HTML5** - Максимальная толерантность для современных веб-страниц

```nim
import netblaze/htmlparser

# Использование режима по умолчанию (relaxed)
let doc1 = parseHtml(html)

# Строгий режим
let doc2 = parseHtml(html, strictOptions())

# HTML5 режим для максимальной совместимости
let doc3 = parseHtml(html, html5Options())
```

#### CSS селекторы

```nim
# По тегу
let divs = select(doc, "div")

# По классу
let items = select(doc, ".item")

# По ID
let header = selectOne(doc, "#header")

# По атрибуту
let links = select(doc, "a[href]")
let httpsLinks = select(doc, "a[href^='https']")

# Комбинаторы
let directChildren = select(doc, "div > p")
let descendants = select(doc, "div p")
let adjacent = select(doc, "h1 + p")

# Псевдо-классы
let firstItem = selectOne(doc, "li:first-child")
let evenRows = select(doc, "tr:nth-child(even)")
let notExcluded = select(doc, "p:not(.exclude)")
```

#### Извлечение данных

```nim
# Получение текстового содержимого
let text = getText(element)
let textClean = getTextClean(element)  # Нормализованные пробелы

# Получение атрибутов
let href = getAttribute(element, "href")
let allAttrs = getAttributes(element)

# Получение всего текста из потомков
let allText = getAllText(element)
```

### Веб-скрейпинг

#### ItemLoader

Структурируйте извлечение данных:

```nim
import netblaze/nimbrowser

let response = newResponse(url = "...", body = html)

# Создание загрузчика элементов
let loader = newItemLoader(response.css(".product"))

# Добавление полей
loader.addCss("title", "h2.title")
loader.addCss("price", ".price", attrib = "data-price")
loader.addCss("image", "img", attrib = "src")

# Загрузка структурированных данных
let item = loader.loadItem()

echo item["title"]
echo item["price"]
echo item["image"]
```

#### LinkExtractor

Извлечение и фильтрация ссылок:

```nim
import netblaze/nimbrowser
import re

# Создание экстрактора ссылок с фильтрами
let extractor = newLinkExtractor(
  allowDomains = @["example.com"],
  denyPatterns = @[re".*\.(pdf|zip)$"],
  unique = true
)

let links = extractor.extractLinks(response)
for link in links:
  echo link.url
```

#### Экспорт данных

```nim
import netblaze/nimbrowser

var items: seq[Item] = @[]

# ... сбор элементов ...

# Экспорт в JSON
let jsonData = items.toJson()
writeFile("data.json", jsonData)

# Экспорт в JSON Lines
let jsonlData = items.toJsonLines()
writeFile("data.jsonl", jsonlData)

# Экспорт в CSV
let csvData = items.toCsv()
writeFile("data.csv", csvData)
```

---

## 🎯 Сценарии использования

- **Сбор данных** - Извлечение структурированных данных с веб-сайтов
- **Веб-мониторинг** - Отслеживание изменений на веб-страницах
- **Миграция контента** - Парсинг и преобразование HTML контента
- **SEO анализ** - Извлечение метаданных и анализ структуры страниц
- **Исследования** - Сбор данных для анализа и исследований
- **Тестирование** - Парсинг HTML ответов в тестах
- **Веб-краулеры** - Создание пауков и краулеров

---

## 📖 Примеры

### Сбор информации о товарах

```nim
import netblaze/nimbrowser
import asyncdispatch

proc scrapeProducts(url: string) {.async.} =
  let response = await fetchAsync(url)
  
  # Извлечение всех товаров
  let products = response.css(".product").getall()
  
  for product in products:
    let loader = newItemLoader(product)
    loader.addCss("name", "h2.name")
    loader.addCss("price", ".price")
    loader.addCss("rating", ".rating", attrib = "data-rating")
    loader.addCss("image", "img", attrib = "src")
    
    let item = loader.loadItem()
    echo item.toJson()

waitFor scrapeProducts("https://example.com/products")
```

### Парсинг новостных статей

```nim
import netblaze/htmlparser

let doc = loadHtml("article.html")

# Извлечение метаданных статьи
let title = selectOne(doc, "h1.article-title")
let author = selectOne(doc, ".author-name")
let date = selectOne(doc, "time[datetime]")

# Извлечение содержимого статьи
let paragraphs = select(doc, "article p")
var content = ""
for p in paragraphs:
  content &= getText(p) & "\n"

echo "Заголовок: ", getText(title)
echo "Автор: ", getText(author)
echo "Дата: ", getAttribute(date, "datetime")
echo "\nСодержимое:\n", content
```

### Извлечение email адресов

```nim
import netblaze/htmlparser
import re

let doc = loadHtml("contacts.html")
let allText = getAllText(doc)

# Поиск всех email адресов
let emailPattern = re"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"
var emails: seq[string] = @[]

for match in findAll(allText, emailPattern):
  emails.add(match)

echo "Найдено email адресов: ", emails
```

### Сбор данных из таблицы с пагинацией

```nim
import netblaze/nimbrowser
import asyncdispatch

proc scrapeAllPages() {.async.} =
  var page = 1
  var allData: seq[Item] = @[]
  
  while true:
    let url = "https://example.com/data?page=" & $page
    let response = await fetchAsync(url)
    
    # Извлечение данных с текущей страницы
    let rows = response.css("table tr").getall()
    
    if rows.len == 0:
      break  # Больше нет данных
    
    for row in rows:
      let loader = newItemLoader(row)
      loader.addCss("name", "td:nth-child(1)")
      loader.addCss("value", "td:nth-child(2)")
      allData.add(loader.loadItem())
    
    page += 1
  
  # Экспорт всех данных
  writeFile("all_data.json", allData.toJson())

waitFor scrapeAllPages()
```

### Извлечение и скачивание изображений

```nim
import netblaze/nimbrowser
import asyncdispatch, httpclient

proc downloadImages(pageUrl: string) {.async.} =
  let response = await fetchAsync(pageUrl)
  
  # Извлечение всех изображений
  let images = response.css("img").getall()
  
  var client = newAsyncHttpClient()
  
  for img in images:
    let src = img.attrib("src")
    let fullUrl = urljoin(pageUrl, src)
    
    # Скачивание изображения
    let imgData = await client.get(fullUrl)
    let filename = "images/" & src.split('/')[^1]
    writeFile(filename, await imgData.body)
    
    echo "Скачано: ", filename

waitFor downloadImages("https://example.com/gallery")
```

### Мониторинг изменений на странице

```nim
import netblaze/nimbrowser
import asyncdispatch, times, os

proc monitorPrice(url: string) {.async.} =
  var lastPrice = ""
  
  while true:
    let response = await fetchAsync(url)
    let currentPrice = response.css(".price").get()
    
    if currentPrice != lastPrice and lastPrice != "":
      echo "[", now(), "] Цена изменилась: ", lastPrice, " -> ", currentPrice
      # Здесь можно добавить отправку уведомления
    
    lastPrice = currentPrice
    await sleepAsync(60000)  # Проверка каждую минуту

waitFor monitorPrice("https://example.com/product/123")
```

### Обработка форм

```nim
import netblaze/htmlparser

let html = """
<form action="/submit" method="POST">
  <input type="text" name="username" value="user123">
  <input type="password" name="password">
  <select name="country">
    <option value="ru">Россия</option>
    <option value="us">США</option>
  </select>
  <textarea name="comment">Комментарий</textarea>
</form>
"""

let doc = parseHtml(html)
let form = selectOne(doc, "form")
let formData = extractForm(form)

echo "Действие: ", formData.action
echo "Метод: ", formData.command
echo "\nПоля:"
for field in formData.fields:
  echo "  ", field.name, " (", field.fieldType, "): ", field.value
  if field.options.len > 0:
    echo "    Опции: ", field.options
```

---

## 🔧 Продвинутые возможности

### Пользовательские опции парсера

```nim
import netblaze/htmlparser

var options = defaultOptions()
options.autoClose = true           # Автоматически закрывать теги
options.fixNesting = true          # Исправлять вложенность
options.removeInvalid = true       # Удалять невалидные теги
options.preserveWhitespace = false # Не сохранять пробелы
options.decodeEntities = true      # Декодировать HTML-сущности

let doc = parseHtml(html, options)
```

### XPath запросы

```nim
import netblaze/nimbrowser

let response = newResponse(url = "...", body = html)

# XPath выражения
let allParagraphs = response.xpath("//p").getall()
let firstDiv = response.xpath("//div[1]").get()
let linksWithHref = response.xpath("//a[@href]").getall()
```

### Обработка ошибок парсинга

```nim
import netblaze/htmlparser

var errors: seq[string] = @[]
let doc = parseHtml(dirtyHtml, errors, html5Options())

if errors.len > 0:
  echo "Обнаружено ошибок парсинга: ", errors.len
  for err in errors:
    echo "  - ", err
else:
  echo "HTML успешно обработан"
```

### Извлечение метаданных

```nim
import netblaze/htmlparser

let doc = loadHtml("page.html")

# Извлечение мета-тегов
let metaTags = select(doc, "meta")
for meta in metaTags:
  let name = getAttribute(meta, "name")
  let property = getAttribute(meta, "property")
  let content = getAttribute(meta, "content")
  
  if name != "":
    echo name, ": ", content
  elif property != "":
    echo property, ": ", content
```

### Статистика документа

```nim
import netblaze/htmlparser

let doc = loadHtml("page.html")

# Общая статистика
let stats = getStats(doc)
echo "Статистика документа:"
for key, val in stats.pairs:
  echo "  ", key, ": ", val

# Подсчёт тегов
let tagCounts = countTags(doc)
echo "\nКоличество тегов:"
for tag, count in tagCounts.pairs:
  echo "  ", tag, ": ", count
```

### Очистка и санитизация HTML

```nim
import netblaze/htmlparser

let doc = parseHtml(unsafeHtml)

# Удаление скриптов и стилей
let cleaned = removeScripts(doc)
let noStyles = removeStyles(cleaned)

# Удаление пустых тегов
let noEmpty = removeEmptyTags(noStyles)

# Удаление комментариев
let noComments = removeComments(noEmpty)

# Санитизация - оставить только безопасные теги
let safeTags = @["p", "div", "span", "b", "i", "a", "ul", "ol", "li", "h1", "h2", "h3"]
let sanitized = sanitize(noComments, safeTags)

# Красивый вывод
echo prettyPrint(sanitized)
```

### Работа с процессорами данных

```nim
import netblaze/nimbrowser
import strutils

# Процессор для очистки пробелов
proc cleanWhitespace(values: seq[string]): seq[string] =
  result = @[]
  for val in values:
    result.add(val.strip())

# Процессор для преобразования в верхний регистр
proc toUpper(values: seq[string]): string =
  if values.len > 0:
    return values[0].toUpperAscii()
  return ""

let loader = newItemLoader(response.css(".item"))
loader.addCss("name", "h2", 
  inputProcessor = cleanWhitespace,
  outputProcessor = toUpper)

let item = loader.loadItem()
```

---

## 🧪 Тестирование

```bash
# Запуск тестов
nimble test

# Запуск конкретного теста
nim c -r tests/test_htmlparser.nim
nim c -r tests/test_nimbrowser.nim
```

---

## 🤝 Участие в разработке

Вклад в проект приветствуется! Пожалуйста, не стесняйтесь отправлять Pull Request. Для серьёзных изменений сначала откройте issue для обсуждения того, что вы хотите изменить.

1. Сделайте форк репозитория
2. Создайте ветку для новой функции (`git checkout -b feature/AmazingFeature`)
3. Зафиксируйте изменения (`git commit -m 'Добавить AmazingFeature'`)
4. Отправьте в ветку (`git push origin feature/AmazingFeature`)
5. Откройте Pull Request

---

## 📝 Лицензия

Этот проект лицензирован под лицензией MIT - см. файл [LICENSE](LICENSE) для подробностей.

---

## 🙏 Благодарности

- Спасибо сообществу Nim за создание замечательного языка программирования
- Вдохновлено Python фреймворками BeautifulSoup и Scrapy
- Создано с упором на производительность и надёжность

---

## 📞 Поддержка

- **Issues**: [GitHub Issues](https://github.com/Balans097/NetBlaze/issues)
- **Обсуждения**: [GitHub Discussions](https://github.com/Balans097/NetBlaze/discussions)

---

## 🗺 Планы развития

- [ ] Поддержка рендеринга JavaScript
- [ ] Больше возможностей XPath
- [ ] Поддержка прокси
- [ ] Ограничение скорости запросов
- [ ] Обработка cookies
- [ ] Управление сессиями
- [ ] Расширенная система middleware
- [ ] Архитектура плагинов

---

## 🔍 Поддерживаемые селекторы

### CSS Селекторы

#### Базовые
- `*` - Универсальный селектор
- `element` - По тегу (`div`, `p`, `span`)
- `.class` - По классу
- `#id` - По ID

#### Атрибуты
- `[attr]` - Атрибут существует
- `[attr=value]` - Точное совпадение
- `[attr~=value]` - Слово в списке
- `[attr|=value]` - Начинается с (с дефисом)
- `[attr^=value]` - Начинается с
- `[attr$=value]` - Заканчивается на
- `[attr*=value]` - Содержит подстроку

#### Комбинаторы
- `(пробел)` - Потомок
- `>` - Прямой потомок
- `+` - Следующий соседний элемент
- `~` - Все последующие соседи

#### Псевдо-классы
- `:first-child`, `:last-child`, `:only-child`
- `:first-of-type`, `:last-of-type`, `:only-of-type`
- `:nth-child(n)`, `:nth-last-child(n)`
- `:nth-of-type(n)`, `:nth-last-of-type(n)`
- `:empty` - Пустой элемент
- `:not(selector)` - Отрицание

---

## 💡 Советы и рекомендации

### Производительность

```nim
# Используйте кэширование для повторяющихся запросов
enableQueryCache()

# Для единичных операций отключите кэш
disableQueryCache()

# Очистите кэш при необходимости
clearQueryCache()
```

### Обработка больших документов

```nim
# Используйте потоковую обработку
let stream = newFileStream("large.html", fmRead)
let doc = parseHtml(stream, html5Options())
stream.close()
```

### Отладка селекторов

```nim
# Проверьте, что селектор находит элементы
let elements = select(doc, "div.item")
echo "Найдено элементов: ", elements.len

# Выведите структуру документа
echo prettyPrint(doc)
```

---

**Сделано с ❤️ на Nim**

NetBlaze - делаем извлечение веб-данных простым и эффективным! 🚀
