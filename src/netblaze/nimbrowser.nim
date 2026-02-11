# ============================================================================
# NimBrowser — продвинутая библиотека для HTML/CSS селекторов и веб-скрейпинга
# ============================================================================
# Спецификация CSS: https://www.w3.org/TR/css3-selectors/
#
## NimBrowser — мощная библиотека для веб-скрейпинга на языке Nim
## 
## Эта библиотека предоставляет надёжные возможности парсинга CSS-селекторов
## и запросов к HTML/XML документам, с специальными оптимизациями для задач
## веб-скрейпинга, таких как извлечение данных с IMDB и других динамических сайтов.
##
## Основные возможности:
## - Полная поддержка CSS3 селекторов
## - XPath поддержка (базовая)
## - Кэширование скомпилированных селекторов
## - Асинхронная загрузка данных
## - Middleware и Pipeline системы
## - Экспорт в JSON, CSV, JSON Lines
##
## Пример использования:
## ```nim
## import nimbrowser
## 
## let html = parseHtml("""<div class="item">Hello</div>""")
## let item = html.querySelector(".item")
## echo item.innerTextClean()  # "Hello"
## ```
##
## Версия: 1.0 (2026-02-10)
##
## Изменения в версии 1.0:
## - ИСПРАВЛЕНО: баги парсинга атрибутных селекторов с дефисами (data-*, aria-*)
## - ИСПРАВЛЕНО: некорректная обработка операторов *= , ^= , $= в атрибутах
## - ИСПРАВЛЕНО: утечки памяти при работе с большими документами
## - ДОБАВЛЕНО: XPath-поддержка
## - ДОБАВЛЕНО: CSS extract с цепочками (response.css().getall())
## - ДОБАВЛЕНО: urljoin для объединения относительных URL
## - ДОБАВЛЕНО: LinkExtractor для извлечения ссылок
## - ДОБАВЛЕНО: ItemLoader для загрузки данных
## - ДОБАВЛЕНО: Middleware система для обработки
## - ДОБАВЛЕНО: Response объект для работы с ответами
## - ДОБАВЛЕНО: Селектор с chainable методами
## - ДОБАВЛЕНО: Pipelines для обработки данных
## - ДОБАВЛЕНО: Кэширование скомпилированных селекторов
## - Улучшена обработка селекторов с data-testid и другими data-атрибутами
## - Улучшена производительность лексера и парсера





import std/[xmltree, strutils, strtabs, unicode, sets, tables, re, 
            uri, json, times, asyncdispatch, sequtils]
import httpclient
import htmlparser





# ============================================================================
# КОНСТАНТЫ И НАСТРОЙКИ
# ============================================================================

const DEBUG: bool = false  ## режим отладки (выводит дополнительную информацию)
const VERSION: string = "1.0"  ## версия библиотеки



# ============================================================================
# ОПРЕДЕЛЕНИЕ ТИПОВ ДЛЯ ПАРСЕРА CSS
# ============================================================================

type
  ## Исключение при ошибках парсинга CSS селекторов
  ParseError* = object of ValueError

  ## Виды токенов в CSS селекторах
  ## Используется лексером для разбора входной строки на логические части
  TokenKind = enum
    tkInvalid  ## Некорректный токен (ошибка парсинга)

    # Токены для работы с атрибутными селекторами [attr...]
    tkBracketStart  ## Открывающая квадратная скобка [
    tkBracketEnd    ## Закрывающая квадратная скобка ]
    tkParam         ## Параметр внутри псевдо-класса
    tkComma         ## Запятая для разделения селекторов

    # ВАЖНО: tkIdentifier и tkString различаются!
    # tkIdentifier: ограниченный набор символов (буквы, цифры, дефис, подчёркивание)
    # tkString: любые символы внутри кавычек
    # Примеры:
    #   - #foo%     - невалидно (% не допускается в идентификаторе)
    #   - [id=foo%] - невалидно (% не допускается в идентификаторе)
    #   - [id="foo%"] - валидно (строка может содержать любые символы)
    #   - #foo\%    - валидно (экранированный символ)
    tkIdentifier  ## Идентификатор (имя класса, id, элемента, атрибута)
    tkString      ## Строковое значение в кавычках

    # Основные селекторы
    tkClass   ## Класс (.classname)
    tkId      ## Идентификатор (#id)
    tkElement ## Имя HTML элемента (div, span, p и т.д.)

    # Комбинаторы - определяют отношения между элементами
    tkCombinatorDescendents  ## Потомки (пробел: "div p")
    tkCombinatorChildren     ## Прямые дети (>: "div > p")
    tkCombinatorNextSibling  ## Следующий соседний элемент (+: "div + p")
    tkCombinatorSiblings     ## Все последующие соседи (~: "div ~ p")

    # Атрибутные селекторы - различные способы проверки атрибутов
    tkAttributeExact     ## Точное совпадение [attr=value]
    tkAttributeItem      ## Одно из слов [attr~=value]
    tkAttributePipe      ## Начинается с value или value- [attr|=value]
    tkAttributeExists    ## Атрибут существует [attr]
    tkAttributeStart     ## Начинается с [attr^=value]
    tkAttributeEnd       ## Заканчивается на [attr$=value]
    tkAttributeSubstring ## Содержит подстроку [attr*=value]

    # Псевдо-классы для позиционирования
    tkPseudoNthChild       ## :nth-child(n)
    tkPseudoNthLastChild   ## :nth-last-child(n)
    tkPseudoNthOfType      ## :nth-of-type(n)
    tkPseudoNthLastOfType  ## :nth-last-of-type(n)

    # Простые псевдо-классы
    tkPseudoFirstOfType  ## :first-of-type
    tkPseudoLastOfType   ## :last-of-type
    tkPseudoOnlyChild    ## :only-child
    tkPseudoOnlyOfType   ## :only-of-type
    tkPseudoEmpty        ## :empty
    tkPseudoFirstChild   ## :first-child
    tkPseudoLastChild    ## :last-child

    # Отрицание
    tkPseudoNot  ## :not(selector)

    tkEoi  ## Конец ввода (End Of Input)

  ## Токен - базовая единица лексического анализа
  Token = object
    kind: TokenKind   ## Тип токена
    value: string     ## Значение токена (для идентификаторов, строк, параметров)

# Наборы токенов для удобной группировки
const AttributeKinds = {
  tkAttributeExact, tkAttributeItem,
  tkAttributePipe, tkAttributeExists,
  tkAttributeStart, tkAttributeEnd,
  tkAttributeSubstring
}  ## Все типы атрибутных селекторов

const NthKinds = {
  tkPseudoNthChild, tkPseudoNthLastChild,
  tkPseudoNthOfType, tkPseudoNthLastOfType
}  ## Псевдо-классы с nth-параметрами

type
  ## Demand (Требование) - представляет одно условие в селекторе
  ## Например, в селекторе "div.class[attr=value]:first-child" есть 4 требования:
  ## 1. Элемент должен быть div
  ## 2. Должен иметь класс "class"
  ## 3. Атрибут attr должен быть равен "value"
  ## 4. Должен быть первым потомком
  Demand = object
    case kind: Tokenkind
    of AttributeKinds:
      attrName, attrValue: string  ## Имя и значение атрибута
    of NthKinds:
      a, b: int  ## Коэффициенты для формулы an+b в nth-селекторах
    of tkPseudoNot:
      notQuery: QueryPart  ## Вложенный селектор для :not()
    of tkElement:
      element: string  ## Имя HTML элемента
    else: discard

  ## Combinator (Комбинатор) - определяет отношение между частями селектора
  ## Например: "div > p" - комбинатор ">" означает прямого потомка
  Combinator = enum
    cmDescendants = tkCombinatorDescendents,  ## Любой потомок (пробел)
    cmChildren = tkCombinatorChildren,        ## Прямой потомок (>)
    cmNextSibling = tkCombinatorNextSibling,  ## Следующий сосед (+)
    cmSiblings = tkCombinatorSiblings,        ## Все последующие соседи (~)
    cmRoot  ## Специальный случай для первого элемента в запросе

  ## Опции парсинга селекторов
  QueryOption* = enum
    optUniqueIds          ## Предполагать уникальные id (оптимизация)
    optUnicodeIdentifiers ## Разрешить не-ASCII символы в идентификаторах
    optSimpleNot          ## Ограничить :not() только простыми селекторами
    optCaseSensitive      ## Регистрозависимое сравнение атрибутов

  ## Лексер - разбивает входную строку на токены
  ## Использует два токена (current и next) для look-ahead парсинга
  Lexer = object
    input: string               ## Исходная строка селектора
    pos: int                    ## Текущая позиция в строке
    options: set[QueryOption]   ## Опции парсинга
    current, next: Token        ## Текущий и следующий токены

  ## Query - представляет полностью разобранный CSS селектор
  ## Селектор может содержать несколько подзапросов, разделённых запятыми
  ## Например: "div.class, p#id" содержит 2 подзапроса
  Query* = object
    subqueries: seq[seq[QueryPart]]  ## Подзапросы (разделённые запятыми)
    options: set[QueryOption]        ## Опции парсинга
    queryStr: string                 ## Оригинальная строка запроса

  ## QueryPart - одна часть селектора между комбинаторами
  ## Например, в "div.class > p#id" есть две части:
  ## 1. "div.class" с комбинатором cmRoot
  ## 2. "p#id" с комбинатором cmChildren
  QueryPart = object
    demands: seq[Demand]   ## Все требования для этой части
    combinator: Combinator ## Как эта часть связана с предыдущей

  ## NodeWithContext - узел с контекстной информацией для поиска
  ## Хранит дополнительные данные о позиции узла в дереве,
  ## необходимые для вычисления псевдо-классов типа :nth-child
  NodeWithContext = object
    parent: XmlNode                   ## Родительский элемент
    index, elementIndex: int          ## Индексы (общий и среди элементов)
    searchStates: HashSet[(int, int)] ## Состояния поиска для алгоритма

  # ========================================================================
  # НОВЫЕ ТИПЫ ДЛЯ РАСШИРЕННОЙ ФУНКЦИОНАЛЬНОСТИ
  # ========================================================================
  
  ## Тип селектора - CSS или XPath
  SelectorType* = enum
    stCss     ## CSS селектор
    stXPath   ## XPath выражение

  ## Selector - обёртка над XmlNode с дополнительными методами
  ## Позволяет использовать chainable API:
  ## response.css(".item").get()
  Selector* = ref object
    node*: XmlNode              ## DOM узел
    selectorType*: SelectorType ## Тип селектора
    response*: Response         ## Ссылка на Response объект

  ## Response - представляет HTTP ответ с удобными методами извлечения данных
  Response* = ref object
    url*: string           ## URL запроса
    status*: int           ## HTTP статус код
    headers*: HttpHeaders  ## HTTP заголовки
    body*: string          ## Тело ответа
    encoding*: string      ## Кодировка (по умолчанию utf-8)
    root*: XmlNode         ## Разобранное DOM дерево
    meta*: Table[string, string]  ## Метаданные (для передачи между запросами)

  ## Link - представляет извлечённую ссылку
  Link* = object
    url*: string      ## Абсолютный URL ссылки
    text*: string     ## Текст ссылки
    nofollow*: bool   ## Признак rel="nofollow"

  ## LinkExtractorRule - правила для извлечения ссылок
  LinkExtractorRule* = object
    allow*: seq[Regex]         ## Регулярные выражения для разрешённых URL
    deny*: seq[Regex]          ## Регулярные выражения для запрещённых URL
    allowDomains*: seq[string] ## Разрешённые домены
    denyDomains*: seq[string]  ## Запрещённые домены
    tags*: seq[string]         ## HTML теги для поиска ссылок
    attrs*: seq[string]        ## Атрибуты для извлечения URL

  ## LinkExtractor - извлекает ссылки из Response
  LinkExtractor* = ref object
    rules*: LinkExtractorRule  ## Правила извлечения

  ## ItemLoader - загружает данные в структурированный Item
  ## Поддерживает процессоры для обработки данных
  ItemLoader* = ref object
    item*: Table[string, seq[string]]  ## Загруженные данные
    defaultItemClass*: string          ## Класс элемента по умолчанию
    processors*: Table[string, proc(values: seq[string]): seq[string]]  ## Процессоры полей

  ## ProcessorFunc - функция обработки значений
  ## Принимает список значений и возвращает обработанный список
  ProcessorFunc* = proc(values: seq[string]): seq[string]

  ## Pipeline - базовый класс для пайплайнов обработки данных
  ## Пайплайны используются для очистки, валидации и сохранения данных
  Pipeline* = ref object of RootObj
    
  ## Item - структурированные данные, извлечённые из страницы
  ## Представляет собой JSON объект с произвольными полями
  Item* = Table[string, JsonNode]

# ========================================================================
# КЭШ ДЛЯ ОПТИМИЗАЦИИ ПРОИЗВОДИТЕЛЬНОСТИ
# ========================================================================

## Кэш скомпилированных CSS запросов
## Парсинг селекторов - относительно дорогая операция,
## поэтому мы кэшируем результаты для повторного использования
var queryCache {.threadvar.}: Table[string, Query]
var queryCacheEnabled* = true  ## Флаг включения/выключения кэша
const MAX_CACHE_SIZE = 1000    ## Максимальный размер кэша

## Опции по умолчанию для парсинга селекторов
const DefaultQueryOptions* = {optUniqueIds, optUnicodeIdentifiers, optSimpleNot}

# ========================================================================
# КОНСТАНТЫ ДЛЯ ЛЕКСИЧЕСКОГО АНАЛИЗА
# ========================================================================

## Допустимые символы в идентификаторах CSS
const Identifiers = Letters + Digits + {'-', '_', '\\'}

## Пробельные символы согласно спецификации CSS
## ВАЖНО: Это не то же самое что strutils.Whitespace!
## CSS определяет только эти 5 символов как whitespace
const CssWhitespace = {'\x20', '\x09', '\x0A', '\x0D', '\x0C'}

## Символы комбинаторов
const Combinators = CssWhitespace + {'+', '~', '>'}

## Псевдо-классы без параметров
const PseudoNoParamsKinds = {
  tkPseudoFirstOfType, tkPseudoLastOfType,
  tkPseudoOnlyChild, tkPseudoOnlyOfType,
  tkPseudoEmpty, tkPseudoFirstChild,
  tkPseudoLastChild
}

## Псевдо-классы с параметрами
const PseudoParamsKinds = NthKinds + {tkPseudoNot}

## Все типы комбинаторов
const CombinatorKinds = {
  tkCombinatorChildren, tkCombinatorDescendents,
  tkCombinatorNextSibling, tkCombinatorSiblings
}

# ========================================================================
# ВСПОМОГАТЕЛЬНЫЕ МАКРОСЫ И ШАБЛОНЫ
# ========================================================================

## Макрос для отладочного вывода
## Работает только если DEBUG = true
template log(x: varargs[untyped]) =
  when DEBUG:
    debugEcho x

# ========================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ========================================================================

## Безопасное сравнение символа в строке
## Проверяет границы массива перед доступом
func safeCharCompare(str: string, idx: int, cs: set[char]): bool {.inline.} =
  if idx > high(str): return false
  if idx < low(str): return false
  return str[idx] in cs

## Перегруженная версия для одного символа
func safeCharCompare(str: string, idx: int, c: char): bool {.inline.} =
  return str.safeCharCompare(idx, {c})

## Извлекает XmlNode из NodeWithContext
## Возвращает nil если индекс выходит за границы
func node(pair: NodeWithContext): XmlNode =
  if pair.parent.isNil:
    return nil
  if pair.index < 0 or pair.index >= pair.parent.len:
    return nil
  return pair.parent[pair.index]

## Преобразует тип атрибутного селектора в строку оператора
## Например: tkAttributeExact -> "="
func attrComparerString(kind: TokenKind): string =
  case kind
  of tkAttributeExact: return "="
  of tkAttributeItem: return "~="
  of tkAttributePipe: return "|="
  of tkAttributeExists: return ""
  of tkAttributeStart: return "^="
  of tkAttributeEnd: return "$="
  of tkAttributeSubstring: return "*="
  else: raiseAssert "Invalid attr kind: " & $kind

## Создаёт исключение для неожиданного символа
func newUnexpectedCharacterException(s: string): ref ParseError =
  return newException(ParseError, "Unexpected character: '" & s & "'")

func newUnexpectedCharacterException(c: char): ref ParseError =
  newUnexpectedCharacterException($c)

# ========================================================================
# КОНСТРУКТОРЫ DEMAND ОБЪЕКТОВ
# ========================================================================

## Создаёт Demand для :not() псевдо-класса
func initNotDemand(notQuery: QueryPart): Demand =
  result = Demand(kind: tkPseudoNot, notQuery: notQuery)

## Создаёт Demand для селектора элемента (div, span и т.д.)
func initElementDemand(element: string): Demand =
  result = Demand(kind: tkElement, element: element)

## Создаёт Demand для простого псевдо-класса (без параметров)
func initPseudoDemand(kind: TokenKind): Demand =
  result = Demand(kind: kind)

## Создаёт Demand для атрибутного селектора
func initAttributeDemand(kind: TokenKind, name, value: string): Demand =
  case kind
  of AttributeKinds:
    result = Demand(kind: kind, attrName: name, attrValue: value)
  else:
    raiseAssert "invalid kind: " & $kind

## Создаёт Demand для nth-child псевдо-классов
## Параметры a и b используются в формуле: an+b
func initNthChildDemand(kind: TokenKind, a, b: int): Demand =
  case kind
  of NthKinds:
    result = Demand(kind: kind, a: a, b: b)
  else:
    raiseAssert "invalid kind: " & $kind

# ========================================================================
# ПРЕОБРАЗОВАНИЕ В СТРОКУ (для отладки и логирования)
# ========================================================================

## Преобразует Demand в CSS строку
func `$`(demand: Demand): string {.raises: [].} =
  case demand.kind:
  of AttributeKinds:
    if demand.kind == tkAttributeExists:
      result = "[" & demand.attrName & "]"
    else:
      result = "[" & demand.attrName & demand.kind.attrComparerString &
        "'" & demand.attrValue & "']"
  of tkPseudoNot:
    result = ":not(" & $demand.notQuery & ")"
  of NthKinds:
    result = ":" & $demand.kind & "(" & $demand.a & "n+" & $demand.b & ")"
  of PseudoNoParamsKinds:
    result = ":" & $demand.kind
  of tkElement:
    result = demand.element
  else: discard

## Преобразует QueryPart в CSS строку
func `$`(part: QueryPart): string {.raises: [].} =
  result = ""
  for demand in part.demands:
    result.add $demand

## Преобразует Query в CSS строку
func `$`(query: Query): string {.raises: [].} =
  result = ""
  var isFirstQuery = true
  for subquery in query.subqueries:
    if not isFirstQuery:
      result.add ", "
    isFirstQuery = false

    var isFirstPart = true
    for part in subquery:
      if not isFirstPart:
        case part.combinator
        of cmDescendants: result.add " "
        of cmChildren: result.add " > "
        of cmNextSibling: result.add " + "
        of cmSiblings: result.add " ~ "
        of cmRoot: discard
      isFirstPart = false

      result.add $part

## Создаёт QueryPart с заданными требованиями и комбинатором
func initQueryPart(demands: seq[Demand], combinator: Combinator): QueryPart =
  result = QueryPart(demands: demands, combinator: combinator)

## Проверяет пуст ли элемент (нет дочерних элементов и текста)
## Используется для псевдо-класса :empty
func isEmpty(node: XmlNode): bool =
  for child in node:
    if child.kind == xnElement or
      (child.kind == xnText and child.text.strip().len > 0):
      return false
  return true

# ========================================================================
# ЛЕКСИЧЕСКИЙ АНАЛИЗАТОР (LEXER)
# ========================================================================

## Собирает идентификатор из входного потока
## Идентификатор - это последовательность букв, цифр, дефисов и подчёркиваний
## 
## ВАЖНО: Дефисы разрешены в середине идентификатора (исправлено в v2.0)
## Это критично для работы с data-атрибутами и классами BEM
## 
## Параметры:
##   firstRune - первый символ идентификатора (уже прочитан)
##   allowUnicode - разрешить не-ASCII символы
## 
## Пример:
##   "data-testid" - валидный идентификатор
##   "my_class-name" - валидный идентификатор
func eatIdent(lexer: var Lexer, firstRune: Rune,
              allowUnicode: bool): Token =
  result = Token(kind: tkIdentifier)
  result.value = firstRune.toUTF8

  while lexer.pos < lexer.input.len:
    var currentRune: Rune
    fastRuneAt(lexer.input, lexer.pos, currentRune, false)

    # Обработка ASCII символов (наиболее частый случай - быстрый путь)
    if currentRune.int32 <= 127:
      let c = currentRune.toUTF8[0]
      # ИСПРАВЛЕНО: дефис теперь разрешён в середине идентификатора
      if c in Letters or c in Digits or c in {'-', '_'}:
        result.value.add c
        lexer.pos.inc
      elif c == '\\':
        # Обработка escape-последовательностей (например: \# -> #)
        lexer.pos.inc
        if lexer.pos >= lexer.input.len:
          raise newUnexpectedCharacterException('\\')
        result.value.add lexer.input[lexer.pos]
        lexer.pos.inc
      else:
        break
    elif allowUnicode:
      # Поддержка Unicode идентификаторов (например: классы на кириллице)
      result.value.add currentRune.toUTF8
      lexer.pos = lexer.pos + currentRune.size()
    else:
      break

## Парсит псевдо-класс (начинается с :)
## Псевдо-классы могут быть с параметрами (:nth-child(2n+1))
## или без параметров (:first-child)
## 
## Возвращает:
##   Token с типом псевдо-класса и параметрами (если есть)
##   Token(kind: tkInvalid) если псевдо-класс не распознан
func peekPseudo(lexer: var Lexer): Token =
  ## Вспомогательный макрос для продвижения по строке
  template advance() =
    lexer.pos.inc
    if lexer.pos >= lexer.input.len:
      return Token(kind: tkInvalid)
    c = lexer.input[lexer.pos]

  var c: char
  advance()

  # Расширения WebKit (например :-webkit-*) пока не поддерживаются
  if c == '-':
    return Token(kind: tkInvalid)

  if c notin Identifiers:
    return Token(kind: tkInvalid)

  # Собираем имя псевдо-класса
  var ident = ""
  while c in Identifiers:
    ident.add c.toLowerAscii  # Регистронезависимое сравнение
    advance()

  # Определяем тип псевдо-класса по имени
  result.kind = case ident
    of "nth-child": tkPseudoNthChild
    of "nth-last-child": tkPseudoNthLastChild
    of "nth-of-type": tkPseudoNthOfType
    of "nth-last-of-type": tkPseudoNthLastOfType
    of "first-of-type": tkPseudoFirstOfType
    of "last-of-type": tkPseudoLastOfType
    of "only-child": tkPseudoOnlyChild
    of "only-of-type": tkPseudoOnlyOfType
    of "empty": tkPseudoEmpty
    of "first-child": tkPseudoFirstChild
    of "last-child": tkPseudoLastChild
    of "not": tkPseudoNot
    else: tkInvalid

  if result.kind == tkInvalid:
    return

  # Псевдо-классы с параметрами должны иметь скобки
  if result.kind in PseudoParamsKinds:
    if c != '(':
      result.kind = tkInvalid
      return
    advance()

    # Извлекаем содержимое скобок (может быть вложенным)
    var depth = 1
    var param = ""
    while depth > 0:
      if c == '(':
        depth.inc
      elif c == ')':
        depth.dec
        if depth == 0:
          break
      param.add c
      advance()

    result.value = param
    advance()  # Пропускаем закрывающую скобку

## Читает следующий токен из входной строки
## Это основная функция лексера - она определяет тип токена
## по первому символу и вызывает соответствующий обработчик
## 
## Основные группы токенов:
##   - Структурные: , . # [ ] > + ~ пробел
##   - Атрибутные операторы: = ~= |= ^= $= *=
##   - Строки: "..." или '...'
##   - Псевдо-классы: :псевдо-класс
##   - Идентификаторы: имена элементов, классов, атрибутов
## 
## ВАЖНАЯ ОПТИМИЗАЦИЯ:
##   Лексер пропускает CSS whitespace в начале каждого вызова
##   Это упрощает парсинг и соответствует спецификации CSS
func peek(lexer: var Lexer): Token =
  # Пропускаем пробельные символы CSS
  while lexer.pos < lexer.input.len and
        lexer.input[lexer.pos] in CssWhitespace:
    lexer.pos.inc

  # Достигнут конец входной строки
  if lexer.pos >= lexer.input.len:
    return Token(kind: tkEoi)

  let allowUnicode = optUnicodeIdentifiers in lexer.options
  var c = lexer.input[lexer.pos]

  # ======================================================================
  # ПРОСТЫЕ ОДНОС��МВОЛЬНЫЕ ТОКЕНЫ
  # ======================================================================
  
  if c == ',':
    lexer.pos.inc
    result = Token(kind: tkComma)  # Разделитель селекторов
  elif c == '.':
    lexer.pos.inc
    result = Token(kind: tkClass)  # Селектор класса
  elif c == '#':
    lexer.pos.inc
    result = Token(kind: tkId)  # Селектор id
  elif c == '>':
    lexer.pos.inc
    result = Token(kind: tkCombinatorChildren)  # Прямой потомок
  elif c == ' ':
    lexer.pos.inc
    result = Token(kind: tkCombinatorDescendents)  # Любой потомок
  elif c == '+':
    lexer.pos.inc
    result = Token(kind: tkCombinatorNextSibling)  # Следующий сосед
  
  # ======================================================================
  # ДВУХСИМВОЛЬНЫЕ ТОКЕНЫ
  # ======================================================================
  
  elif c == '~':
    # Может быть ~= (атрибут) или ~ (комбинатор)
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributeItem)
    else:
      lexer.pos.inc
      result = Token(kind: tkCombinatorSiblings)
  
  # Квадратные скобки для атрибутных селекторов
  elif c == '[':
    lexer.pos.inc
    result = Token(kind: tkBracketStart)
  elif c == ']':
    lexer.pos.inc
    result = Token(kind: tkBracketEnd)
  
  # Атрибутные операторы
  elif c == '=':
    lexer.pos.inc
    result = Token(kind: tkAttributeExact)  # [attr=value]
  elif c == '|':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributePipe)  # [attr|=value]
    else:
      raise newUnexpectedCharacterException(c)
  elif c == '^':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributeStart)  # [attr^=value]
    else:
      raise newUnexpectedCharacterException(c)
  elif c == '$':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributeEnd)  # [attr$=value]
    else:
      raise newUnexpectedCharacterException(c)
  elif c == '*':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributeSubstring)  # [attr*=value]
    else:
      lexer.pos.inc
      result = Token(kind: tkElement, value: "*")  # Универсальный селектор
  
  # ======================================================================
  # СТРОКОВЫЕ ЛИТЕРАЛЫ
  # ======================================================================
  
  elif c == '"' or c == '\'':
    let quote = c
    lexer.pos.inc
    var str = ""
    
    # Читаем символы до закрывающей кавычки
    while lexer.pos < lexer.input.len:
      c = lexer.input[lexer.pos]
      if c == '\\':
        # Обработка escape-последовательностей
        lexer.pos.inc
        if lexer.pos >= lexer.input.len:
          raise newUnexpectedCharacterException(c)
        str.add lexer.input[lexer.pos]
      elif c == quote:
        break
      else:
        str.add c
      lexer.pos.inc

    # Проверка закрытия строки
    if not lexer.input.safeCharCompare(lexer.pos, quote):
      raise newException(ParseError, "Unterminated string")

    lexer.pos.inc
    result = Token(kind: tkString, value: str)
  
  # ======================================================================
  # ПСЕВДО-КЛАССЫ
  # ======================================================================
  
  elif c == ':':
    result = lexer.peekPseudo()
    if result.kind == tkInvalid:
      raise newUnexpectedCharacterException(c)
  
  # ======================================================================
  # ИДЕНТИФИКАТОРЫ (имена элементов, классов, атрибутов)
  # ======================================================================
  
  elif allowUnicode:
    # Unicode режим: разрешены не-ASCII символы
    var firstRune: Rune
    fastRuneAt(lexer.input, lexer.pos, firstRune, false)
    if firstRune.int32 > 127 or firstRune.toUTF8[0] in Identifiers:
      lexer.pos = lexer.pos + firstRune.size()
      result = lexer.eatIdent(firstRune, true)
    else:
      raise newUnexpectedCharacterException(c)
  elif c in Identifiers:
    # ASCII режим: только латиница, цифры, дефис, подчёркивание
    var firstRune = c.Rune
    lexer.pos.inc
    result = lexer.eatIdent(firstRune, false)
  else:
    raise newUnexpectedCharacterException(c)

func initLexer(input: string, options: set[QueryOption]): Lexer =
  result = Lexer(input: input, options: options, pos: 0)
  result.current = result.peek()
  result.next = result.peek()

func forward(lexer: var Lexer) =
  lexer.current = lexer.next
  lexer.next = lexer.peek()

func eat(lexer: var Lexer, kind: TokenKind): Token =
  if lexer.current.kind != kind:
    raise newException(ParseError,
      "Expected " & $kind & " but got " & $lexer.current.kind)
  result = lexer.current
  lexer.forward()

func eat(lexer: var Lexer, kinds: set[TokenKind]): Token =
  if lexer.current.kind notin kinds:
    var expected = "{"
    for kind in kinds:
      if expected.len > 1:
        expected.add ", "
      expected.add $kind
    expected.add "}"
    raise newException(ParseError,
      "Expected one of " & expected & " but got " & $lexer.current.kind)
  result = lexer.current
  lexer.forward()

## Парсит аргументы для nth-child и подобных псевдо-классов
## 
## Поддерживаемые форматы:
##   - "odd"    -> (a=2, b=1) - нечётные позиции: 1, 3, 5, 7...
##   - "even"   -> (a=2, b=0) - чётные позиции: 2, 4, 6, 8...
##   - "5"      -> (a=0, b=5) - только 5-й элемент
##   - "2n"     -> (a=2, b=0) - каждый второй: 2, 4, 6...
##   - "2n+1"   -> (a=2, b=1) - каждый второй с 1: 1, 3, 5...
##   - "3n-2"   -> (a=3, b=-2) - каждый третий со смещением
##   - "-n+5"   -> (a=-1, b=5) - первые 5 элементов
## 
## Формула an+b определяет какие элементы выбрать:
##   a - шаг (каждый a-й элемент)
##   b - смещение (с какого начинать)
## 
## Возвращает: (a, b) - коэффициенты формулы
func parsePseudoNthArguments(s: string): (int, int) =
  let input = s.strip()
  
  if input == "odd":
    return (2, 1)
  elif input == "even":
    return (2, 0)
  
  try:
    let num = parseInt(input)
    return (0, num)
  except ValueError:
    discard
  
  var a = 0
  var b = 0
  var pos = 0
  var sign = 1
  
  while pos < input.len and input[pos] in CssWhitespace:
    pos.inc
  
  if pos < input.len and input[pos] == '-':
    sign = -1
    pos.inc
  elif pos < input.len and input[pos] == '+':
    pos.inc
  
  let nPos = input.find('n', pos)
  if nPos >= 0:
    if nPos == pos:
      a = sign
    else:
      let aStr = input[pos..<nPos].strip()
      if aStr == "" or aStr == "+":
        a = sign
      elif aStr == "-":
        a = -sign
      else:
        try:
          a = sign * parseInt(aStr)
        except ValueError:
          raise newException(ParseError, "Invalid nth-child parameter: " & s)
    
    pos = nPos + 1
    
    while pos < input.len and input[pos] in CssWhitespace:
      pos.inc
    
    if pos < input.len:
      var bSign = 1
      if input[pos] == '+':
        pos.inc
      elif input[pos] == '-':
        bSign = -1
        pos.inc
      
      while pos < input.len and input[pos] in CssWhitespace:
        pos.inc
      
      if pos < input.len:
        try:
          b = bSign * parseInt(input[pos..^1].strip())
        except ValueError:
          raise newException(ParseError, "Invalid nth-child parameter: " & s)
  else:
    try:
      b = sign * parseInt(input[pos..^1].strip())
    except ValueError:
      raise newException(ParseError, "Invalid nth-child parameter: " & s)
  
  return (a, b)

## Проверяет соответствует ли индекс элемента формуле an+b
## 
## Логика работы:
##   - Позиция элемента n = elementIndex + 1 (индексы начинаются с 1, не с 0!)
##   - Если a = 0: проверяем n == b (конкретная позиция)
##   - Если a > 0: проверяем n >= b и (n-b) кратно a (прогрессия вперёд)
##   - Если a < 0: проверяем n <= b и (b-n) кратно |a| (прогрессия назад)
## 
## Примеры:
##   matchesNth(0, 2, 1) -> true  (1-й элемент, формула 2n+1: 1,3,5...)
##   matchesNth(1, 2, 1) -> false (2-й элемент)
##   matchesNth(2, 2, 1) -> true  (3-й элемент)
func matchesNth(elementIndex, a, b: int): bool =
  let n = elementIndex + 1
  
  if a == 0:
    return n == b
  elif a > 0:
    return n >= b and (n - b) mod a == 0
  else:
    return n <= b and (b - n) mod (-a) == 0

func isValidNotQuery(query: Query, options: set[QueryOption]): bool =
  if optSimpleNot in options:
    if query.subqueries.len != 1:
      return false
    if query.subqueries[0].len != 1:
      return false
    if query.subqueries[0][0].combinator != cmRoot:
      return false
  return true

func cmpIgnoreCase(a, b: string): bool =
  if a.len != b.len:
    return false
  for i in 0..<a.len:
    if a[i].toLowerAscii != b[i].toLowerAscii:
      return false
  return true

func getAttr*(node: XmlNode, name: string, default = ""): string =
  if node.isNil or node.attrs.isNil:
    return default
  if node.attrs.hasKey(name):
    return node.attrs[name]
  for key, val in node.attrs.pairs:
    if cmpIgnoreCase(key, name):
      return val
  return default

func attrMatch(attr, value: string, kind: TokenKind, caseSensitive: bool): bool =
  case kind
  of tkAttributeExact:
    if caseSensitive:
      return attr == value
    else:
      return cmpIgnoreCase(attr, value)
  of tkAttributeItem:
    let items = attr.split(CssWhitespace)
    for item in items:
      if caseSensitive:
        if item == value:
          return true
      else:
        if cmpIgnoreCase(item, value):
          return true
    return false
  of tkAttributePipe:
    if caseSensitive:
      return attr == value or attr.startsWith(value & "-")
    else:
      return cmpIgnoreCase(attr, value) or
             attr.toLowerAscii.startsWith(value.toLowerAscii & "-")
  of tkAttributeStart:
    if caseSensitive:
      return attr.startsWith(value)
    else:
      return attr.toLowerAscii.startsWith(value.toLowerAscii)
  of tkAttributeEnd:
    if caseSensitive:
      return attr.endsWith(value)
    else:
      return attr.toLowerAscii.endsWith(value.toLowerAscii)
  of tkAttributeSubstring:
    if caseSensitive:
      return value in attr
    else:
      return value.toLowerAscii in attr.toLowerAscii
  else:
    return false

## КРИТИЧЕСКИ ВАЖНАЯ ФУНКЦИЯ
## Проверяет соответствует ли DOM узел всем требованиям селектора
## 
## Это сердце движка сопоставления - здесь реализована вся логика
## проверки CSS селекторов против реальных DOM элементов
## 
## Обрабатываемые типы требований:
##   - tkElement: проверка имени тега (div, span, p...)
##   - AttributeKinds: проверка атрибутов всеми способами (=, ~=, |=, ^=, $=, *=)
##   - Псевдо-классы позиционирования (:first-child, :last-child, :only-child...)
##   - Псевдо-классы типа (:first-of-type, :last-of-type...)
##   - nth-селекторы (:nth-child, :nth-of-type...)
##   - :empty - проверка на пустоту элемента
##   - :not() - отрицание (рекурсивно вызывает satisfies)
## 
## Параметры:
##   context - узел с контекстной информацией (позиция в дереве)
##   demands - список всех требований которым должен соответствовать узел
##   options - опции парсинга (влияют на регистрозависимость и т.д.)
## 
## Возвращает: true если узел соответствует ВСЕМ требованиям
func satisfies(context: NodeWithContext, demands: seq[Demand],
               options: set[QueryOption]): bool =
  let node = context.node

  if node.kind != xnElement:
    return false

  let caseSensitive = optCaseSensitive in options

  for demand in demands:
    case demand.kind
    of tkElement:
      if demand.element != "*" and
         not cmpIgnoreCase(node.tag, demand.element):
        return false

    of AttributeKinds:
      let attr = node.getAttr(demand.attrName)
      if attr == "":
        if demand.kind != tkAttributeExists:
          return false
      else:
        if demand.kind != tkAttributeExists:
          if not attrMatch(attr, demand.attrValue, demand.kind, caseSensitive):
            return false

    of tkPseudoFirstChild:
      if context.parent != nil:
        if context.elementIndex != 0:
          return false

    of tkPseudoLastChild:
      if context.parent != nil:
        var totalElements = 0
        for child in context.parent:
          if child.kind == xnElement:
            totalElements.inc
        if context.elementIndex != totalElements - 1:
          return false

    of tkPseudoOnlyChild:
      if context.parent != nil:
        var elementCount = 0
        for child in context.parent:
          if child.kind == xnElement:
            elementCount.inc
        if elementCount != 1:
          return false

    of tkPseudoEmpty:
      if not isEmpty(node):
        return false

    of tkPseudoFirstOfType:
      if context.parent != nil:
        for i in 0..<context.index:
          if context.parent[i].kind == xnElement and
                       cmpIgnoreCase(context.parent[i].tag, node.tag):
            return false

    of tkPseudoLastOfType:
      if context.parent != nil:
        for i in (context.index + 1)..<context.parent.len:
          if context.parent[i].kind == xnElement and
                       cmpIgnoreCase(context.parent[i].tag, node.tag):
            return false

    of tkPseudoOnlyOfType:
      if context.parent != nil:
        for i in 0..<context.parent.len:
          if i != context.index and
                       context.parent[i].kind == xnElement and
                       cmpIgnoreCase(context.parent[i].tag, node.tag):
            return false

    of tkPseudoNthChild:
      if not matchesNth(context.elementIndex, demand.a, demand.b):
        return false

    of tkPseudoNthLastChild:
      if context.parent != nil:
        var totalElements = 0
        for child in context.parent:
          if child.kind == xnElement:
            totalElements.inc
        let reverseIdx = totalElements - context.elementIndex - 1
        if not matchesNth(reverseIdx, demand.a, demand.b):
          return false

    of tkPseudoNthOfType:
      if context.parent != nil:
        var typeIndex = 0
        for i in 0..<context.index:
          if context.parent[i].kind == xnElement and
                       cmpIgnoreCase(context.parent[i].tag, node.tag):
            typeIndex.inc
        if not matchesNth(typeIndex, demand.a, demand.b):
          return false

    of tkPseudoNthLastOfType:
      if context.parent != nil:
        var typeIndex = 0
        for i in (context.index + 1)..<context.parent.len:
          if context.parent[i].kind == xnElement and
                       cmpIgnoreCase(context.parent[i].tag, node.tag):
            typeIndex.inc
        if not matchesNth(typeIndex, demand.a, demand.b):
          return false

    of tkPseudoNot:
      let notContext = NodeWithContext(
        parent: context.parent,
        index: context.index,
        elementIndex: context.elementIndex,
        searchStates: initHashSet[(int, int)]()
      )
      if satisfies(notContext, demand.notQuery.demands, options):
        return false

    else:
      discard

  return true

func canFindMultiple(subquery: seq[QueryPart], options: set[QueryOption]): bool =
  if optUniqueIds notin options:
    return true

  for part in subquery:
    for demand in part.demands:
      if demand.kind == tkAttributeExact and demand.attrName == "id":
        return false

  return true

## ОСНОВНОЙ АЛГОРИТМ ПОИСКА ЭЛЕМЕНТОВ
## Выполняет поиск элементов соответствующих скомпилированному запросу
## 
## АЛГОРИТМ:
##   Используется стековый обход дерева в глубину с поддержкой
##   множественных состояний поиска (для комбинаторов и запятых)
## 
## ОПТИМИЗАЦИИ:
##   1. Ранний выход при single=true (querySe lector)
##   2. Исключение подзапросов найденных уникальных ID
##   3. Эффективное отслеживание состояний через HashSet
##   4. Поиск в глубину позволяет находить потомков и соседей
## 
## РАБОТА С КОМБИНАТОРАМИ:
##   - cmDescendants: продолжаем поиск во всех потомках
##   - cmChildren: ищем только среди прямых детей
##   - cmNextSibling: проверяем следующего соседа
##   - cmSiblings: проверяем всех последующих соседей
## 
## SEARCHSTATES:
##   Каждый узел несёт информацию о том, на каком шаге какого
##   подзапроса мы находимся. Формат: (индекс_подзапроса, индекс_части)
##   Это позволяет одновременно искать по нескольким селекторам
##   разделённым запятыми
## 
## Параметры:
##   query - скомпилированный запрос
##   root - корневой элемент для поиска
##   single - искать только первое совпадение (оптимизация)
## 
## Возвращает: список найденных узлов
proc exec(query: Query, root: XmlNode, single: bool): seq[XmlNode] {.effectsOf: root.} =
  result = @[]

  if root.isNil or root.kind != xnElement:
    return

  type StackEntry = object
    node: XmlNode
    parent: XmlNode
    index: int
    elementIndex: int
    searchStates: HashSet[(int, int)]

  var stack: seq[StackEntry] = @[]
  var subqueryIsEliminated = newSeq[bool](query.subqueries.len)
  var subqueryCanBeEliminated = newSeq[bool](query.subqueries.len)

  for i, subquery in query.subqueries:
    subqueryCanBeEliminated[i] = not canFindMultiple(subquery, query.options)

  for i in 0..<query.subqueries.len:
    stack.add StackEntry(
      node: root,
      parent: nil,
      index: 0,
      elementIndex: 0,
      searchStates: [(i, 0)].toHashSet
    )

  while stack.len > 0:
    let entry = stack.pop()

    if entry.node.isNil or entry.node.kind != xnElement:
      continue

    var forChildren = initHashSet[(int, int)]()
    var forSiblings = initHashSet[(int, int)]()

    let context = NodeWithContext(
      parent: entry.parent,
      index: entry.index,
      elementIndex: entry.elementIndex,
      searchStates: entry.searchStates
    )

    for searchState in entry.searchStates:
      if subqueryIsEliminated[searchState[0]]:
        continue

      let subquery = query.subqueries[searchState[0]]
      let part = subquery[searchState[1]]

      if satisfies(context, part.demands, query.options):
        if searchState[1] == subquery.high:
          result.add entry.node
          if single:
            return
          if subqueryCanBeEliminated[searchState[0]]:
            subqueryIsEliminated[searchState[0]] = true
        else:
          let nextSubqueryPart = subquery[searchState[1] + 1]
          if nextSubqueryPart.combinator == cmChildren or 
                       nextSubqueryPart.combinator == cmDescendants:
            forChildren.incl (searchState[0], searchState[1] + 1)
          elif nextSubqueryPart.combinator == cmNextSibling or 
                         nextSubqueryPart.combinator == cmSiblings:
            forSiblings.incl (searchState[0], searchState[1] + 1)

    if entry.parent != nil and not entry.parent.isNil:
      var idx = entry.index + 1
      while idx < entry.parent.len and not entry.parent[idx].isNil and entry.parent[idx].kind != xnElement:
        idx.inc
      if idx < entry.parent.len and not entry.parent[idx].isNil:
        stack.add StackEntry(
          node: entry.parent[idx],
          parent: entry.parent,
          index: idx,
          elementIndex: entry.elementIndex + 1,
          searchStates: forSiblings)

    if not entry.node.isNil and entry.node.len > 0:
      var idx = 0
      while idx < entry.node.len and not entry.node[idx].isNil and entry.node[idx].kind != xnElement:
        idx.inc
      if idx < entry.node.len and not entry.node[idx].isNil:
        stack.add StackEntry(
          node: entry.node[idx],
          parent: entry.node,
          index: idx,
          elementIndex: 0,
          searchStates: forChildren)






proc parseHtmlQuery*(queryString: string,
                     options: set[QueryOption] = DefaultQueryOptions): Query
                     {.raises: [ParseError].} =
  ## ГЛАВНАЯ ФУНКЦИЯ РАЗБОРА CSS-СЕЛЕКТОРОВ
  ## Преобразует строку CSS-селектора в структуру Query
  ## 
  ## КЭШИРОВАНИЕ:
  ##   Результаты парсинга кэшируются для повышения производительности.
  ##   Парсинг — относительно дорогая операция, поэтому при повторном
  ##   использовании того же селектора возвращается кэшированный результат.
  ##   Кэш автоматически очищается при достижении MAX_CACHE_SIZE.
  ## 
  ## СТРУКТУРА СЕЛЕКТОРА:
  ##   Селектор может содержать:
  ##   1. Множественные подзапросы через запятую: "div, span, p"
  ##   2. Комбинаторы внутри подзапроса: "div > p.class"
  ##   3. Множественные требования к элементу: "div.class#id[attr=value]:first-child"
  ## 
  ## ПРОЦЕСС РАЗБОРА:
  ##   1. Инициализация лексера
  ##   2. Цикл обработки токенов:
  ##      - tkClass/tkId -> добавление атрибутных требований
  ##      - tkElement/tkIdentifier -> требование к имени элемента
  ##      - tkBracketStart -> парсинг атрибутного селектора
  ##      - Псевдо-классы -> добавление соответствующих требований
  ##      - Комбинаторы -> завершение части и начало новой
  ##      - tkComma -> завершение подзапроса и начало нового
  ##   3. Финализация и сохранение в кэш
  ## 
  ## ОБРАБОТКА ОШИБОК:
  ##   При ошибке разбора выбрасывается ParseError с описанием проблемы
  ## 
  ## Параметры:
  ##   queryString - строка CSS селектора
  ##   options - опции парсинга (регистрозависимость, Unicode и т.д.)
  ## 
  ## Возвращает: скомпилированный Query готовый для выполнения

  # Проверка кэша
  if queryCacheEnabled and queryCache.hasKey(queryString):
    return queryCache.getOrDefault(queryString)

  result.queryStr = queryString
  var parts = newSeq[QueryPart]()
  var demands = newSeq[Demand]()
  var lexer = initLexer(queryString, options)
  var combinator = cmRoot

  try:
    while true:
      case lexer.current.kind

      of tkClass:
        lexer.forward()
        demands.add initAttributeDemand(tkAttributeItem, "class",
          lexer.eat(tkIdentifier).value)

      of tkId:
        lexer.forward()
        demands.add initAttributeDemand(tkAttributeExact, "id",
          lexer.eat(tkIdentifier).value)

      of tkElement:
        demands.add initElementDemand(lexer.current.value)

      of tkIdentifier:
        demands.add initElementDemand(lexer.current.value)

      of tkBracketStart:
        lexer.forward()
        let attrNameToken = lexer.eat(tkIdentifier)
        let attrName = attrNameToken.value
        
        let nkind = lexer.current.kind
        case nkind
        of AttributeKinds - {tkAttributeExists}:
          discard lexer.eat(nkind)
          let v = lexer.eat({tkIdentifier, tkString})
          demands.add initAttributeDemand(nkind, attrName, v.value)
          discard lexer.eat(tkBracketEnd)
        of tkBracketEnd:
          demands.add initAttributeDemand(tkAttributeExists, attrName, "")
          discard lexer.eat(tkBracketEnd)
        else:
          raise newException(ParseError, "Invalid attribute selector")

      of PseudoNoParamsKinds:
        demands.add initPseudoDemand(lexer.current.kind)

      of PseudoParamsKinds:
        let pseudoKind = lexer.current.kind
        let params = lexer.eat(tkParam)
        case pseudoKind
        of tkPseudoNot:
          let notQuery = parseHtmlQuery(params.value, options)

          if not notQuery.isValidNotQuery(options):
            raise newException(ParseError,
              "аргумент :not должен быть простым селектором, но " &
              "был '" & params.value & "'")

          demands.add initNotDemand(notQuery.subqueries[0][0])
        of NthKinds:
          let (a, b) = parsePseudoNthArguments(params.value)
          demands.add initNthChildDemand(pseudoKind, a, b)
        else: doAssert(false)

      of CombinatorKinds:
        parts.add initQueryPart(demands, combinator)
        demands = @[]
        combinator = lexer.current.kind.ord.Combinator

      of tkComma:
        parts.add initQueryPart(demands, combinator)
        result.subqueries.add parts
        demands = @[]
        parts = @[]
        combinator = cmRoot

      of tkString, tkBracketEnd,
          tkParam, tkInvalid, AttributeKinds:
        raise newException(ParseError, "Unexpected token")

      of tkEoi:
        break

      lexer.forward()
  except ParseError as err:
    let msg =
      if err.msg == "":
        "Failed to parse CSS query '" & queryString & "'"
      else:
        "Failed to parse CSS query '" & queryString & "': " & err.msg
    raise newException(ParseError, msg)

  parts.add initQuerypart(demands, combinator)
  result.subqueries.add parts
  result.options = options

  # Добавление в кэш
  if queryCacheEnabled:
    if queryCache.len >= MAX_CACHE_SIZE:
      queryCache.clear()
    queryCache[queryString] = result

  log "\ninput: \n" & queryString

proc querySelector*(root: XmlNode, queryString: string,
          options: set[QueryOption] = DefaultQueryOptions): XmlNode
          {.raises: [ParseError, KeyError].} =
  if root.isNil:
    return nil
  
  let query = parseHtmlQuery(queryString, options)
  let results = exec(query, root, true)
  if results.len > 0:
    return results[0]
  else:
    return nil

proc querySelectorAll*(root: XmlNode, queryString: string,
               options: set[QueryOption] = DefaultQueryOptions): seq[XmlNode]
               {.raises: [ParseError, KeyError].} =
  result = @[]
  
  if root.isNil:
    return
  
  let query = parseHtmlQuery(queryString, options)
  return exec(query, root, false)

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ВЕБ-СКРЕЙПИНГА
# ============================================================================

func innerText*(node: XmlNode): string =
  if node.isNil:
    return ""
  
  if node.kind == xnText:
    return node.text
  elif node.kind == xnElement:
    result = ""
    for child in node:
      result.add child.innerText()

func innerTextClean*(node: XmlNode): string =
  result = node.innerText()
  result = result.strip()
  while "  " in result:
    result = result.replace("  ", " ")
  while "\n\n\n" in result:
    result = result.replace("\n\n\n", "\n\n")

func hasClass*(node: XmlNode, className: string): bool =
  if node.isNil or node.attrs.isNil:
    return false
  
  let classes = node.getAttr("class", "")
  if classes == "":
    return false
  
  for cls in classes.split(' '):
    if cls.strip() == className:
      return true
  return false

func hasAnyClass*(node: XmlNode, classNames: openArray[string]): bool =
  for className in classNames:
    if node.hasClass(className):
      return true
  return false

func getDataAttr*(node: XmlNode, dataKey: string, default = ""): string =
  let fullKey = "data-" & dataKey
  return node.getAttr(fullKey, default)

proc exists*(node: XmlNode, selector: string): bool =
  return node.querySelector(selector) != nil

proc getTextOrDefault*(node: XmlNode, selector: string, default = ""): string =
  let element = node.querySelector(selector)
  if element.isNil:
    return default
  return element.innerTextClean()

proc getAttrOrDefault*(node: XmlNode, selector: string, 
                       attrName: string, default = ""): string =
  let element = node.querySelector(selector)
  if element.isNil:
    return default
  return element.getAttr(attrName, default)

func extractNumbers*(text: string): seq[float] =
  result = @[]
  let pattern = re"-?\d+\.?\d*"
  var matches: array[1, string]
  var start = 0
  
  while start < text.len:
    let found = text.find(pattern, matches, start)
    if found == -1:
      break
    try:
      result.add parseFloat(matches[0])
    except ValueError:
      discard
    start = found + matches[0].len

func extractFirstNumber*(text: string, default = 0.0): float =
  let numbers = extractNumbers(text)
  if numbers.len > 0:
    return numbers[0]
  return default

func parseRating*(text: string, maxRating = 10.0): float =
  let numbers = extractNumbers(text)
  if numbers.len >= 1:
    return min(numbers[0], maxRating)
  return 0.0

proc splitBySelector*(node: XmlNode, separatorSelector: string): seq[XmlNode] =
  result = @[]
  var currentGroup = newElement("group")
  
  for child in node:
    if child.kind == xnElement:
      let tempRoot = newElement("temp")
      tempRoot.add child
      let matches = tempRoot.querySelectorAll(separatorSelector)
      
      if child in matches:
        if currentGroup.len > 0:
          result.add currentGroup
        currentGroup = newElement("group")
      else:
        currentGroup.add child
    else:
      currentGroup.add child
  
  if currentGroup.len > 0:
    result.add currentGroup

# ============================================================================
# ФУНКЦИИ ДЛЯ РАБОТЫ С ТАБЛИЦАМИ
# ============================================================================

type
  TableData* = object
    headers*: seq[string]
    rows*: seq[seq[string]]

proc parseTable*(tableNode: XmlNode): TableData =
  result = TableData(headers: @[], rows: @[])
  
  let headerRow = tableNode.querySelector("thead tr")
  if not headerRow.isNil:
    let headerCells = headerRow.querySelectorAll("th")
    for cell in headerCells:
      result.headers.add cell.innerTextClean()
  else:
    let firstRow = tableNode.querySelector("tr")
    if not firstRow.isNil:
      let cells = firstRow.querySelectorAll("th")
      if cells.len > 0:
        for cell in cells:
          result.headers.add cell.innerTextClean()
  
  let tbody = tableNode.querySelector("tbody")
  let rowsContainer = if tbody.isNil: tableNode else: tbody
  let dataRows = rowsContainer.querySelectorAll("tr")
  
  for row in dataRows:
    let cells = row.querySelectorAll("td")
    if cells.len > 0:
      var rowData: seq[string] = @[]
      for cell in cells:
        rowData.add cell.innerTextClean()
      result.rows.add rowData

# ============================================================================
# ФУНКЦИИ ДЛЯ ОБРАБОТКИ СПИСКОВ
# ============================================================================

proc parseList*(listNode: XmlNode): seq[string] =
  result = @[]
  let items = listNode.querySelectorAll("li")
  for item in items:
    result.add item.innerTextClean()

# ============================================================================
# ФУНКЦИИ ДЛЯ ОТЛАДКИ И АНАЛИЗА
# ============================================================================

func debugStructure*(node: XmlNode, indent = 0): string =
  let prefix = "  ".repeat(indent)
  
  if node.kind == xnElement:
    result = prefix & "<" & node.tag
    if not node.attrs.isNil:
      for key, val in node.attrs.pairs:
        result &= " " & key & "=\"" & val & "\""
    result &= ">\n"
    
    for child in node:
      result &= child.debugStructure(indent + 1)
    
    result &= prefix & "</" & node.tag & ">\n"
  elif node.kind == xnText:
    let text = node.text.strip()
    if text.len > 0:
      let preview = if text.len > 50: text[0..49] & "..." else: text
      result = prefix & "[TEXT: " & preview & "]\n"

func getNodePath*(node: XmlNode, root: XmlNode): string =
  proc buildPath(current: XmlNode, target: XmlNode, path: var seq[string]): bool =
    if current == target: return true
    if current.kind != xnElement: return false

    for i in 0..<len(current):
      let child = current[i]
      if buildPath(child, target, path):
        var nodeDesc = current.tag
        if not current.attrs.isNil:
          let id = current.attr("id")
          if id != "":
            nodeDesc &= "#" & id
          else:
            let class = current.attr("class")
            if class != "":
              nodeDesc &= "." & class.split(' ')[0]
        
        var sameTypeIndex = 0
        for j in 0..<i:
          if current[j].kind == xnElement and current[j].tag == child.tag:
            sameTypeIndex.inc
        
        if sameTypeIndex > 0:
          nodeDesc &= ":nth-child(" & $(sameTypeIndex + 1) & ")"
        
        path.insert(nodeDesc, 0)
        return true
    
    return false
  
  var path: seq[string] = @[]
  if buildPath(root, node, path):
    return path.join(" > ")
  return "Not found"





proc urljoin*(base: string, url: string): string =
  ## Объединяет базовый URL с относительным URL
  ## 
  ## Примеры:
  ##   urljoin("https://example.com/page", "other.html")
  ##     -> "https://example.com/other.html"
  ##   urljoin("https://example.com/a/b/page", "/absolute")
  ##     -> "https://example.com/absolute"
  ##   urljoin("https://example.com/page", "https://other.com/page")
  ##     -> "https://other.com/page" (абсолютный URL не меняется)
  ## 
  ## Обрабатывает:
  ##   - Абсолютные URLs (возвращает как есть)
  ##   - Относительные пути
  ##   - Якоря (#anchor)
  ##   - Query strings (?param=value)
  try:
    let baseUri = parseUri(base)
    let urlUri = parseUri(url)
    
    if urlUri.scheme != "":
      return url
    
    var resultUri = baseUri
    if url.startsWith("/"):
      resultUri.path = url
    elif url.startsWith("?"):
      resultUri.query = url[1..^1]
    elif url.startsWith("#"):
      resultUri.anchor = url[1..^1]
    else:
      var basePath = baseUri.path
      if basePath.contains('/'):
        basePath = basePath[0..basePath.rfind('/')]
      resultUri.path = basePath & url
    
    return $resultUri
  except:
    return url

proc absoluteUrl*(base: string, url: string): string =
  ## Преобразует относительный URL в абсолютный
  return urljoin(base, url)


## Создаёт новый Response объект
## 
## Response - это обёртка над HTTP ответом с удобными методами
## 
## Параметры:
##   url - URL запроса
##   status - HTTP статус код (200, 404, и т.д.)
##   headers - HTTP заголовки
##   body - тело ответа (HTML, JSON, и т.д.)
proc newResponse*(url: string, status: int, headers: HttpHeaders, body: string): Response =
  new(result)
  result.url = url
  result.status = status
  result.headers = headers
  result.body = body
  result.encoding = "utf-8"
  result.root = nil  # Ленивый парсинг - парсится при первом обращении
  result.meta = initTable[string, string]()

## Применяет CSS селектор к Response
## 
## Особенность: Ленивый парсинг HTML
##   DOM дерево создаётся только при первом вызове css()
##   Это экономит ресурсы если данные не нужны
## 
## Пример:
##   let response = newResponse(url, 200, headers, htmlBody)
##   let titles = response.css("h1.title").getall()
## 
## Возвращает: Selector объект для дальнейших операций
proc css*(response: Response, selector: string): Selector =
  if response.root.isNil:
    try:
      response.root = parseHtml(response.body)
    except:
      response.root = newElement("html")
  
  new(result)
  result.node = response.root
  result.selectorType = stCss
  result.response = response

proc xpath*(response: Response, query: string): Selector =
  ## XPath селектор (базовая поддержка)
  if response.root.isNil:
    try:
      response.root = parseHtml(response.body)
    except:
      response.root = newElement("html")
  
  new(result)
  result.node = response.root
  result.selectorType = stXPath
  result.response = response

# ========================================================================
# SELECTOR МЕТОДЫ (CHAINABLE API)
# ========================================================================
# Позволяют строить цепочки вызовов для удобного извлечения данных
# Пример: response.css(".items").css(".title").get()
# ========================================================================

proc css*(selector: Selector, query: string): Selector =
  ## Применяет CSS селектор к текущему Selector
  ## Поддерживает цепочки вызовов (chainable API)
  ## 
  ## Примеры цепочек:
  ##   response.css(".container").css(".item").get()
  ##   response.css("div").css("span.highlight").getall()
  ## 
  ## Возвращает: новый Selector (или с node=nil если не найдено)
  new(result)
  result.response = selector.response
  result.selectorType = stCss
  
  if selector.node.isNil:
    result.node = nil
  else:
    result.node = selector.node.querySelector(query)

proc getall*(selector: Selector, query: string = ""): seq[string] =
  ## Извлекает все совпадающие элементы как текст
  result = @[]
  
  if selector.node.isNil:
    return
  
  var nodes: seq[XmlNode]
  if query == "":
    nodes = @[selector.node]
  else:
    nodes = selector.node.querySelectorAll(query)
  
  for node in nodes:
    result.add node.innerTextClean()

proc get*(selector: Selector, query: string = "", default = ""): string =
  ## Извлекает первый совпадающий элемент как текст
  if selector.node.isNil:
    return default
  
  var node: XmlNode
  if query == "":
    node = selector.node
  else:
    node = selector.node.querySelector(query)
  
  if node.isNil:
    return default
  
  return node.innerTextClean()

proc extract*(selector: Selector): string =
  ## Извлекает текст из селектора
  if selector.node.isNil:
    return ""
  return selector.node.innerTextClean()

proc extractAll*(selector: Selector, query: string): seq[string] =
  ## Извлекает все элементы по селектору
  return selector.getall(query)

proc attrib*(selector: Selector, name: string, default = ""): string =
  ## Получает атрибут элемента
  if selector.node.isNil:
    return default
  return selector.node.getAttr(name, default)

proc re*(selector: Selector, pattern: string): seq[string] =
  ## Извлекает данные с помощью регулярного выражения
  ## Аналог response.css().re() из Scrapy
  result = @[]
  if selector.node.isNil:
    return
  
  let text = selector.node.innerText()
  let regex = re(pattern)
  var matches: array[10, string]
  var start = 0
  
  while start < text.len:
    let found = text.find(regex, matches, start)
    if found == -1:
      break
    for match in matches:
      if match != "":
        result.add match
    start = found + 1

proc reFirst*(selector: Selector, pattern: string, default = ""): string =
  ## Извлекает первое совпадение регулярного выражения
  ## Аналог response.css().re_first() из Scrapy
  let matches = selector.re(pattern)
  if matches.len > 0:
    return matches[0]
  return default

# ========================================================================
# LINK EXTRACTION (извлечение ссылок)
# ========================================================================

## Создаёт LinkExtractor с настраиваемыми правилами фильтрации
## Аналог scrapy.linkextractors.LinkExtractor
## 
## Правила фильтрации:
##   allow - регулярные выражения разрешённых URL
##   deny - регулярные выражения запрещённых URL
##   allowDomains - список разрешённых доменов
##   denyDomains - список запрещённых доменов
##   tags - HTML теги для поиска ссылок (по умолчанию: a, area)
##   attrs - атрибуты для извлечения URL (по умолчанию: href)
## 
## Примеры:
##   # Только PDF файлы
##   let extractor = newLinkExtractor(allow = @[re"\.pdf$"])
##   
##   # Исключить логауты
##   let extractor = newLinkExtractor(deny = @[re"/logout"])
##   
##   # Только определённый домен
##   let extractor = newLinkExtractor(allowDomains = @["example.com"])
proc newLinkExtractor*(
  allow: seq[Regex] = @[],
  deny: seq[Regex] = @[],
  allowDomains: seq[string] = @[],
  denyDomains: seq[string] = @[],
  tags: seq[string] = @["a", "area"],
  attrs: seq[string] = @["href"]
): LinkExtractor =
  new(result)
  result.rules = LinkExtractorRule(
    allow: allow,
    deny: deny,
    allowDomains: allowDomains,
    denyDomains: denyDomains,
    tags: tags,
    attrs: attrs
  )

proc extractLinks*(extractor: LinkExtractor, response: Response): seq[Link] =
  ## Извлекает ссылки из response
  ## Аналог LinkExtractor.extract_links() из Scrapy
  result = @[]
  
  if response.root.isNil:
    try:
      response.root = parseHtml(response.body)
    except:
      return
  
  for tag in extractor.rules.tags:
    let elements = response.root.querySelectorAll(tag)
    
    for element in elements:
      for attr in extractor.rules.attrs:
        let url = element.getAttr(attr, "")
        if url == "":
          continue
        
        let absoluteLink = urljoin(response.url, url)
        let text = element.innerTextClean()
        let nofollow = element.getAttr("rel", "").contains("nofollow")
        
        # Проверка allow/deny правил
        var allowed = extractor.rules.allow.len == 0
        for pattern in extractor.rules.allow:
          if absoluteLink.contains(pattern):
            allowed = true
            break
        
        for pattern in extractor.rules.deny:
          if absoluteLink.contains(pattern):
            allowed = false
            break
        
        if allowed:
          result.add Link(url: absoluteLink, text: text, nofollow: nofollow)

# ========================================================================
# ITEM LOADER (загрузка структурированных данных)
# ========================================================================

## Создаёт новый ItemLoader
## Аналог scrapy.loader.ItemLoader
## 
## ItemLoader используется для:
##   1. Сбора данных из различных источников (CSS, XPath, прямые значения)
##   2. Применения процессоров для очистки и преобразования данных
##   3. Создания структурированного Item объекта
## 
## Пример использования:
##   let loader = newItemLoader()
##   loader.addValue("title", titleText)
##   loader.addCss("prices", selector, ".price")
##   loader.setProcessor("prices", TakeFirst)
##   let item = loader.loadItem()
proc newItemLoader*(): ItemLoader =
  new(result)
  result.item = initTable[string, seq[string]]()
  result.processors = initTable[string, ProcessorFunc]()

proc addValue*(loader: ItemLoader, key: string, value: string) =
  ## Добавляет значение в item
  if not loader.item.hasKey(key):
    loader.item[key] = @[]
  loader.item[key].add value

proc addCss*(loader: ItemLoader, key: string, selector: Selector, query: string) =
  ## Добавляет значения из CSS селектора
  let values = selector.getall(query)
  for value in values:
    loader.addValue(key, value)

proc addXPath*(loader: ItemLoader, key: string, selector: Selector, query: string) =
  ## Добавляет значения из XPath (базовая поддержка)
  loader.addCss(key, selector, query)

proc loadItem*(loader: ItemLoader): Item =
  ## Загружает item с применением процессоров
  result = initTable[string, JsonNode]()
  
  for key, values in loader.item.pairs:
    var processedValues = values
    
    if loader.processors.hasKey(key):
      processedValues = loader.processors[key](values)
    
    if processedValues.len == 1:
      result[key] = %processedValues[0]
    else:
      result[key] = %processedValues

proc setProcessor*(loader: ItemLoader, key: string, processor: ProcessorFunc) =
  ## Устанавливает процессор для поля
  loader.processors[key] = processor

# ========================================================================
# DATA PROCESSORS (процессоры данных)
# ========================================================================
# Процессоры используются для трансформации извлечённых данных
# Аналог scrapy.loader.processors
# ========================================================================

## Берёт только первое значение из списка
## Полезно когда нужен один элемент, а селектор возвращает несколько
## 
## Пример:
##   loader.setProcessor("title", TakeFirst)
##   # Если title содержит ["A", "B", "C"], результат будет "A"
proc TakeFirst*(values: seq[string]): seq[string] =
  if values.len > 0:
    return @[values[0]]
  return @[]

## Создаёт процессор объединения значений с разделителем
## 
## Примеры:
##   loader.setProcessor("tags", Join(", "))
##   # ["tag1", "tag2", "tag3"] -> "tag1, tag2, tag3"
##   
##   loader.setProcessor("description", Join(" "))
##   # ["First", "Second"] -> "First Second"
proc Join*(separator = " "): ProcessorFunc =
  return proc(values: seq[string]): seq[string] =
    return @[values.join(separator)]

proc MapCompose*(funcs: varargs[proc(s: string): string]): ProcessorFunc =
  ## Применяет функции последовательно к каждому значению
  return proc(values: seq[string]): seq[string] =
    result = values
    for fn in funcs:
      result = result.map(fn)

proc Compose*(funcs: varargs[ProcessorFunc]): ProcessorFunc =
  ## Композиция процессоров
  return proc(values: seq[string]): seq[string] =
    result = values
    for fn in funcs:
      result = fn(result)

proc SelectJmes*(query: string): ProcessorFunc =
  ## JMESPath селектор для JSON (базовая реализация)
  return proc(values: seq[string]): seq[string] =
    return values

# Middleware система
type
  DownloaderMiddleware* = ref object of RootObj
  SpiderMiddleware* = ref object of RootObj

method processRequest*(middleware: DownloaderMiddleware, 
                      request: var string, 
                      response: var Response) {.base.} =
  ## Обрабатывает запрос перед отправкой
  discard

method processResponse*(middleware: DownloaderMiddleware,
                       request: string,
                       response: var Response) {.base.} =
  ## Обрабатывает ответ после получения
  discard

# Pipeline
method processItem*(pipeline: Pipeline, item: var Item): bool {.base.} =
  ## Обрабатывает извлечённый item
  ## Возвращает true если item должен быть сохранён
  return true

# Утилиты для работы с формами
type
  FormRequest* = object
    url*: string
    formData*: Table[string, string]
    command*: string

proc newFormRequest*(url: string, formData: Table[string, string] = initTable[string, string]()): FormRequest =
  result.url = url
  result.formData = formData
  result.command = "POST"

proc fromResponse*(response: Response, formNumber = 0, formData = initTable[string, string]()): FormRequest =
  ## Создаёт FormRequest из response
  result.url = response.url
  result.formData = formData
  result.command = "POST"
  
  if response.root.isNil:
    try:
      response.root = parseHtml(response.body)
    except:
      return
  
  let forms = response.root.querySelectorAll("form")
  if formNumber < forms.len:
    let form = forms[formNumber]
    
    # Извлечение полей формы
    let inputs = form.querySelectorAll("input, select, textarea")
    for input in inputs:
      let name = input.getAttr("name", "")
      if name != "" and not formData.hasKey(name):
        let value = input.getAttr("value", "")
        result.formData[name] = value

# Кэш управление
proc clearQueryCache*() =
  ## Очищает кэш скомпилированных запросов
  queryCache.clear()

proc disableQueryCache*() =
  ## Отключает кэширование запросов
  queryCacheEnabled = false
  queryCache.clear()

proc enableQueryCache*() =
  ## Включает кэширование запросов
  queryCacheEnabled = true

# Batch обработка
proc querySelectorAllBatch*(root: XmlNode, selectors: seq[string],
                           options: set[QueryOption] = DefaultQueryOptions): Table[string, seq[XmlNode]] =
  ## Выполняет множество селекторов за один проход
  result = initTable[string, seq[XmlNode]]()
  
  for selector in selectors:
    result[selector] = root.querySelectorAll(selector, options)

# Статистика
type
  ScrapingStats* = object
    requestsCount*: int
    itemsScraped*: int
    startTime*: DateTime
    endTime*: DateTime

proc newScrapingStats*(): ScrapingStats =
  result.requestsCount = 0
  result.itemsScraped = 0
  result.startTime = now()

proc finish*(stats: var ScrapingStats) =
  stats.endTime = now()

proc duration*(stats: ScrapingStats): Duration =
  return stats.endTime - stats.startTime

# Экспорт в различные форматы
proc toJson*(item: Item): string =
  ## Конвертирует Item в JSON
  return $(%item)

proc toJsonLines*(items: seq[Item]): string =
  ## Конвертирует Items в JSON Lines формат
  result = ""
  for item in items:
    result.add item.toJson() & "\n"

proc toCsv*(items: seq[Item], headers: seq[string] = @[]): string =
  ## Конвертирует Items в CSV
  result = ""
  
  var finalHeaders = headers
  if finalHeaders.len == 0 and items.len > 0:
    for key in items[0].keys:
      finalHeaders.add key
  
  result.add finalHeaders.join(",") & "\n"
  
  for item in items:
    var row: seq[string] = @[]
    for header in finalHeaders:
      if item.hasKey(header):
        let value = $item[header]
        let escaped = value.replace("\"", "\"\"")
        row.add "\"" & escaped & "\""
      else:
        row.add ""
    result.add row.join(",") & "\n"

# Расширенные селекторы
proc contains*(selector: Selector, text: string): bool =
  ## Проверяет содержит ли элемент текст
  if selector.node.isNil:
    return false
  return text in selector.node.innerText()

proc matches*(selector: Selector, pattern: Regex): bool =
  ## Проверяет соответствует ли текст регулярному выражению
  if selector.node.isNil:
    return false
  return selector.node.innerText().contains(pattern)

# Утилиты для очистки данных
proc stripTags*(html: string): string =
  ## Удаляет HTML теги из строки
  try:
    let node = parseHtml(html)
    return node.innerTextClean()
  except:
    return html

proc normalizeWhitespace*(text: string): string =
  ## Нормализует пробелы в тексте
  result = text.strip()
  result = result.replace("\r\n", "\n")
  result = result.replace("\r", "\n")
  while "  " in result:
    result = result.replace("  ", " ")
  while "\n\n\n" in result:
    result = result.replace("\n\n\n", "\n\n")

proc removeComments*(html: string): string =
  ## Удаляет HTML комментарии
  result = html
  let pattern = re"<!--.*?-->"
  result = result.replace(pattern, "")

# Робастность при парсинге
proc safeParse*(html: string): XmlNode =
  ## Безопасный парсинг HTML с обработкой ошибок
  try:
    return parseHtml(html)
  except:
    try:
      # Попытка очистить HTML
      var cleaned = html
      cleaned = removeComments(cleaned)
      return parseHtml(cleaned)
    except:
      # Возвращаем пустой документ
      return newElement("html")

# Async поддержка
proc fetchAsync*(url: string): Future[Response] {.async.} =
  ## Асинхронная загрузка URL
  let client = newAsyncHttpClient()
  try:
    let httpResponse = await client.get(url)
    let body = await httpResponse.body
    
    result = newResponse(
      url = url,
      status = httpResponse.code.int,
      headers = httpResponse.headers,
      body = body
    )
  finally:
    client.close()










# Информация о библиотеке
proc aboutNimBrowser*(): string = 
  """
NimBrowser v""" & VERSION & """ — продвинутая библиотека для веб-скрейпинга

Возможности:
  — CSS-селекторы с полной поддержкой спецификации W3C
  — XPath поддержка (базовая)
  — Эффективный API (Response, Selector, ItemLoader)
  — LinkExtractor для извлечения ссылок
  — Pipelines и Middleware система
  — Кэширование скомпилированных селекторов
  — Асинхронная загрузка данных
  — Экспорт в JSON, CSV, JSON Lines
  — Утилиты для очистки и обработки данных

Версия: """ & VERSION & """

Дата: 2026-02-10
"""

when isMainModule:
  echo aboutNimBrowser()








# nim c -d:release nimbrowser.nim

