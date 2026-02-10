# Документация модуля htmlparser.nim

**Версия:** 1.0 (2026-02-10)

## Описание

Улучшенный HTML парсер для работы с „грязными“ HTML-документами. Библиотека предназначена для автоматизированного разбора веб-ресурсов и извлечения данных.

### Основные возможности

- Толерантный парсинг с автоматическим исправлением ошибок
- CSS-селекторы для поиска элементов
- XPath-подобные селекторы
- Автоматическое закрытие незакрытых тегов
- Обработка некорректной вложенности
- Извлечение текста, атрибутов, таблиц, форм
- Навигация по DOM-дереву
- Модификация структуры документа
- Совместимость с BeautifulSoup/lxml API

---

## Содержание

1. [Типы данных](#типы-данных)
2. [Опции парсера](#опции-парсера)
3. [Функции парсинга](#функции-парсинга)
4. [CSS селекторы](#css-селекторы)
5. [Извлечение данных](#извлечение-данных)
6. [Навигация по дереву](#навигация-по-дереву)
7. [Работа с таблицами](#работа-с-таблицами)
8. [Работа с формами](#работа-с-формами)
9. [Работа со ссылками и изображениями](#работа-со-ссылками-и-изображениями)
10. [Фильтрация и поиск](#фильтрация-и-поиск)
11. [Статистика и анализ](#статистика-и-анализ)
12. [Модификация документа](#модификация-документа)
13. [Валидация](#валидация)
14. [XPath-подобные функции](#xpath-подобные-функции)
15. [Утилиты для очистки](#утилиты-для-очистки)
16. [Дополнительные утилиты](#дополнительные-утилиты)
17. [Строковые утилиты](#строковые-утилиты)

---

## Типы данных

### ParseMode

Режимы разбора HTML документа.

```nim
type ParseMode* = enum
  pmStrict      ## Строгий режим (оригинальное поведение XML парсера)
  pmRelaxed     ## Расслабленный режим (автоматическое исправление ошибок)
  pmHtml5       ## HTML5-совместимый режим (максимальная толерантность)
```

### ParserOptions

Опции для настройки поведения парсера.

```nim
type ParserOptions* = object
  mode*: ParseMode              ## Режим парсинга
  autoClose*: bool              ## Автоматически закрывать теги
  fixNesting*: bool             ## Исправлять неправильную вложенность
  removeInvalid*: bool          ## Удалять невалидные теги
  preserveWhitespace*: bool     ## Сохранять пробелы
  decodeEntities*: bool         ## Декодировать HTML-сущности
  maxErrors*: int               ## Максимальное количество ошибок для логирования (-1 = без ограничений)
```

### HtmlParser

Внутренний объект парсера (используется внутри модуля).

```nim
type HtmlParser* = object
  options: ParserOptions
  errors: seq[string]
  openTags: seq[XmlNode]     ## Стек открытых тегов
```

### TableData

Структура для хранения данных таблицы.

```nim
type TableData* = object
  headers*: seq[string]        ## Заголовки таблицы
  rows*: seq[seq[string]]      ## Строки данных
```

### FormField

Описание поля формы.

```nim
type FormField* = object
  name*: string                ## Имя поля
  fieldType*: string           ## Тип поля (text, password, select, textarea и т.д.)
  value*: string               ## Значение поля
  options*: seq[string]        ## Опции для select
```

### FormData

Структура для хранения данных формы.

```nim
type FormData* = object
  action*: string              ## URL для отправки формы
  command*: string             ## HTTP метод (GET/POST)
  fields*: seq[FormField]      ## Поля формы
```

---

## Константы

### SelfNestingTags

Теги, которые могут быть вложены сами в себя.

```nim
const SelfNestingTags* = {tagDiv, tagSpan, tagUl, tagOl, tagTable, tagTbody}
```

### ExtendedSingleTags

Расширенный список одиночных тегов (void elements в HTML5).

```nim
const ExtendedSingleTags* = SingleTags + {tagCommand, tagKeygen}
```

### AutoClosingPairs

Теги, которые автоматически закрывают предыдущие.

```nim
const AutoClosingPairs* = {
  tagLi: {tagLi},
  tagDt: {tagDt, tagDd},
  tagDd: {tagDt, tagDd},
  tagP: {tagP},
  tagTr: {tagTr},
  tagTd: {tagTd, tagTh},
  tagTh: {tagTd, tagTh},
  tagOption: {tagOption},
  tagOptgroup: {tagOptgroup}
}.toTable
```

### ParentRequirements

Теги, которые должны содержаться в определённых родителях.

```nim
const ParentRequirements* = {
  tagTr: {tagTable, tagThead, tagTbody, tagTfoot},
  tagTd: {tagTr},
  tagTh: {tagTr},
  tagThead: {tagTable},
  tagTbody: {tagTable},
  tagTfoot: {tagTable},
  tagLi: {tagUl, tagOl},
  tagDt: {tagDl},
  tagDd: {tagDl},
  tagOption: {tagSelect, tagOptgroup},
  tagOptgroup: {tagSelect}
}.toTable
```

---

## Опции парсера

### defaultOptions

```nim
proc defaultOptions*(): ParserOptions
```

Возвращает опции парсера по умолчанию (рекомендуется для большинства случаев).

**Параметры:**
- mode: `pmRelaxed`
- autoClose: `true`
- fixNesting: `true`
- removeInvalid: `false`
- preserveWhitespace: `false`
- decodeEntities: `true`
- maxErrors: `1000`

**Пример:**
```nim
let doc = loadHtml("page.html", defaultOptions())
```

---

### strictOptions

```nim
proc strictOptions*(): ParserOptions
```

Возвращает строгие опции парсера (оригинальное поведение XML парсера).

**Параметры:**
- mode: `pmStrict`
- autoClose: `false`
- fixNesting: `false`
- removeInvalid: `false`
- preserveWhitespace: `true`
- decodeEntities: `true`
- maxErrors: `-1` (без ограничений)

**Пример:**
```nim
let doc = loadHtml("page.html", strictOptions())
```

---

### html5Options

```nim
proc html5Options*(): ParserOptions
```

Возвращает опции для максимальной совместимости с HTML5.

**Параметры:**
- mode: `pmHtml5`
- autoClose: `true`
- fixNesting: `true`
- removeInvalid: `true`
- preserveWhitespace: `false`
- decodeEntities: `true`
- maxErrors: `-1` (без ограничений)

**Пример:**
```nim
let doc = loadHtml("page.html", html5Options())
```

---

## Функции парсинга

### parseHtml (из строки)

```nim
proc parseHtml*(html: string, options = defaultOptions()): XmlNode
```

Парсит HTML из строки.

**Параметры:**
- `html` - HTML строка для парсинга
- `options` - опции парсера (по умолчанию `defaultOptions()`)

**Возвращает:** корневой узел XmlNode

**Пример:**
```nim
let html = "<html><body><h1>Hello</h1></body></html>"
let doc = parseHtml(html)
```

---

### parseHtml (из потока)

```nim
proc parseHtml*(s: Stream, options = defaultOptions()): XmlNode
```

Парсит HTML из потока, игнорируя ошибки.

**Параметры:**
- `s` - поток для чтения
- `options` - опции парсера

**Возвращает:** корневой узел XmlNode

**Пример:**
```nim
let stream = newStringStream(htmlContent)
let doc = parseHtml(stream)
```

---

### parseHtml (из потока с обработкой ошибок)

```nim
proc parseHtml*(s: Stream, filename: string,
                errors: var seq[string], 
                options = defaultOptions()): XmlNode
```

Парсит HTML из потока с сохранением ошибок.

**Параметры:**
- `s` - поток для чтения
- `filename` - имя файла для сообщений об ошибках
- `errors` - последовательность для сохранения ошибок парсинга
- `options` - опции парсера

**Возвращает:** корневой узел XmlNode

**Пример:**
```nim
var errors: seq[string] = @[]
let stream = newFileStream("page.html", fmRead)
let doc = parseHtml(stream, "page.html", errors)
echo "Errors: ", errors.len
```

---

### loadHtml (из файла)

```nim
proc loadHtml*(path: string, options = defaultOptions()): XmlNode
```

Загружает и парсит HTML из файла, игнорируя ошибки.

**Параметры:**
- `path` - путь к файлу
- `options` - опции парсера

**Возвращает:** корневой узел XmlNode

**Исключения:** `IOError` если файл не может быть прочитан

**Пример:**
```nim
let doc = loadHtml("page.html")
```

---

### loadHtml (из файла с обработкой ошибок)

```nim
proc loadHtml*(path: string, errors: var seq[string], 
               options = defaultOptions()): XmlNode
```

Загружает и парсит HTML из файла с сохранением ошибок.

**Параметры:**
- `path` - путь к файлу
- `errors` - последовательность для сохранения ошибок парсинга
- `options` - опции парсера

**Возвращает:** корневой узел XmlNode

**Исключения:** `IOError` если файл не может быть прочитан

**Пример:**
```nim
var errors: seq[string] = @[]
let doc = loadHtml("page.html", errors)
if errors.len > 0:
  echo "Parsing errors found: ", errors.len
```

---

## CSS селекторы

### select

```nim
proc select*(node: XmlNode, selector: string): seq[XmlNode]
```

Простой CSS селектор для поиска элементов.

**Поддерживаемые селекторы:**
- По тегу: `"div"`, `"p"`, `"a"`
- По классу: `".classname"`, `"div.classname"`
- По ID: `"#idname"`, `"div#idname"`
- По атрибуту: `"[attr]"`, `"[attr=value]"`
- Универсальный: `"*"`

**Параметры:**
- `node` - узел для поиска
- `selector` - CSS селектор

**Возвращает:** последовательность найденных узлов

**Пример:**
```nim
let doc = parseHtml(html)

# Поиск по тегу
let divs = select(doc, "div")

# Поиск по классу
let headers = select(doc, ".header")

# Поиск по ID
let main = select(doc, "#main-content")

# Комбинированный поиск
let navLinks = select(doc, "nav.main")

# Поиск по атрибуту
let forms = select(doc, "[action=/submit]")
```

---

### selectOne

```nim
proc selectOne*(node: XmlNode, selector: string): XmlNode
```

Находит первый узел, соответствующий CSS селектору.

**Параметры:**
- `node` - узел для поиска
- `selector` - CSS селектор

**Возвращает:** первый найденный узел или `nil`

**Пример:**
```nim
let title = selectOne(doc, "#page-title")
if title != nil:
  echo "Title: ", getText(title)
```

---

## Извлечение данных

### getText

```nim
proc getText*(node: XmlNode, recursive = true): string
```

Извлекает весь текст из узла.

**Параметры:**
- `node` - узел для извлечения текста
- `recursive` - извлекать текст рекурсивно из всех потомков (по умолчанию `true`)

**Возвращает:** текстовое содержимое узла

**Пример:**
```nim
let paragraph = selectOne(doc, "p")
echo getText(paragraph)  # Весь текст из параграфа

let div = selectOne(doc, "div.content")
echo getText(div, recursive = false)  # Только непосредственный текст
```

---

### getTexts

```nim
proc getTexts*(node: XmlNode): seq[string]
```

Возвращает все текстовые фрагменты из узла в виде последовательности.

**Параметры:**
- `node` - узел для извлечения текста

**Возвращает:** последовательность текстовых фрагментов (без пустых строк)

**Пример:**
```nim
let texts = getTexts(doc)
for text in texts:
  echo text
```

---

### getAttribute

```nim
proc getAttribute*(node: XmlNode, attr: string, default = ""): string
```

Получает значение атрибута узла или значение по умолчанию.

**Параметры:**
- `node` - узел
- `attr` - имя атрибута
- `default` - значение по умолчанию (если атрибут отсутствует)

**Возвращает:** значение атрибута или значение по умолчанию

**Пример:**
```nim
let link = selectOne(doc, "a")
let href = getAttribute(link, "href", "#")
let target = getAttribute(link, "target", "_self")
```

---

### getAttributes

```nim
proc getAttributes*(node: XmlNode): Table[string, string]
```

Возвращает все атрибуты узла в виде таблицы.

**Параметры:**
- `node` - узел

**Возвращает:** таблица атрибутов (имя -> значение)

**Пример:**
```nim
let img = selectOne(doc, "img")
let attrs = getAttributes(img)
for name, value in attrs.pairs:
  echo name, " = ", value
```

---

## Навигация по дереву

### parent

```nim
proc parent*(node: XmlNode): XmlNode
```

Возвращает родительский узел.

**Примечание:** XmlNode не хранит ссылку на родителя, поэтому эта функция всегда возвращает `nil`. Для полноценной навигации требуется построение дополнительной структуры.

**Параметры:**
- `node` - узел

**Возвращает:** всегда `nil`

---

### nextSibling

```nim
proc nextSibling*(node: XmlNode, parent: XmlNode): XmlNode
```

Возвращает следующий элемент-сосед.

**Параметры:**
- `node` - текущий узел
- `parent` - родительский узел

**Возвращает:** следующий элемент-сосед или `nil`

**Пример:**
```nim
let firstLi = selectOne(doc, "li")
let parent = selectOne(doc, "ul")
let secondLi = nextSibling(firstLi, parent)
```

---

### previousSibling

```nim
proc previousSibling*(node: XmlNode, parent: XmlNode): XmlNode
```

Возвращает предыдущий элемент-сосед.

**Параметры:**
- `node` - текущий узел
- `parent` - родительский узел

**Возвращает:** предыдущий элемент-сосед или `nil`

**Пример:**
```nim
let li = selectOne(doc, "li:nth-child(3)")
let parent = selectOne(doc, "ul")
let prevLi = previousSibling(li, parent)
```

---

## Работа с таблицами

### extractTable

```nim
proc extractTable*(tableNode: XmlNode): TableData
```

Извлекает данные из HTML таблицы.

**Параметры:**
- `tableNode` - узел с тегом `<table>`

**Возвращает:** структуру `TableData` с заголовками и строками

**Пример:**
```nim
let table = selectOne(doc, "table")
let data = extractTable(table)

echo "Headers: ", data.headers
for row in data.rows:
  echo "Row: ", row
```

---

### tableToCsv

```nim
proc tableToCsv*(table: TableData): string
```

Конвертирует таблицу в CSV формат.

**Параметры:**
- `table` - структура TableData

**Возвращает:** строка в формате CSV

**Пример:**
```nim
let table = extractTable(tableNode)
let csv = tableToCsv(table)
writeFile("output.csv", csv)
```

---

## Работа с формами

### extractForm

```nim
proc extractForm*(formNode: XmlNode): FormData
```

Извлекает данные из HTML формы.

**Параметры:**
- `formNode` - узел с тегом `<form>`

**Возвращает:** структуру `FormData` с полями формы

**Поддерживаемые типы полей:**
- `<input>` (text, password, email, и т.д.)
- `<textarea>`
- `<select>` (с опциями)

**Пример:**
```nim
let form = selectOne(doc, "form")
let formData = extractForm(form)

echo "Action: ", formData.action
echo "Method: ", formData.command
for field in formData.fields:
  echo field.name, ": ", field.fieldType
  if field.options.len > 0:
    echo "  Options: ", field.options
```

---

## Работа со ссылками и изображениями

### extractLinks

```nim
proc extractLinks*(node: XmlNode): seq[(string, string)]
```

Извлекает все ссылки из документа.

**Параметры:**
- `node` - корневой узел для поиска

**Возвращает:** последовательность кортежей (href, текст ссылки)

**Пример:**
```nim
let links = extractLinks(doc)
for (href, text) in links:
  echo text, " -> ", href
```

---

### extractImages

```nim
proc extractImages*(node: XmlNode): seq[(string, string)]
```

Извлекает все изображения из документа.

**Параметры:**
- `node` - корневой узел для поиска

**Возвращает:** последовательность кортежей (src, alt)

**Пример:**
```nim
let images = extractImages(doc)
for (src, alt) in images:
  echo src, " (", alt, ")"
```

---

## Фильтрация и поиск

### findAllByTag

```nim
proc findAllByTag*(node: XmlNode, tag: string): seq[XmlNode]
```

Находит все узлы с указанным тегом (без учёта регистра).

**Параметры:**
- `node` - корневой узел для поиска
- `tag` - имя тега

**Возвращает:** последовательность найденных узлов

**Пример:**
```nim
let divs = findAllByTag(doc, "div")
let paragraphs = findAllByTag(doc, "p")
```

---

### findAllByClass

```nim
proc findAllByClass*(node: XmlNode, className: string): seq[XmlNode]
```

Находит все узлы с указанным классом.

**Параметры:**
- `node` - корневой узел для поиска
- `className` - имя класса (без точки)

**Возвращает:** последовательность найденных узлов

**Пример:**
```nim
let headers = findAllByClass(doc, "header")
let buttons = findAllByClass(doc, "btn-primary")
```

---

### findById

```nim
proc findById*(node: XmlNode, id: string): XmlNode
```

Находит узел по ID.

**Параметры:**
- `node` - корневой узел для поиска
- `id` - значение атрибута id

**Возвращает:** найденный узел или `nil`

**Пример:**
```nim
let main = findById(doc, "main-content")
if main != nil:
  echo getText(main)
```

---

### findAllByAttr

```nim
proc findAllByAttr*(node: XmlNode, attr: string, value = ""): seq[XmlNode]
```

Находит все узлы с указанным атрибутом (и опционально значением).

**Параметры:**
- `node` - корневой узел для поиска
- `attr` - имя атрибута
- `value` - значение атрибута (если пусто, ищет только наличие атрибута)

**Возвращает:** последовательность найденных узлов

**Пример:**
```nim
# Все элементы с атрибутом data-id
let withDataId = findAllByAttr(doc, "data-id")

# Все элементы с data-type="product"
let products = findAllByAttr(doc, "data-type", "product")
```

---

### findAllByText

```nim
proc findAllByText*(node: XmlNode, text: string, exact = false): seq[XmlNode]
```

Находит все узлы, содержащие указанный текст.

**Параметры:**
- `node` - корневой узел для поиска
- `text` - искомый текст
- `exact` - точное совпадение (по умолчанию `false` - поиск подстроки без учёта регистра)

**Возвращает:** последовательность найденных узлов

**Пример:**
```nim
# Поиск всех элементов, содержащих "error"
let errors = findAllByText(doc, "error")

# Точное совпадение
let welcome = findAllByText(doc, "Welcome!", exact = true)
```

---

## Статистика и анализ

### countTags

```nim
proc countTags*(node: XmlNode): Table[string, int]
```

Подсчитывает количество каждого тега в документе (без учёта регистра).

**Параметры:**
- `node` - корневой узел

**Возвращает:** таблица (тег -> количество)

**Пример:**
```nim
let tagCounts = countTags(doc)
for tag, count in tagCounts.pairs:
  echo tag, ": ", count
```

---

### getDepth

```nim
proc getDepth*(node: XmlNode): int
```

Вычисляет максимальную глубину дерева узлов.

**Параметры:**
- `node` - корневой узел

**Возвращает:** максимальная глубина вложенности

**Пример:**
```nim
let depth = getDepth(doc)
echo "Document depth: ", depth
```

---

### getStats

```nim
proc getStats*(node: XmlNode): Table[string, int]
```

Возвращает статистику документа.

**Параметры:**
- `node` - корневой узел

**Возвращает:** таблица со статистикой:
- `"elements"` - количество элементов
- `"elements_with_attrs"` - количество элементов с атрибутами
- `"total_attrs"` - общее количество атрибутов
- `"text_nodes"` - количество текстовых узлов
- `"comments"` - количество комментариев
- `"depth"` - глубина дерева

**Пример:**
```nim
let stats = getStats(doc)
echo "Elements: ", stats["elements"]
echo "Text nodes: ", stats["text_nodes"]
echo "Depth: ", stats["depth"]
```

---

## Модификация документа

### removeNode

```nim
proc removeNode*(node: XmlNode, parent: XmlNode): bool
```

Удаляет узел из родителя.

**Параметры:**
- `node` - узел для удаления
- `parent` - родительский узел

**Возвращает:** `true` если удаление успешно, `false` в противном случае

**Пример:**
```nim
let div = selectOne(doc, "div.obsolete")
let parent = selectOne(doc, "body")
discard removeNode(div, parent)
```

---

### replaceNode

```nim
proc replaceNode*(oldNode: XmlNode, newNode: XmlNode, parent: var XmlNode): bool
```

Заменяет один узел на другой.

**Параметры:**
- `oldNode` - узел для замены
- `newNode` - новый узел
- `parent` - родительский узел (var)

**Возвращает:** `true` если замена успешна, `false` в противном случае

**Пример:**
```nim
let oldPara = selectOne(doc, "p#old")
let newPara = newElement("p")
newPara.add(newText("New content"))
var body = selectOne(doc, "body")
discard replaceNode(oldPara, newPara, body)
```

---

### unwrap

```nim
proc unwrap*(node: XmlNode, parent: XmlNode): bool
```

Убирает обёртку узла, оставляя его содержимое на том же уровне.

**Параметры:**
- `node` - узел-обёртка для удаления
- `parent` - родительский узел

**Возвращает:** `true` если операция успешна, `false` в противном случае

**Пример:**
```nim
# <div><span>Text</span></div> -> <div>Text</div>
let span = selectOne(doc, "span")
let div = selectOne(doc, "div")
discard unwrap(span, div)
```

---

### wrap

```nim
proc wrap*(node: XmlNode, wrapperTag: string, parent: var XmlNode): bool
```

Оборачивает узел новым элементом.

**Параметры:**
- `node` - узел для обёртывания
- `wrapperTag` - имя тега обёртки
- `parent` - родительский узел (var)

**Возвращает:** `true` если операция успешна, `false` в противном случае

**Пример:**
```nim
# Text -> <div>Text</div>
let textNode = selectOne(doc, "p")
var body = selectOne(doc, "body")
discard wrap(textNode, "div", body)
```

---

## Валидация

### hasRequiredAttrs

```nim
proc hasRequiredAttrs*(node: XmlNode, attrs: seq[string]): bool
```

Проверяет наличие всех требуемых атрибутов.

**Параметры:**
- `node` - проверяемый узел
- `attrs` - список требуемых атрибутов

**Возвращает:** `true` если все атрибуты присутствуют, `false` в противном случае

**Пример:**
```nim
let form = selectOne(doc, "form")
if hasRequiredAttrs(form, @["action", "method"]):
  echo "Form is valid"
```

---

### validateStructure

```nim
proc validateStructure*(node: XmlNode, rules: Table[string, seq[string]]): seq[string]
```

Проверяет структуру документа по правилам.

**Параметры:**
- `node` - корневой узел
- `rules` - таблица правил (тег -> список разрешённых дочерних тегов)

**Возвращает:** последовательность сообщений об ошибках валидации

**Пример:**
```nim
var rules = initTable[string, seq[string]]()
rules["table"] = @["thead", "tbody", "tfoot", "tr"]
rules["tr"] = @["td", "th"]

let errors = validateStructure(doc, rules)
for error in errors:
  echo error
```

---

## XPath-подобные функции

### findByPath

```nim
proc findByPath*(node: XmlNode, path: string): seq[XmlNode]
```

Простой XPath-подобный поиск элементов.

**Поддерживаемые пути:**
- `"tag1/tag2/tag3"` - путь от родителя к потомкам
- `"//tag"` - рекурсивный поиск тега

**Параметры:**
- `node` - корневой узел
- `path` - путь для поиска

**Возвращает:** последовательность найденных узлов

**Пример:**
```nim
# Найти все td внутри tbody внутри table
let cells = findByPath(doc, "table/tbody/td")

# Рекурсивно найти все div
let divs = findByPath(doc, "//div")
```

---

## Утилиты для очистки

### removeEmptyTags

```nim
proc removeEmptyTags*(node: XmlNode): XmlNode
```

Удаляет пустые теги (без текста и без дочерних элементов).

**Примечание:** Не удаляет одиночные теги (void elements).

**Параметры:**
- `node` - узел для очистки

**Возвращает:** очищенный узел (модифицирует исходный)

**Пример:**
```nim
let cleaned = removeEmptyTags(doc)
```

---

### removeComments

```nim
proc removeComments*(node: XmlNode): XmlNode
```

Удаляет все комментарии из документа.

**Параметры:**
- `node` - узел для очистки

**Возвращает:** узел без комментариев (модифицирует исходный)

**Пример:**
```nim
let noComments = removeComments(doc)
```

---

### sanitize

```nim
proc sanitize*(node: XmlNode, allowedTags: seq[string]): XmlNode
```

Оставляет только разрешённые теги (фильтрация XSS).

**Параметры:**
- `node` - узел для санитизации
- `allowedTags` - список разрешённых тегов (в нижнем регистре)

**Возвращает:** санитизированный узел

**Пример:**
```nim
# Разрешить только безопасные теги
let safeTags = @["p", "div", "span", "b", "i", "a", "ul", "ol", "li"]
let safe = sanitize(doc, safeTags)
```

---

## Дополнительные утилиты

### prettyPrint

```nim
proc prettyPrint*(node: XmlNode, indent = 0): string
```

Красиво печатает HTML с отступами.

**Параметры:**
- `node` - узел для вывода
- `indent` - начальный уровень отступа (по умолчанию 0)

**Возвращает:** отформатированная HTML строка

**Пример:**
```nim
let formatted = prettyPrint(doc)
writeFile("output.html", formatted)
```

---

### entityToUtf8

```nim
proc entityToUtf8*(entity: string): string
```

Преобразует имя HTML-сущности в эквивалент UTF-8.

**Параметры:**
- `entity` - имя сущности (например, `"Uuml"` для `&Uuml;`) или числовой код (`"#220"` или `"#x000DC"`)

**Возвращает:** UTF-8 символ или пустая строка

**Пример:**
```nim
echo entityToUtf8("nbsp")   # неразрывный пробел
echo entityToUtf8("#220")   # Ü
echo entityToUtf8("#x000DC") # Ü
```

---

## Строковые утилиты

### normalizeWhitespace

```nim
proc normalizeWhitespace*(text: string): string
```

Нормализует пробельные символы (схлопывает множественные пробелы в один).

**Параметры:**
- `text` - исходная строка

**Возвращает:** нормализованная строка

**Пример:**
```nim
let text = "Hello    world\n\t  !"
echo normalizeWhitespace(text)  # "Hello world !"
```

---

### stripTags

```nim
proc stripTags*(html: string): string
```

Удаляет все HTML теги из строки, оставляя только текст.

**Параметры:**
- `html` - HTML строка

**Возвращает:** строка без тегов

**Пример:**
```nim
let html = "<p>Hello <b>world</b>!</p>"
echo stripTags(html)  # "Hello world!"
```

---

### decodeHtmlEntities

```nim
proc decodeHtmlEntities*(text: string): string
```

Декодирует все HTML сущности в тексте.

**Параметры:**
- `text` - текст с HTML сущностями

**Возвращает:** декодированный текст

**Пример:**
```nim
let text = "Hello &nbsp; &lt;world&gt; &amp; &#220;"
echo decodeHtmlEntities(text)  # "Hello   <world> & Ü"
```

---

## Информационная функция

### aboutHtmlParser

```nim
proc aboutHtmlParser*(): string
```

Возвращает информацию о библиотеке htmlparser.

**Возвращает:** многострочная строка с описанием библиотеки

**Пример:**
```nim
echo aboutHtmlParser()
```

---

## Примеры использования

### Базовый парсинг и поиск

```nim
import htmlparser

# Парсинг HTML
let html = """
<html>
  <body>
    <div class="container">
      <h1 id="title">Welcome</h1>
      <p>This is a paragraph.</p>
      <a href="https://example.com">Link</a>
    </div>
  </body>
</html>
"""

let doc = parseHtml(html)

# Поиск элементов
let title = selectOne(doc, "#title")
echo "Title: ", getText(title)

let links = select(doc, "a")
for link in links:
  echo "Link: ", getAttribute(link, "href")
```

---

### Извлечение данных из таблицы

```nim
import htmlparser

let html = """
<table>
  <thead>
    <tr><th>Name</th><th>Age</th></tr>
  </thead>
  <tbody>
    <tr><td>Alice</td><td>30</td></tr>
    <tr><td>Bob</td><td>25</td></tr>
  </tbody>
</table>
"""

let doc = parseHtml(html)
let table = selectOne(doc, "table")
let data = extractTable(table)

echo "Headers: ", data.headers
for row in data.rows:
  echo "Row: ", row

# Экспорт в CSV
let csv = tableToCsv(data)
writeFile("output.csv", csv)
```

---

### Работа с формами

```nim
import htmlparser

let html = """
<form action="/submit" method="POST">
  <input type="text" name="username">
  <input type="password" name="password">
  <select name="country">
    <option value="us">USA</option>
    <option value="ru">Russia</option>
  </select>
</form>
"""

let doc = parseHtml(html)
let form = selectOne(doc, "form")
let formData = extractForm(form)

echo "Action: ", formData.action
echo "Method: ", formData.command
for field in formData.fields:
  echo "Field: ", field.name, " (", field.fieldType, ")"
```

---

### Обработка "грязного" HTML

```nim
import htmlparser

# HTML с ошибками
let dirtyHtml = """
<div>
  <p>Unclosed paragraph
  <div>Nested div without closing p
  <span>Some text
</div>
"""

var errors: seq[string] = @[]
let doc = parseHtml(dirtyHtml, errors, defaultOptions())

echo "Parsing errors: ", errors.len
for err in errors:
  echo "  ", err

# Документ всё равно будет обработан корректно
echo "\nParsed document:"
echo prettyPrint(doc)
```

---

### Статистика документа

```nim
import htmlparser

let doc = loadHtml("page.html")

# Общая статистика
let stats = getStats(doc)
echo "Document statistics:"
for key, val in stats.pairs:
  echo "  ", key, ": ", val

# Подсчёт тегов
let tagCounts = countTags(doc)
echo "\nTag counts:"
for tag, count in tagCounts.pairs:
  echo "  ", tag, ": ", count
```

---

## Режимы работы

### Strict Mode (Строгий)

Строгий режим не исправляет ошибки автоматически и сообщает о всех проблемах.

```nim
var errors: seq[string] = @[]
let doc = loadHtml("page.html", errors, strictOptions())
# Все ошибки будут в errors
```

---

### Relaxed Mode (Расслабленный, по умолчанию)

Расслабленный режим автоматически исправляет распространённые ошибки HTML.

```nim
let doc = loadHtml("page.html", defaultOptions())
# Автоматическое закрытие тегов, исправление вложенности
```

---

### HTML5 Mode

HTML5 режим обеспечивает максимальную совместимость с современным HTML.

```nim
let doc = loadHtml("page.html", html5Options())
# Максимальная толерантность к ошибкам
```

---

## Зависимости

Модуль использует следующие стандартные библиотеки Nim:
- `std/strutils` - работа со строками
- `std/streams` - потоки ввода-вывода
- `std/parsexml` - базовый XML парсер
- `std/xmltree` - дерево XML узлов
- `std/unicode` - Unicode операции
- `std/strtabs` - строковые таблицы
- `std/tables` - хеш-таблицы
- `std/sets` - множества
- `std/sequtils` - утилиты для последовательностей
- `std/re` - регулярные выражения
- `std/options` - опциональные значения
- `std/syncio` - синхронный ввод-вывод

Также требуется модуль `htmlentities` для работы с HTML сущностями.

---

## Лицензия и авторство

**Версия:** 1.0 (2026-02-10)

Библиотека для автоматизированного разбора веб-ресурсов и извлечения данных (Automated data extraction).

---

## Заключение

Модуль `htmlparser.nim` предоставляет мощный инструментарий для работы с HTML документами любого качества. Благодаря трём режимам работы, CSS селекторам и богатому набору утилит, он подходит как для парсинга валидного HTML, так и для работы с "грязными" веб-страницами из реального интернета.

Рекомендуется использовать `defaultOptions()` для большинства задач и `html5Options()` для максимальной совместимости с современными веб-страницами.
