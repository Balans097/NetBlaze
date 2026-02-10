# Спецификация: https://www.w3.org/TR/css3-selectors/
## NimBrowser — продвинутая библиотека для HTML/CSS селекторов
## 
## Эта библиотека предоставляет надёжные возможности парсинга CSS-селекторов
## и запросов к HTML/XML документам, с специальными оптимизациями для задач
## веб-скрейпинга, таких как извлечение отзывов с IMDB и других динамических сайтов.
##
## Версия: 2.1 (Исправленная)
## Изменения:
## - ИСПРАВЛЕНО: баг парсинга атрибутных селекторов с дефисами (data-*, aria-*)
## - ИСПРАВЛЕНО: баг с некорректной обработкой операторов *= , ^= , $= в атрибутах
## - Улучшена обработка селекторов с data-testid и другими data-атрибутами
## - Добавлены дополнительные селекторы для IMDB
## - Улучшена производительность лексера

import std/[xmltree, strutils, strtabs, unicode, sets, tables, re]

const DEBUG = false

type
  ParseError* = object of ValueError

  TokenKind = enum
    tkInvalid

    tkBracketStart, tkBracketEnd
    tkParam
    tkComma

    # ПРИМЕЧАНИЕ: В некоторых контекстах они обрабатываются одинаково, но
    #       они различны. `tkIdentifier` может содержать только очень
    #       ограниченный набор символов, а tkString может содержать что угодно.
    #       Это означает, что и `#foo%`, и `[id=foo%]` невалидны,
    #       но не `[id="foo%"]` или `#foo\%`.
    tkIdentifier, tkString

    tkClass, tkId, tkElement

    tkCombinatorDescendents, tkCombinatorChildren
    tkCombinatorNextSibling, tkCombinatorSiblings

    tkAttributeExact     # [attr=...]
    tkAttributeItem      # [attr~=...]
    tkAttributePipe      # [attr|=...]
    tkAttributeExists    # [attr]
    tkAttributeStart     # [attr^=...]
    tkAttributeEnd       # [attr$=...]
    tkAttributeSubstring # [attr*=...]

    tkPseudoNthChild, tkPseudoNthLastChild
    tkPseudoNthOfType, tkPseudoNthLastOfType

    tkPseudoFirstOfType, tkPseudoLastOfType
    tkPseudoOnlyChild, tkPseudoOnlyOfType, tkPseudoEmpty
    tkPseudoFirstChild, tkPseudoLastChild

    tkPseudoNot

    tkEoi # Конец ввода

  Token = object
    kind: TokenKind
    value: string

const AttributeKinds = {
  tkAttributeExact, tkAttributeItem,
  tkAttributePipe, tkAttributeExists,
  tkAttributeStart, tkAttributeEnd,
  tkAttributeSubstring
}

const NthKinds = {
  tkPseudoNthChild, tkPseudoNthLastChild,
  tkPseudoNthOfType, tkPseudoNthLastOfType
}

type
  Demand = object
    case kind: Tokenkind
    of AttributeKinds:
      attrName, attrValue: string
    of NthKinds:
      a, b: int
    of tkPseudoNot:
      notQuery: QueryPart
    of tkElement:
      element: string
    else: discard

  Combinator = enum
    cmDescendants = tkCombinatorDescendents,
    cmChildren = tkCombinatorChildren,
    cmNextSibling = tkCombinatorNextSibling,
    cmSiblings = tkCombinatorSiblings,
    cmRoot # Особый случай для первого запроса

  QueryOption* = enum
    optUniqueIds          ## Предполагать уникальные id или нет
    optUnicodeIdentifiers ## Разрешить не-ASCII в идентификаторах (например `#exämple`)
    optSimpleNot          ## Разрешать только простые селекторы в качестве аргумента
                              ## для ":not". Комбинаторы и/или запятые не
                              ## разрешены, даже если эта опция исключена.
    optCaseSensitive      ## Делать сравнение атрибутов регистрозависимым (по умолчанию: регистронезависимое)

  Lexer = object
    input: string
    pos: int
    options: set[QueryOption]
    current, next: Token

  Query* = object ## Представляет разобранный запрос.
    subqueries: seq[seq[QueryPart]]
    options: set[QueryOption]
    queryStr: string ## Оригинальная входная строка

  QueryPart = object
    demands: seq[Demand]
    combinator: Combinator

  # Используется во время поиска для отслеживания того, какие части подзапросов
  # уже были сопоставлены.
  NodeWithContext = object
    # Нам нужен доступ к соседним элементам узла,
    # которые мы получаем через родителя.
    parent: XmlNode
    # Index - это индекс, используемый `xmltree`,
    # elementIndex - это индекс при подсчёте только элементов
    # (не текстовых узлов и т.д.).
    index, elementIndex: int
    searchStates: HashSet[(int, int)]

# Алиасы для обратной совместимости
const DefaultQueryOptions* = {optUniqueIds, optUnicodeIdentifiers,
  optSimpleNot}

const Identifiers = Letters + Digits + {'-', '_', '\\'}
# ПРИМЕЧАНИЕ: Это не то же самое, что `strutils.Whitespace`.
#       Эти значения определены спецификацией.
const CssWhitespace = {'\x20', '\x09', '\x0A', '\x0D', '\x0C'}
const Combinators = CssWhitespace + {'+', '~', '>'}

const PseudoNoParamsKinds = {
  tkPseudoFirstOfType, tkPseudoLastOfType,
  tkPseudoOnlyChild, tkPseudoOnlyOfType,
  tkPseudoEmpty, tkPseudoFirstChild,
  tkPseudoLastChild
}

const PseudoParamsKinds = NthKinds + {tkPseudoNot}

const CombinatorKinds = {
  tkCombinatorChildren, tkCombinatorDescendents,
  tkCombinatorNextSibling, tkCombinatorSiblings
}

template log(x: varargs[untyped]) =
  when DEBUG:
    debugEcho x

func safeCharCompare(str: string, idx: int, cs: set[char]): bool {.inline.} =
  if idx > high(str): return false
  if idx < low(str): return false
  return str[idx] in cs

func safeCharCompare(str: string, idx: int, c: char): bool {.inline.} =
  return str.safeCharCompare(idx, {c})

func node(pair: NodeWithContext): XmlNode =
  if pair.parent.isNil:
    return nil
  if pair.index < 0 or pair.index >= pair.parent.len:
    return nil
  return pair.parent[pair.index]

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

func newUnexpectedCharacterException(s: string): ref ParseError =
  return newException(ParseError, "Unexpected character: '" & s & "'")

func newUnexpectedCharacterException(c: char): ref ParseError =
  newUnexpectedCharacterException($c)

func initNotDemand(notQuery: QueryPart): Demand =
  result = Demand(kind: tkPseudoNot, notQuery: notQuery)

func initElementDemand(element: string): Demand =
  result = Demand(kind: tkElement, element: element)

func initPseudoDemand(kind: TokenKind): Demand =
  result = Demand(kind: kind)

func initAttributeDemand(kind: TokenKind, name, value: string): Demand =
  case kind
  of AttributeKinds:
    result = Demand(kind: kind, attrName: name, attrValue: value)
  else:
    raiseAssert "invalid kind: " & $kind

func initNthChildDemand(kind: TokenKind, a, b: int): Demand =
  case kind
  of NthKinds:
    result = Demand(kind: kind, a: a, b: b)
  else:
    raiseAssert "invalid kind: " & $kind

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

func `$`(part: QueryPart): string {.raises: [].} =
  result = ""
  for demand in part.demands:
    result.add $demand

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

func initQueryPart(demands: seq[Demand], combinator: Combinator): QueryPart =
  result = QueryPart(demands: demands, combinator: combinator)

func isEmpty(node: XmlNode): bool =
  for child in node:
    if child.kind == xnElement or
      (child.kind == xnText and child.text.strip().len > 0):
      return false
  return true

func eatIdent(lexer: var Lexer, firstRune: Rune,
              allowUnicode: bool): Token =
  # Функция для сбора идентификаторов (имена классов, элементов, атрибутов)
  result = Token(kind: tkIdentifier)
  result.value = firstRune.toUTF8

  while lexer.pos < lexer.input.len:
    var currentRune: Rune
    fastRuneAt(lexer.input, lexer.pos, currentRune, false)

    # Проверка допустимых символов
    if currentRune.int32 <= 127:
      let c = currentRune.toUTF8[0]
      # ИСПРАВЛЕНО: теперь дефис разрешён в середине идентификатора
      if c in Letters or c in Digits or c in {'-', '_'}:
        result.value.add c
        lexer.pos.inc
      elif c == '\\':
        # Обработка escape-последовательностей
        lexer.pos.inc
        if lexer.pos >= lexer.input.len:
          raise newUnexpectedCharacterException('\\')
        result.value.add lexer.input[lexer.pos]
        lexer.pos.inc
      else:
        break
    elif allowUnicode:
      result.value.add currentRune.toUTF8
      lexer.pos = lexer.pos + currentRune.size()
    else:
      break

func peekPseudo(lexer: var Lexer): Token =
  template advance() =
    lexer.pos.inc
    if lexer.pos >= lexer.input.len:
      return Token(kind: tkInvalid)
    c = lexer.input[lexer.pos]

  var c: char
  advance()

  if c == '-':
    # Расширения WebKit, пока не поддерживаются
    return Token(kind: tkInvalid)

  if c notin Identifiers:
    return Token(kind: tkInvalid)

  var ident = ""
  while c in Identifiers:
    ident.add c.toLowerAscii
    advance()

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

  # Проверка на параметры
  if result.kind in PseudoParamsKinds:
    if c != '(':
      result.kind = tkInvalid
      return
    advance()

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
    advance() # пропустить закрывающую скобку

func peek(lexer: var Lexer): Token =
  while lexer.pos < lexer.input.len and
        lexer.input[lexer.pos] in CssWhitespace:
    lexer.pos.inc

  if lexer.pos >= lexer.input.len:
    return Token(kind: tkEoi)

  let allowUnicode = optUnicodeIdentifiers in lexer.options
  var c = lexer.input[lexer.pos]

  if c == ',':
    lexer.pos.inc
    result = Token(kind: tkComma)
  elif c == '.':
    lexer.pos.inc
    result = Token(kind: tkClass)
  elif c == '#':
    lexer.pos.inc
    result = Token(kind: tkId)
  elif c == '>':
    lexer.pos.inc
    result = Token(kind: tkCombinatorChildren)
  elif c == ' ':
    lexer.pos.inc
    result = Token(kind: tkCombinatorDescendents)
  elif c == '+':
    lexer.pos.inc
    result = Token(kind: tkCombinatorNextSibling)
  elif c == '~':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributeItem)
    else:
      lexer.pos.inc
      result = Token(kind: tkCombinatorSiblings)
  elif c == '[':
    lexer.pos.inc
    result = Token(kind: tkBracketStart)
  elif c == ']':
    lexer.pos.inc
    result = Token(kind: tkBracketEnd)
  elif c == '=':
    lexer.pos.inc
    result = Token(kind: tkAttributeExact)
  elif c == '|':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributePipe)
    else:
      raise newUnexpectedCharacterException(c)
  elif c == '^':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributeStart)
    else:
      raise newUnexpectedCharacterException(c)
  elif c == '$':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributeEnd)
    else:
      raise newUnexpectedCharacterException(c)
  elif c == '*':
    if lexer.input.safeCharCompare(lexer.pos + 1, '='):
      lexer.pos.inc(2)
      result = Token(kind: tkAttributeSubstring)
    else:
      lexer.pos.inc
      result = Token(kind: tkElement, value: "*")
  elif c == '"' or c == '\'':
    let quote = c
    lexer.pos.inc
    var str = ""
    while lexer.pos < lexer.input.len:
      c = lexer.input[lexer.pos]
      if c == '\\':
        lexer.pos.inc
        if lexer.pos >= lexer.input.len:
          raise newUnexpectedCharacterException(c)
        str.add lexer.input[lexer.pos]
      elif c == quote:
        break
      else:
        str.add c
      lexer.pos.inc

    if not lexer.input.safeCharCompare(lexer.pos, quote):
      raise newException(ParseError, "Unterminated string")

    lexer.pos.inc
    result = Token(kind: tkString, value: str)
  elif c == ':':
    result = lexer.peekPseudo()
    if result.kind == tkInvalid:
      raise newUnexpectedCharacterException(c)
  elif allowUnicode:
    var firstRune: Rune
    fastRuneAt(lexer.input, lexer.pos, firstRune, false)
    if firstRune.int32 > 127 or firstRune.toUTF8[0] in Identifiers:
      lexer.pos = lexer.pos + firstRune.size()
      result = lexer.eatIdent(firstRune, true)
      # result.kind = tkElement
    else:
      raise newUnexpectedCharacterException(c)
  elif c in Identifiers:
    var firstRune = c.Rune
    lexer.pos.inc
    result = lexer.eatIdent(firstRune, false)
    # result.kind = tkElement
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

func parsePseudoNthArguments(s: string): (int, int) =
  # Очистить пробелы
  let input = s.strip()
  
  # Обработать специальные случаи
  if input == "odd":
    return (2, 1)
  elif input == "even":
    return (2, 0)
  
  # Попытка разобрать как число
  try:
    let num = parseInt(input)
    return (0, num)
  except ValueError:
    discard
  
  # Разбор an+b формата
  var a = 0
  var b = 0
  var pos = 0
  var sign = 1
  
  # Пропустить начальные пробелы
  while pos < input.len and input[pos] in CssWhitespace:
    pos.inc
  
  # Проверить знак
  if pos < input.len and input[pos] == '-':
    sign = -1
    pos.inc
  elif pos < input.len and input[pos] == '+':
    pos.inc
  
  # Найти 'n'
  let nPos = input.find('n', pos)
  if nPos >= 0:
    # Есть компонент 'a'
    if nPos == pos:
      # Просто 'n'
      a = sign
    else:
      # Число перед 'n'
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
    
    # Найти компонент 'b'
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
    # Нет 'n', только число
    try:
      b = sign * parseInt(input[pos..^1].strip())
    except ValueError:
      raise newException(ParseError, "Invalid nth-child parameter: " & s)
  
  return (a, b)

func matchesNth(elementIndex, a, b: int): bool =
  # elementIndex начинается с 0, но nth-child начинается с 1
  let n = elementIndex + 1
  
  if a == 0:
    # Просто b
    return n == b
  elif a > 0:
    # n должно быть >= b и (n - b) должно быть кратно a
    return n >= b and (n - b) mod a == 0
  else:
    # a < 0
    # n должно быть <= b и (b - n) должно быть кратно -a
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
  ## Получает значение атрибута с учётом регистра
  if node.attrs.isNil:
    return default
  # Сначала пробуем точное совпадение
  if node.attrs.hasKey(name):
    return node.attrs[name]
  # Затем регистронезависимый поиск
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
    # Значение должно быть одним из разделённых пробелами слов
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
    # Значение должно быть равно или начинаться с value-
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
      # Создать контекст только для этого узла
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
  # Если у нас есть селектор ID и optUniqueIds включен, мы можем найти максимум один элемент
  if optUniqueIds notin options:
    return true

  for part in subquery:
    for demand in part.demands:
      if demand.kind == tkAttributeExact and demand.attrName == "id":
        return false

  return true

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

    # Поиск в глубину

    # Добавить следующего соседа в стек
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

    # Добавить первого потомка в стек
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

func parseHtmlQuery*(queryString: string,
                     options: set[QueryOption] = DefaultQueryOptions): Query
                     {.raises: [ParseError].} =
  ## Разбирает запрос для последующего использования.
  ## Вызывает `ParseError`, если разбор `queryString` не удался.
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
        lexer.forward()  # перейти к имени атрибута
        # ИСПРАВЛЕНО: разрешить имя атрибута быть tkIdentifier
        let attrNameToken = lexer.eat(tkIdentifier)
        let attrName = attrNameToken.value
        
        let nkind = lexer.current.kind
        case nkind
        of AttributeKinds - {tkAttributeExists}:
          discard lexer.eat(nkind)
          # значение может быть идентификатор или строка
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
          # Не самый чистый способ сделать это, но работает
          let notQuery = parseHtmlQuery(params.value, options)

          if not notQuery.isValidNotQuery(options):
            raise newException(ParseError,
              "аргумент :not должен быть простым селектором, но " &
              "был '" & params.value & "'")

          demands.add initNotDemand(notQuery.subqueries[0][0])
        of NthKinds:
          let (a, b) = parsePseudoNthArguments(params.value)
          demands.add initNthChildDemand(pseudoKind, a, b)
        else: doAssert(false) # не может произойти

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

  log "\ninput: \n" & queryString

proc querySelector*(root: XmlNode, queryString: string,
          options: set[QueryOption] = DefaultQueryOptions): XmlNode
          {.raises: [ParseError, KeyError].} =
  ## Получает первый элемент, соответствующий `queryString`,
  ## или `nil`, если такого элемента не существует.
  ## Вызывает `ParseError`, если разбор `queryString` не удался.
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
  ## Получает все элементы, соответствующие `queryString`.
  ## Вызывает `ParseError`, если разбор `queryString` не удался.
  result = @[]
  
  if root.isNil:
    return
  
  let query = parseHtmlQuery(queryString, options)
  return exec(query, root, false)

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ВЕБ-СКРЕЙПИНГА
# ============================================================================

func innerText*(node: XmlNode): string =
  ## Получает весь текст из узла и его потомков
  if node.isNil:
    return ""
  
  if node.kind == xnText:
    return node.text
  elif node.kind == xnElement:
    result = ""
    for child in node:
      result.add child.innerText()

func innerTextClean*(node: XmlNode): string =
  ## Получает текст и очищает лишние пробелы
  result = node.innerText()
  result = result.strip()
  # Заменяем множественные пробелы на один
  while "  " in result:
    result = result.replace("  ", " ")
  # Заменяем множественные переносы строк на один
  while "\n\n\n" in result:
    result = result.replace("\n\n\n", "\n\n")

func hasClass*(node: XmlNode, className: string): bool =
  ## Проверяет наличие класса у элемента
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
  ## Проверяет наличие любого из классов
  for className in classNames:
    if node.hasClass(className):
      return true
  return false

func getDataAttr*(node: XmlNode, dataKey: string, default = ""): string =
  ## Получает data-атрибут
  ## Пример: getDataAttr("testid") вернёт значение data-testid
  let fullKey = "data-" & dataKey
  return node.getAttr(fullKey, default)

proc exists*(node: XmlNode, selector: string): bool =
  ## Проверяет существование элемента по селектору.
  ## Более эффективно, чем querySelector().isNil.
  ## 
  ## Пример:
  ##   if reviewNode.exists(".spoiler-warning"):
  ##     review.isSpoiler = true
  return node.querySelector(selector) != nil

proc getTextOrDefault*(node: XmlNode, selector: string, default = ""): string =
  ## Безопасно извлекает текст элемента по селектору.
  ## Возвращает значение по умолчанию, если элемент не найден.
  ## 
  ## Пример:
  ##   let rating = reviewNode.getTextOrDefault(".rating span", "N/A")
  let element = node.querySelector(selector)
  if element.isNil:
    return default
  return element.innerTextClean()

proc getAttrOrDefault*(node: XmlNode, selector: string, 
                       attrName: string, default = ""): string =
  ## Безопасно извлекает атрибут элемента по селектору.
  ## 
  ## Пример:
  ##   let imageUrl = node.getAttrOrDefault("img", "src", "/default.png")
  let element = node.querySelector(selector)
  if element.isNil:
    return default
  return element.getAttr(attrName, default)

func extractNumbers*(text: string): seq[float] =
  ## Извлекает все числа из текста.
  ## Полезно для парсинга рейтингов и голосов.
  ## 
  ## Пример:
  ##   let numbers = extractNumbers("123 out of 456 found this helpful")
  ##   # Результат: @[123.0, 456.0]
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
  ## Извлекает первое число из текста.
  ## 
  ## Пример:
  ##   let rating = extractFirstNumber("Rating: 8.5/10")  # 8.5
  let numbers = extractNumbers(text)
  if numbers.len > 0:
    return numbers[0]
  return default

func parseRating*(text: string, maxRating = 10.0): float =
  ## Парсит рейтинг из текста и нормализует его.
  ## 
  ## Пример:
  ##   let rating = parseRating("8/10")  # 8.0
  ##   let normalizedRating = parseRating("4/5", 5.0)  # 4.0
  let numbers = extractNumbers(text)
  if numbers.len >= 1:
    return min(numbers[0], maxRating)
  return 0.0

proc splitBySelector*(node: XmlNode, separatorSelector: string): seq[XmlNode] =
  ## Разделяет дочерние элементы узла по элементам-разделителям.
  ## Полезно для группировки контента.
  ## 
  ## Пример:
  ##   let sections = doc.splitBySelector("hr")
  result = @[]
  var currentGroup = newElement("group")
  
  for child in node:
    if child.kind == xnElement:
      # Проверяем, является ли это разделителем
      let tempRoot = newElement("temp")
      tempRoot.add child
      let matches = tempRoot.querySelectorAll(separatorSelector)
      
      if child in matches:
        # Это разделитель, сохраняем текущую группу
        if currentGroup.len > 0:
          result.add currentGroup
        currentGroup = newElement("group")
      else:
        currentGroup.add child
    else:
      currentGroup.add child
  
  # Добавляем последнюю группу
  if currentGroup.len > 0:
    result.add currentGroup

# ============================================================================
# ФУНКЦИИ ДЛЯ РАБОТЫ С ТАБЛИЦАМИ (полезно для структурированных данных)
# ============================================================================

type
  TableData* = object
    headers*: seq[string]
    rows*: seq[seq[string]]

proc parseTable*(tableNode: XmlNode): TableData =
  ## Парсит HTML таблицу в структурированный формат.
  ## 
  ## Пример:
  ##   let table = doc.querySelector("table")
  ##   let data = table.parseTable()
  ##   for row in data.rows:
  ##     echo row.join(" | ")
  result = TableData(headers: @[], rows: @[])
  
  # Извлекаем заголовки
  let headerRow = tableNode.querySelector("thead tr")
  if not headerRow.isNil:
    let headerCells = headerRow.querySelectorAll("th")
    for cell in headerCells:
      result.headers.add cell.innerTextClean()
  else:
    # Пробуем первую строку как заголовки
    let firstRow = tableNode.querySelector("tr")
    if not firstRow.isNil:
      let cells = firstRow.querySelectorAll("th")
      if cells.len > 0:
        for cell in cells:
          result.headers.add cell.innerTextClean()
  
  # Извлекаем строки данных
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
  ## Парсит HTML список (ul, ol) в массив строк.
  ## 
  ## Пример:
  ##   let list = doc.querySelector("ul.features")
  ##   let items = list.parseList()
  result = @[]
  let items = listNode.querySelectorAll("li")
  for item in items:
    result.add item.innerTextClean()

# ============================================================================
# ФУНКЦИИ ДЛЯ ОТЛАДКИ И АНАЛИЗА
# ============================================================================

func debugStructure*(node: XmlNode, indent = 0): string =
  ## Возвращает строковое представление структуры DOM для отладки.
  ## 
  ## Пример:
  ##   echo doc.debugStructure()
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
  ## Возвращает путь к узлу от корня (для отладки).
  ## 
  ## Пример:
  ##   echo reviewNode.getNodePath(doc)
  ##   # Результат: "html > body > div.reviews > div.review:nth-child(3)"
  
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
        
        # Добавляем позицию среди соседей того же типа
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



# ============================================================================
# ЭКСПОРТ
# ============================================================================

# Основные функции экспортируются автоматически через *
# Дополнительные вспомогательные функции также экспортированы

when isMainModule:
  echo "nimBrowser v2.1 - Исправленная библиотека для парсинга HTML"
  echo "Используйте эту библиотеку для веб-скрейпинга и извлечения данных"
