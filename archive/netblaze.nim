################################################################
##                      N E T B L A Z E
##    КОМПЛЕКС ФУНКЦИЙ ДЛЯ РАБОТЫ С СЕТЯМИ ПЕРЕДАЧИ ДАННЫХ; 
##  ИЗВЛЕЧЕНИЯ, ОБРАБОТКИ, МОДИФИКАЦИИ, СОХРАНЕНИЯ ИНФОРМАЦИИ
## 
## 
## Версия:   0.3
## Дата:     2026-02-10
## Автор:    github.com/Balans097
################################################################

# 0.3 — исправление ошибок, формирование единого модуля (2026-02-10)
# 0.2 — реализация ключевых функций библиотек 
#       htmlparser, nimbrowser (2026-02-09)
# 0.1 — начальная реализация библиотеки (2026-02-08)





import std/[strutils, xmltree, streams, tables, strtabs, unicode]
import src/htmlentitiesTypes







################################################################
#         Публичный API модуля HTMLENTITIES
################################################################

proc `$`*(tag: HtmlTag): string 
  ## Преобразует HtmlTag в строку
proc allLower(s: string): bool
  ## Проверяет, состоит ли строка только из строчных букв
proc toHtmlTag(s: string): HtmlTag
  ## Преобразует строку в HtmlTag
proc htmlTag*(n: XmlNode): HtmlTag
  ## Получает тег `n` как `HtmlTag
proc htmlTag*(s: string): HtmlTag
  ## Преобразует `s` в `HtmlTag`. Если `s` не является HTML-тегом, возвращается `tagUnknown`.
proc runeToEntity*(rune: Rune): string
  ## Преобразует Rune в эквивалент числовой HTML-сущности
proc entityToRune*(entity: string): Rune
  ## Преобразует имя HTML-сущности вроде `&Uuml;` или значения вроде `&#220;`
  ## или `&#x000DC;` в эквивалент UTF-8.
  ## Возвращается Rune(0), если имя сущности неизвестно






################################################################
#         Публичный API модуля HTMLPARSER
################################################################

# ==================== ТИПЫ ДАННЫХ ====================

type
  ParseMode* = enum
    ## Режимы разбора HTML
    pmStrict,      ## строгий режим (оригинальное поведение)
    pmRelaxed,     ## расслабленный режим (автоисправление)
    pmHtml5        ## HTML5-совместимый режим (максимальная толерантность)
  
  ParserOptions* = object
    ## Опции парсера
    mode*: ParseMode
    autoClose*: bool           ## автоматически закрывать теги
    fixNesting*: bool          ## исправлять неправильную вложенность
    removeInvalid*: bool       ## удалять невалидные теги
    preserveWhitespace*: bool  ## сохранять пробелы
    decodeEntities*: bool      ## декодировать HTML-сущности
    maxErrors*: int            ## максимальное количество ошибок для логирования

  HtmlParser* = object
    ## Расширенный HTML парсер
    options: ParserOptions
    errors: seq[string]
    openTags: seq[XmlNode]     ## стек открытых тегов

  TableData* = object
    ## Структура для хранения данных таблицы
    headers*: seq[string]
    rows*: seq[seq[string]]

  FormField* = object
    ## Описание поля формы
    name*: string
    fieldType*: string
    value*: string
    options*: seq[string]
  
  FormData* = object
    ## Структура для хранения данных формы
    action*: string
    command*: string
    fields*: seq[FormField]


# ==================== КОНСТАНТЫ ====================

# Список тегов, которые могут быть вложены сами в себя
const SelfNestingTags* = {tagDiv, tagSpan, tagUl, tagOl, tagTable, tagTbody}

# Расширенный список одиночных тегов (void elements в HTML5)
const ExtendedSingleTags* = SingleTags + {tagCommand, tagKeygen}

# Теги, которые автоматически закрывают предыдущие
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

# Теги, которые должны содержаться в определённых родителях
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


# ==================== ОПЦИИ ПАРСЕРА ====================

proc defaultOptions*(): ParserOptions
  ## Возвращает опции парсера по умолчанию (рекомендуется)
  ## 
  ## Параметры:
  ## - mode: pmRelaxed
  ## - autoClose: true
  ## - fixNesting: true
  ## - removeInvalid: false
  ## - preserveWhitespace: false
  ## - decodeEntities: true
  ## - maxErrors: 1000

proc strictOptions*(): ParserOptions
  ## Возвращает строгие опции парсера
  ## 
  ## Параметры:
  ## - mode: pmStrict
  ## - autoClose: false
  ## - fixNesting: false
  ## - removeInvalid: false
  ## - preserveWhitespace: true
  ## - decodeEntities: true
  ## - maxErrors: -1

proc html5Options*(): ParserOptions
  ## Возвращает опции для максимальной совместимости с HTML5
  ## 
  ## Параметры:
  ## - mode: pmHtml5
  ## - autoClose: true
  ## - fixNesting: true
  ## - removeInvalid: true
  ## - preserveWhitespace: false
  ## - decodeEntities: true
  ## - maxErrors: -1


# ==================== ФУНКЦИИ РАЗБОРА HTML ====================

proc parseHtml*(s: Stream, filename: string,
                errors: var seq[string], 
                options = defaultOptions()): XmlNode
  ## Парсит HTML из потока с настраиваемыми опциями
  ## 
  ## Параметры:
  ## - s: поток для чтения
  ## - filename: имя файла для сообщений об ошибках
  ## - errors: последовательность для сохранения ошибок парсинга
  ## - options: опции парсера
  ## 
  ## Возвращает: корневой узел XmlNode

proc parseHtml*(s: Stream, options = defaultOptions()): XmlNode
  ## Парсит HTML из потока, игнорируя ошибки
  ## 
  ## Параметры:
  ## - s: поток для чтения
  ## - options: опции парсера
  ## 
  ## Возвращает: корневой узел XmlNode

proc parseHtml*(html: string, options = defaultOptions()): XmlNode
  ## Парсит HTML из строки
  ## 
  ## Параметры:
  ## - html: HTML строка для парсинга
  ## - options: опции парсера
  ## 
  ## Возвращает: корневой узел XmlNode

proc loadHtml*(path: string, errors: var seq[string], 
               options = defaultOptions()): XmlNode
  ## Загружает и парсит HTML из файла с сохранением ошибок
  ## 
  ## Параметры:
  ## - path: путь к файлу
  ## - errors: последовательность для сохранения ошибок парсинга
  ## - options: опции парсера
  ## 
  ## Возвращает: корневой узел XmlNode
  ## Исключения: IOError если файл не может быть прочитан

proc loadHtml*(path: string, options = defaultOptions()): XmlNode
  ## Загружает и парсит HTML из файла, игнорируя ошибки
  ## 
  ## Параметры:
  ## - path: путь к файлу
  ## - options: опции парсера
  ## 
  ## Возвращает: корневой узел XmlNode
  ## Исключения: IOError если файл не может быть прочитан


# ==================== CSS-СЕЛЕКТОРЫ ====================

proc select*(node: XmlNode, selector: string): seq[XmlNode]
  ## Простой CSS селектор для поиска элементов
  ## 
  ## Поддерживаемые селекторы:
  ## - По тегу: "div", "p", "a"
  ## - По классу: ".classname", "div.classname"
  ## - По ID: "#idname", "div#idname"
  ## - По атрибуту: "[attr]", "[attr=value]"
  ## - Универсальный: "*"
  ## 
  ## Параметры:
  ## - node: узел для поиска
  ## - selector: CSS селектор
  ## 
  ## Возвращает: последовательность найденных узлов

proc selectOne*(node: XmlNode, selector: string): XmlNode
  ## Находит первый узел, соответствующий CSS селектору
  ## 
  ## Параметры:
  ## - node: узел для поиска
  ## - selector: CSS селектор
  ## 
  ## Возвращает: первый найденный узел или nil


# ==================== ИЗВЛЕЧЕНИЕ ДАННЫХ ====================

proc getText*(node: XmlNode, recursive = true): string
  ## Извлекает весь текст из узла
  ## 
  ## Параметры:
  ## - node: узел для извлечения текста
  ## - recursive: извлекать текст рекурсивно из всех потомков
  ## 
  ## Возвращает: текстовое содержимое узла

proc getTexts*(node: XmlNode): seq[string]
  ## Возвращает все текстовые фрагменты из узла
  ## 
  ## Параметры:
  ## - node: узел для извлечения текста
  ## 
  ## Возвращает: последовательность текстовых фрагментов (без пустых строк)

proc getAttribute*(node: XmlNode, attr: string, default = ""): string
  ## Получает значение атрибута узла или значение по умолчанию
  ## 
  ## Параметры:
  ## - node: узел
  ## - attr: имя атрибута
  ## - default: значение по умолчанию (если атрибут отсутствует)
  ## 
  ## Возвращает: значение атрибута или значение по умолчанию

proc getAttributes*(node: XmlNode): Table[string, string]
  ## Возвращает все атрибуты узла в виде таблицы
  ## 
  ## Параметры:
  ## - node: узел
  ## 
  ## Возвращает: таблица атрибутов (имя -> значение)


# ==================== НАВИГАЦИЯ ====================

proc parent*(node: XmlNode): XmlNode
  ## Возвращает родительский узел
  ## 
  ## Примечание: XmlNode не хранит ссылку на родителя,
  ## поэтому эта функция всегда возвращает nil
  ## 
  ## Параметры:
  ## - node: узел
  ## 
  ## Возвращает: всегда nil

proc nextSibling*(node: XmlNode, parent: XmlNode): XmlNode
  ## Возвращает следующий элемент-сосед
  ## 
  ## Параметры:
  ## - node: текущий узел
  ## - parent: родительский узел
  ## 
  ## Возвращает: следующий элемент-сосед или nil

proc previousSibling*(node: XmlNode, parent: XmlNode): XmlNode
  ## Возвращает предыдущий элемент-сосед
  ## 
  ## Параметры:
  ## - node: текущий узел
  ## - parent: родительский узел
  ## 
  ## Возвращает: предыдущий элемент-сосед или nil


# ==================== РАБОТА С ТАБЛИЦАМИ ====================

proc extractTable*(tableNode: XmlNode): TableData
  ## Извлекает данные из HTML таблицы
  ## 
  ## Параметры:
  ## - tableNode: узел с тегом <table>
  ## 
  ## Возвращает: структуру TableData с заголовками и строками

proc tableToCsv*(tbl: TableData): string
  ## Конвертирует таблицу в CSV формат
  ## 
  ## Параметры:
  ## - tbl: структура TableData
  ## 
  ## Возвращает: строка в формате CSV


# ==================== РАБОТА С ФОРМАМИ ====================

proc extractForm*(formNode: XmlNode): FormData
  ## Извлекает данные из HTML формы
  ## 
  ## Поддерживаемые типы полей:
  ## - <input> (text, password, email, и т.д.)
  ## - <textarea>
  ## - <select> (с опциями)
  ## 
  ## Параметры:
  ## - formNode: узел с тегом <form>
  ## 
  ## Возвращает: структуру FormData с полями формы


# ==================== РАБОТА СО ССЫЛКАМИ И ИЗОБРАЖЕНИЯМИ ====================

proc extractLinks*(node: XmlNode): seq[(string, string)]
  ## Извлекает все ссылки из документа
  ## 
  ## Параметры:
  ## - node: корневой узел для поиска
  ## 
  ## Возвращает: последовательность кортежей (href, текст ссылки)

proc extractImages*(node: XmlNode): seq[(string, string)]
  ## Извлекает все изображения из документа
  ## 
  ## Параметры:
  ## - node: корневой узел для поиска
  ## 
  ## Возвращает: последовательность кортежей (src, alt)


# ==================== ФИЛЬТРАЦИЯ И ПОИСК ====================

proc findAllByTag*(node: XmlNode, tag: string): seq[XmlNode]
  ## Находит все узлы с указанным тегом (без учёта регистра)
  ## 
  ## Параметры:
  ## - node: корневой узел для поиска
  ## - tag: имя тега
  ## 
  ## Возвращает: последовательность найденных узлов

proc findAllByClass*(node: XmlNode, className: string): seq[XmlNode]
  ## Находит все узлы с указанным классом
  ## 
  ## Параметры:
  ## - node: корневой узел для поиска
  ## - className: имя класса (без точки)
  ## 
  ## Возвращает: последовательность найденных узлов

proc findById*(node: XmlNode, id: string): XmlNode
  ## Находит узел по ID
  ## 
  ## Параметры:
  ## - node: корневой узел для поиска
  ## - id: значение атрибута id
  ## 
  ## Возвращает: найденный узел или nil

proc findAllByAttr*(node: XmlNode, attr: string, value = ""): seq[XmlNode]
  ## Находит все узлы с указанным атрибутом (и опционально значением)
  ## 
  ## Параметры:
  ## - node: корневой узел для поиска
  ## - attr: имя атрибута
  ## - value: значение атрибута (если пусто, ищет только наличие атрибута)
  ## 
  ## Возвращает: последовательность найденных узлов

proc findAllByText*(node: XmlNode, text: string, exact = false): seq[XmlNode]
  ## Находит все узлы, содержащие указанный текст
  ## 
  ## Параметры:
  ## - node: корневой узел для поиска
  ## - text: искомый текст
  ## - exact: точное совпадение (по умолчанию false - поиск подстроки)
  ## 
  ## Возвращает: последовательность найденных узлов


# ==================== СТАТИСТИКА И АНАЛИЗ ====================

proc countTags*(node: XmlNode): Table[string, int]
  ## Подсчитывает количество каждого тега в документе
  ## 
  ## Параметры:
  ## - node: корневой узел
  ## 
  ## Возвращает: таблица (тег -> количество)

proc getDepth*(node: XmlNode): int
  ## Вычисляет максимальную глубину дерева узлов
  ## 
  ## Параметры:
  ## - node: корневой узел
  ## 
  ## Возвращает: максимальная глубина вложенности

proc getStats*(node: XmlNode): Table[string, int]
  ## Возвращает статистику документа
  ## 
  ## Возвращаемые ключи:
  ## - "elements": количество элементов
  ## - "elements_with_attrs": количество элементов с атрибутами
  ## - "total_attrs": общее количество атрибутов
  ## - "text_nodes": количество текстовых узлов
  ## - "comments": количество комментариев
  ## - "depth": глубина дерева
  ## 
  ## Параметры:
  ## - node: корневой узел
  ## 
  ## Возвращает: таблица со статистикой


# ==================== МОДИФИКАЦИЯ ДОКУМЕНТА ====================

proc removeNode*(node: XmlNode, parent: XmlNode): bool
  ## Удаляет узел из родителя
  ## 
  ## Параметры:
  ## - node: узел для удаления
  ## - parent: родительский узел
  ## 
  ## Возвращает: true если удаление успешно

proc replaceNode*(oldNode: XmlNode, newNode: XmlNode, parent: var XmlNode): bool
  ## Заменяет один узел на другой
  ## 
  ## Параметры:
  ## - oldNode: узел для замены
  ## - newNode: новый узел
  ## - parent: родительский узел (var)
  ## 
  ## Возвращает: true если замена успешна

proc unwrap*(node: XmlNode, parent: XmlNode): bool
  ## Убирает обёртку узла, оставляя его содержимое
  ## 
  ## Параметры:
  ## - node: узел-обёртка для удаления
  ## - parent: родительский узел
  ## 
  ## Возвращает: true если операция успешна

proc wrap*(node: XmlNode, wrapperTag: string, parent: var XmlNode): bool
  ## Оборачивает узел новым элементом
  ## 
  ## Параметры:
  ## - node: узел для обёртывания
  ## - wrapperTag: имя тега обёртки
  ## - parent: родительский узел (var)
  ## 
  ## Возвращает: true если операция успешна


# ==================== ВАЛИДАЦИЯ ====================

proc hasRequiredAttrs*(node: XmlNode, attrs: seq[string]): bool
  ## Проверяет наличие всех требуемых атрибутов
  ## 
  ## Параметры:
  ## - node: проверяемый узел
  ## - attrs: список требуемых атрибутов
  ## 
  ## Возвращает: true если все атрибуты присутствуют

proc validateStructure*(node: XmlNode, rules: Table[string, seq[string]]): seq[string]
  ## Проверяет структуру документа по правилам
  ## 
  ## Параметры:
  ## - node: корневой узел
  ## - rules: таблица правил (тег -> список разрешённых дочерних тегов)
  ## 
  ## Возвращает: последовательность сообщений об ошибках валидации


# ==================== XPATH-ПОДОБНЫЕ ФУНКЦИИ ====================

proc findByPath*(node: XmlNode, path: string): seq[XmlNode]
  ## Простой XPath-подобный поиск элементов
  ## 
  ## Поддерживаемые пути:
  ## - "tag1/tag2/tag3": путь от родителя к потомкам
  ## - "//tag": рекурсивный поиск тега
  ## 
  ## Параметры:
  ## - node: корневой узел
  ## - path: путь для поиска
  ## 
  ## Возвращает: последовательность найденных узлов


# ==================== УТИЛИТЫ ДЛЯ ОЧИСТКИ ====================

proc removeEmptyTags*(node: XmlNode): XmlNode
  ## Удаляет пустые теги (без текста и без дочерних элементов)
  ## 
  ## Примечание: не удаляет одиночные теги (void elements)
  ## 
  ## Параметры:
  ## - node: узел для очистки
  ## 
  ## Возвращает: очищенный узел (модифицирует исходный)

proc removeComments*(node: XmlNode): XmlNode
  ## Удаляет все комментарии из документа
  ## 
  ## Параметры:
  ## - node: узел для очистки
  ## 
  ## Возвращает: узел без комментариев (модифицирует исходный)

proc sanitize*(node: XmlNode, allowedTags: seq[string]): XmlNode
  ## Оставляет только разрешённые теги (фильтрация XSS)
  ## 
  ## Параметры:
  ## - node: узел для санитизации
  ## - allowedTags: список разрешённых тегов (в нижнем регистре)
  ## 
  ## Возвращает: санитизированный узел


# ==================== ДОПОЛНИТЕЛЬНЫЕ УТИЛИТЫ ====================

proc prettyPrint*(node: XmlNode, indent = 0): string
  ## Красиво печатает HTML с отступами
  ## 
  ## Параметры:
  ## - node: узел для вывода
  ## - indent: начальный уровень отступа
  ## 
  ## Возвращает: отформатированная HTML строка

proc entityToUtf8*(entity: string): string
  ## Преобразует имя HTML-сущности в эквивалент UTF-8
  ## 
  ## Параметры:
  ## - entity: имя сущности (например, "Uuml" для &Uuml;)
  ##           или числовой код ("#220" или "#x000DC")
  ## 
  ## Возвращает: UTF-8 символ или пустая строка


# ==================== СТРОКОВЫЕ УТИЛИТЫ ====================

proc normalizeWhitespace*(text: string): string
  ## Нормализует пробельные символы (схлопывает множественные пробелы)
  ## 
  ## Параметры:
  ## - text: исходная строка
  ## 
  ## Возвращает: нормализованная строка

proc stripTags*(html: string): string
  ## Удаляет все HTML-теги из строки, оставляя только текст
  ## 
  ## Параметры:
  ## - html: HTML-строка
  ## 
  ## Возвращает: строка без тегов

proc decodeHtmlEntities*(text: string): string
  ## Декодирует все HTML-сущности в тексте
  ## 
  ## Параметры:
  ## - text: текст с HTML-сущностями
  ## 
  ## Возвращает: декодированный текст


# ==================== ИНФОРМАЦИОННЫЕ ФУНКЦИИ ====================

proc aboutHtmlParser*(): string
  ## Возвращает информацию о библиотеке htmlparser
  ## 
  ## Возвращает: многострочная строка с описанием библиотеки








include src/htmlentities
include src/htmlparser
include src/nimbrowser











when isMainModule:
  echo aboutNimBrowser()
  echo aboutHtmlParser()



# nim c -d:release nimblaze.nim
# nim c -d:release --app:gui --threads:on nimblaze.nim
# nim c -d:release -d:ssl --app:gui --threads:on nimblaze.nim




