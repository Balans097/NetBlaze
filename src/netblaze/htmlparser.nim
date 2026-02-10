## Улучшенный HTML Parser для работы с „грязными“ HTML
##
## Возможности:
## - Толерантный парсинг с автоматическим исправлением ошибок
## - CSS-селекторы для поиска элементов
## - XPath-подобные селекторы
## - Автоматическое закрытие незакрытых тегов
## - Обработка некорректной вложенности
## - Извлечение текста, атрибутов
## - Навигация по DOM-дереву
## - Модификация структуры документа



import std/[strutils, streams, parsexml, xmltree, unicode, strtabs, 
            tables, sets, sequtils, re, options, syncio]
import htmlentities




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

# Опции парсера по умолчанию
proc defaultOptions*(): ParserOptions =
  ParserOptions(
    mode: pmRelaxed,
    autoClose: true,
    fixNesting: true,
    removeInvalid: false,
    preserveWhitespace: false,
    decodeEntities: true,
    maxErrors: 1000)

proc strictOptions*(): ParserOptions =
  ParserOptions(
    mode: pmStrict,
    autoClose: false,
    fixNesting: false,
    removeInvalid: false,
    preserveWhitespace: true,
    decodeEntities: true,
    maxErrors: -1)

proc html5Options*(): ParserOptions =
  ParserOptions(
    mode: pmHtml5,
    autoClose: true,
    fixNesting: true,
    removeInvalid: true,
    preserveWhitespace: false,
    decodeEntities: true,
    maxErrors: -1)

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

proc entityToUtf8*(entity: string): string =
  ## Преобразует имя HTML-сущности вроде `&Uuml;` или значения вроде `&#220;`
  ## или `&#x000DC;` в эквивалент UTF-8.
  let rune = entityToRune(entity)
  if rune.ord <= 0: result = ""
  else: result = toUTF8(rune)

proc addNode(father, son: XmlNode) =
  ## Добавляет сына к отцу, если сын не nil.
  if son != nil: add(father, son)

proc shouldAutoClose(currentTag: HtmlTag, newTag: HtmlTag): bool =
  ## Проверяет, должен ли currentTag автоматически закрываться при открытии newTag
  if currentTag in AutoClosingPairs:
    return newTag in AutoClosingPairs[currentTag]
  return false

proc needsParent(tag: HtmlTag): Option[set[HtmlTag]] =
  ## Возвращает набор возможных родительских тегов для данного тега
  if tag in ParentRequirements:
    return some(ParentRequirements[tag])
  return none(set[HtmlTag])

proc findOpenTag(parser: var HtmlParser, tag: string): int =
  ## Находит индекс открытого тега в стеке (-1 если не найден)
  for i in countdown(parser.openTags.high, 0):
    if cmpIgnoreCase(parser.openTags[i].tag, tag) == 0:
      return i
  return -1

proc closeOpenTags(parser: var HtmlParser, upTo: int, errors: var seq[string]) =
  ## Закрывает открытые теги до указанного индекса
  for i in countdown(parser.openTags.high, upTo):
    if parser.options.mode != pmStrict and errors.len < parser.options.maxErrors:
      errors.add("Auto-closing unclosed tag: <" & parser.openTags[i].tag & ">")
    discard parser.openTags.pop()

proc autoCloseIfNeeded(parser: var HtmlParser, newTag: HtmlTag, 
                       errors: var seq[string]): bool =
  ## Автоматически закрывает теги, если необходимо. Возвращает true если что-то закрыли.
  if parser.openTags.len == 0:
    return false
  
  let lastTag = parser.openTags[^1].htmlTag
  
  # Проверяем автозакрытие
  if shouldAutoClose(lastTag, newTag):
    if parser.options.autoClose:
      if errors.len < parser.options.maxErrors:
        errors.add("Auto-closing <" & $lastTag & "> before <" & $newTag & ">")
      discard parser.openTags.pop()
      return true
  
  return false

proc ensureProperParent(parser: var HtmlParser, tag: HtmlTag, 
                        currentNode: XmlNode, errors: var seq[string]) =
  ## Обеспечивает правильного родителя для тега
  let parentReq = needsParent(tag)
  if parentReq.isNone:
    return
  
  let requiredParents = parentReq.get
  var hasProperParent = false
  
  # Проверяем стек открытых тегов
  for openTag in parser.openTags:
    if openTag.htmlTag in requiredParents:
      hasProperParent = true
      break
  
  if not hasProperParent and parser.options.fixNesting:
    if errors.len < parser.options.maxErrors:
      errors.add("Tag <" & $tag & "> requires parent from " & $requiredParents)

proc parse(parser: var HtmlParser, x: var XmlParser, 
           errors: var seq[string]): XmlNode {.gcsafe.}

proc expected(x: var XmlParser, n: XmlNode): string =
  result = errorMsg(x, "</" & n.tag & "> expected")

template elemName(x: untyped): untyped = rawData(x)

template adderr(x: untyped) =
  if errors.len < 1000:  # Ограничиваем количество ошибок
    errors.add(x)

proc untilElementEnd(parser: var HtmlParser, x: var XmlParser, 
                     result: XmlNode, errors: var seq[string]) =
  ## Продолжает парсинг до конца элемента с улучшенной обработкой ошибок
  
  # Проверяем одиночные теги
  if result.htmlTag in ExtendedSingleTags:
    if x.kind != xmlElementEnd or cmpIgnoreCase(x.elemName, result.tag) != 0:
      return
  
  # Добавляем тег в стек открытых
  if parser.options.mode != pmStrict:
    parser.openTags.add(result)
  
  while true:
    case x.kind
    of xmlElementStart, xmlElementOpen:
      let newTag = htmlTag(x.elemName)
      
      # Автозакрытие при необходимости
      if parser.options.autoClose:
        while autoCloseIfNeeded(parser, newTag, errors):
          discard  # Продолжаем закрывать, пока нужно
      
      # Проверяем необходимость правильного родителя
      if parser.options.fixNesting:
        ensureProperParent(parser, newTag, result, errors)
      
      # Стандартная обработка автозакрытия для совместимости
      case result.htmlTag
      of tagP, tagInput, tagOption:
        if newTag in {tagLi, tagP, tagDt, tagDd, tagInput, tagOption}:
          if parser.options.mode == pmStrict:
            adderr(expected(x, result))
          if parser.options.mode != pmStrict:
            if parser.openTags.len > 0 and parser.openTags[^1] == result:
              discard parser.openTags.pop()
          break
      of tagDd, tagDt, tagLi:
        if newTag in {tagLi, tagDt, tagDd, tagInput, tagOption}:
          if parser.options.mode == pmStrict:
            adderr(expected(x, result))
          if parser.options.mode != pmStrict:
            if parser.openTags.len > 0 and parser.openTags[^1] == result:
              discard parser.openTags.pop()
          break
      of tagTd, tagTh:
        if newTag in {tagTr, tagTd, tagTh, tagTfoot, tagThead}:
          if parser.options.mode == pmStrict:
            adderr(expected(x, result))
          if parser.options.mode != pmStrict:
            if parser.openTags.len > 0 and parser.openTags[^1] == result:
              discard parser.openTags.pop()
          break
      of tagTr:
        if newTag == tagTr:
          if parser.options.mode == pmStrict:
            adderr(expected(x, result))
          if parser.options.mode != pmStrict:
            if parser.openTags.len > 0 and parser.openTags[^1] == result:
              discard parser.openTags.pop()
          break
      of tagOptgroup:
        if newTag in {tagOption, tagOptgroup}:
          if parser.options.mode == pmStrict:
            adderr(expected(x, result))
          if parser.options.mode != pmStrict:
            if parser.openTags.len > 0 and parser.openTags[^1] == result:
              discard parser.openTags.pop()
          break
      else: discard
      
      result.addNode(parse(parser, x, errors))
      
    of xmlElementEnd:
      let endTag = x.elemName
      
      if cmpIgnoreCase(endTag, result.tag) != 0:
        # Неправильный закрывающий тег
        if parser.options.mode == pmStrict:
          adderr(expected(x, result))
        
        # В relaxed режиме пытаемся найти соответствующий открытый тег
        if parser.options.mode != pmStrict:
          let idx = findOpenTag(parser, endTag)
          if idx >= 0:
            # Закрываем все теги до найденного
            closeOpenTags(parser, idx, errors)
            next(x)
            break
          else:
            # Игнорируем неожиданный закрывающий тег
            if errors.len < parser.options.maxErrors:
              errors.add("Ignoring unexpected closing tag: </" & endTag & ">")
            next(x)
            continue
        
        # В строгом режиме пытаемся восстановиться
        while x.kind in {xmlElementEnd, xmlWhitespace}:
          if x.kind == xmlElementEnd and cmpIgnoreCase(x.elemName, result.tag) == 0:
            break
          next(x)
      
      # Правильный закрывающий тег
      if parser.options.mode != pmStrict:
        if parser.openTags.len > 0 and parser.openTags[^1] == result:
          discard parser.openTags.pop()
      
      next(x)
      break
      
    of xmlEof:
      if parser.options.mode == pmStrict:
        adderr(expected(x, result))
      else:
        if errors.len < parser.options.maxErrors:
          errors.add("EOF reached with unclosed tag: <" & result.tag & ">")
      
      if parser.options.mode != pmStrict:
        if parser.openTags.len > 0 and parser.openTags[^1] == result:
          discard parser.openTags.pop()
      break
      
    else:
      result.addNode(parse(parser, x, errors))

proc parse(parser: var HtmlParser, x: var XmlParser, 
           errors: var seq[string]): XmlNode =
  ## Парсит следующий узел XML/HTML с улучшенной обработкой ошибок
  case x.kind
  of xmlComment:
    result = newComment(x.rawData)
    next(x)
  of xmlCharData, xmlWhitespace:
    if parser.options.preserveWhitespace or x.kind == xmlCharData:
      result = newText(x.rawData)
    next(x)
  of xmlPI, xmlSpecial:
    # Игнорируем инструкции обработки
    next(x)
  of xmlError:
    if parser.options.mode == pmStrict or errors.len < parser.options.maxErrors:
      adderr(errorMsg(x))
    next(x)
  of xmlElementStart:
    result = newElement(toLowerAscii(x.elemName))
    next(x)
    untilElementEnd(parser, x, result, errors)
  of xmlElementEnd:
    if parser.options.mode == pmStrict:
      adderr(errorMsg(x, "unexpected ending tag: " & x.elemName))
    else:
      # В relaxed режиме пытаемся обработать неожиданный закрывающий тег
      let idx = findOpenTag(parser, x.elemName)
      if idx >= 0 and errors.len < parser.options.maxErrors:
        errors.add("Found matching open tag for </" & x.elemName & ">")
    next(x)
  of xmlElementOpen:
    result = newElement(toLowerAscii(x.elemName))
    next(x)
    result.attrs = newStringTable()
    while true:
      case x.kind
      of xmlAttribute:
        result.attrs[x.rawData] = x.rawData2
        next(x)
      of xmlElementClose:
        next(x)
        break
      of xmlError:
        if parser.options.mode == pmStrict or errors.len < parser.options.maxErrors:
          adderr(errorMsg(x))
        next(x)
        break
      else:
        if parser.options.mode == pmStrict or errors.len < parser.options.maxErrors:
          adderr(errorMsg(x, "'>' expected"))
        next(x)
        break
    untilElementEnd(parser, x, result, errors)
  of xmlAttribute, xmlElementClose:
    if parser.options.mode == pmStrict or errors.len < parser.options.maxErrors:
      adderr(errorMsg(x, "<some_tag> expected"))
    next(x)
  of xmlCData:
    result = newCData(x.rawData)
    next(x)
  of xmlEntity:
    if parser.options.decodeEntities:
      var u = entityToUtf8(x.rawData)
      if u.len != 0: result = newText(u)
    else:
      result = newText("&" & x.rawData & ";")
    next(x)
  of xmlEof: discard

proc parseHtml*(s: Stream, filename: string,
                errors: var seq[string], 
                options = defaultOptions()): XmlNode =
  ## Парсит HTML из потока с настраиваемыми опциями
  var parser = HtmlParser(options: options, errors: @[], openTags: @[])
  var x: XmlParser
  open(x, s, filename, {reportComments, reportWhitespace, 
                        allowUnquotedAttribs, allowEmptyAttribs})
  next(x)
  
  # Пропускаем DOCTYPE
  if x.kind == xmlSpecial: next(x)
  
  result = newElement("document")
  result.addNode(parse(parser, x, errors))
  
  while x.kind != xmlEof:
    var oldPos = x.bufpos
    result.addNode(parse(parser, x, errors))
    if x.bufpos == oldPos:
      next(x)  # Принудительный прогресс
  
  # Закрываем все оставшиеся открытые теги
  if parser.options.autoClose and parser.openTags.len > 0:
    if errors.len < parser.options.maxErrors:
      for tag in parser.openTags:
        errors.add("Auto-closing unclosed tag at EOF: <" & tag.tag & ">")
  
  close(x)
  
  if result.len == 1:
    result = result[0]

proc parseHtml*(s: Stream, options = defaultOptions()): XmlNode =
  ## Парсит HTML из потока, игнорируя ошибки
  var errors: seq[string] = @[]
  result = parseHtml(s, "unknown_html_doc", errors, options)

proc parseHtml*(html: string, options = defaultOptions()): XmlNode =
  ## Парсит HTML из строки
  parseHtml(newStringStream(html), options)

proc loadHtml*(path: string, errors: var seq[string], 
               options = defaultOptions()): XmlNode =
  ## Загружает и парсит HTML из файла
  var s = newFileStream(path, fmRead)
  if s == nil: raise newException(IOError, "Unable to read file: " & path)
  result = parseHtml(s, path, errors, options)

proc loadHtml*(path: string, options = defaultOptions()): XmlNode =
  ## Загружает и парсит HTML из файла, игнорируя ошибки
  var errors: seq[string] = @[]
  result = loadHtml(path, errors, options)

# ==================== CSS СЕЛЕКТОРЫ ====================

proc matchesClass(node: XmlNode, className: string): bool =
  ## Проверяет, есть ли у узла указанный класс
  if node.kind != xnElement or node.attrs == nil:
    return false
  if not node.attrs.hasKey("class"):
    return false
  let classes = node.attrs["class"].split(Whitespace)
  return className in classes

proc matchesId(node: XmlNode, id: string): bool =
  ## Проверяет, есть ли у узла указанный ID
  if node.kind != xnElement or node.attrs == nil:
    return false
  return node.attrs.hasKey("id") and node.attrs["id"] == id

proc matchesAttribute(node: XmlNode, attr: string, value = ""): bool =
  ## Проверяет наличие атрибута (и опционально его значение)
  if node.kind != xnElement or node.attrs == nil:
    return false
  if value == "":
    return node.attrs.hasKey(attr)
  else:
    return node.attrs.hasKey(attr) and node.attrs[attr] == value

proc findAllNodes(node: XmlNode, tag: string, 
                  class_name = "", id = "", 
                  attr = "", attrVal = "",
                  recursive = true): seq[XmlNode] =
  ## Универсальный поиск узлов с различными фильтрами
  result = @[]
  
  if node.kind != xnElement:
    return
  
  # Проверяем текущий узел
  var matches = true
  
  if tag != "" and tag != "*":
    matches = matches and cmpIgnoreCase(node.tag, tag) == 0
  
  if class_name != "":
    matches = matches and matchesClass(node, class_name)
  
  if id != "":
    matches = matches and matchesId(node, id)
  
  if attr != "":
    matches = matches and matchesAttribute(node, attr, attrVal)
  
  if matches:
    result.add(node)
  
  # Рекурсивно ищем в дочерних узлах
  if recursive:
    for child in node:
      result.add(findAllNodes(child, tag, class_name, id, attr, attrVal, recursive))

proc select*(node: XmlNode, selector: string): seq[XmlNode] =
  ## Простой CSS селектор (базовая поддержка)
  ## Поддерживает:
  ## - Селектор по тегу: "div"
  ## - Селектор по классу: ".classname"
  ## - Селектор по ID: "#idname"
  ## - Селектор по атрибуту: "[attr]" или "[attr=value]"
  ## - Комбинации: "div.classname", "div#idname"
  result = @[]
  
  var tag = ""
  var className = ""
  var id = ""
  var attr = ""
  var attrVal = ""
  
  var s = selector.strip()
  
  # Простой парсинг селектора
  if s.startsWith("#"):
    id = s[1..^1]
    tag = "*"
  elif s.startsWith("."):
    className = s[1..^1]
    tag = "*"
  elif s.contains("."):
    let parts = s.split(".", maxsplit=1)
    tag = parts[0]
    className = parts[1]
  elif s.contains("#"):
    let parts = s.split("#", maxsplit=1)
    tag = parts[0]
    id = parts[1]
  elif s.startsWith("[") and s.endsWith("]"):
    let attrStr = s[1..^2]
    if attrStr.contains("="):
      let parts = attrStr.split("=", maxsplit=1)
      attr = parts[0].strip()
      attrVal = parts[1].strip(chars={'"', '\''})
    else:
      attr = attrStr.strip()
    tag = "*"
  else:
    tag = s
  
  result = findAllNodes(node, tag, className, id, attr, attrVal)

proc selectOne*(node: XmlNode, selector: string): XmlNode =
  ## Находит первый узел, соответствующий селектору
  let results = select(node, selector)
  if results.len > 0:
    return results[0]
  return nil

# ==================== ИЗВЛЕЧЕНИЕ ДАННЫХ ====================

proc getText*(node: XmlNode, recursive = true): string =
  ## Извлекает весь текст из узла
  result = ""
  if node.kind == xnText or node.kind == xnCData:
    return node.text
  if node.kind == xnElement:
    for child in node:
      if recursive:
        result.add(getText(child, recursive))
      elif child.kind in {xnText, xnCData}:
        result.add(child.text)

proc getTexts*(node: XmlNode): seq[string] =
  ## Возвращает все текстовые фрагменты из узла
  result = @[]
  if node.kind == xnText or node.kind == xnCData:
    let text = node.text.strip()
    if text.len > 0:
      result.add(text)
  elif node.kind == xnElement:
    for child in node:
      result.add(getTexts(child))

proc getAttribute*(node: XmlNode, attr: string, default = ""): string =
  ## Получает значение атрибута или значение по умолчанию
  if node.kind != xnElement or node.attrs == nil:
    return default
  if node.attrs.hasKey(attr):
    return node.attrs[attr]
  return default

proc getAttributes*(node: XmlNode): Table[string, string] =
  ## Возвращает все атрибуты узла
  result = initTable[string, string]()
  if node.kind == xnElement and node.attrs != nil:
    for key, val in node.attrs.pairs:
      result[key] = val

# ==================== НАВИГАЦИЯ ====================

proc parent*(node: XmlNode): XmlNode =
  ## Возвращает родительский узел (требует обхода дерева)
  ## Примечание: XmlNode не хранит ссылку на родителя
  ## Для полноценной навигации нужно построить дополнительную структуру
  return nil

proc nextSibling*(node: XmlNode, parent: XmlNode): XmlNode =
  ## Возвращает следующий элемент-сосед
  if parent == nil or parent.kind != xnElement:
    return nil
  var found = false
  for child in parent:
    if found and child.kind == xnElement:
      return child
    if child == node:
      found = true
  return nil

proc previousSibling*(node: XmlNode, parent: XmlNode): XmlNode =
  ## Возвращает предыдущий элемент-сосед
  if parent == nil or parent.kind != xnElement:
    return nil
  var prev: XmlNode = nil
  for child in parent:
    if child == node:
      return prev
    if child.kind == xnElement:
      prev = child
  return nil






###########################################################
# ================ ДОПОЛНИТЕЛЬНЫЕ УТИЛИТЫ =================
###########################################################

proc prettyPrint*(node: XmlNode, indent = 0): string =
  ## Красиво печатает HTML с отступами
  let indentStr = "  ".repeat(indent)

  case node.kind
  of xnElement:
    result = indentStr & "<" & node.tag
    if node.attrs != nil:
      for key, val in node.attrs.pairs:
        result.add(" " & key & "=\"" & val & "\"")
    result.add(">")

    if node.len > 0:
      result.add("\n")
      for child in node:
        result.add(prettyPrint(child, indent + 1))
      result.add(indentStr)

    if node.htmlTag notin ExtendedSingleTags:
      result.add("</" & node.tag & ">\n")
    else:
      result.add("\n")

  of xnText:
    let text = node.text.strip()
    if text.len > 0:
      result = indentStr & text & "\n"

  of xnComment:
    result = indentStr & "<!-- " & node.text & " -->\n"

  else:
    discard



# ==================== СТРОКОВЫЕ УТИЛИТЫ ====================

proc normalizeWhitespace*(text: string): string =
  ## Нормализует пробелы (как в BeautifulSoup.get_text(strip=True))
  result = join(unicode.splitWhitespace(strip(text)), " ")

proc stripTags*(html: string): string =
  ## Удаляет все HTML теги из строки
  result = html.replace(re"<[^>]+>", "")

proc decodeHtmlEntities*(text: string): string =
  ## Декодирует все HTML сущности в тексте
  result = text
  var matches: seq[string]
  for match in findAll(text, re"&([a-zA-Z]+|#\d+|#x[0-9a-fA-F]+);"):
    let entity = match[1..^2]  # Убираем & и ;
    let decoded = entityToRune(entity)
    if decoded.ord > 0:
      result = result.replace(match, toUTF8(decoded))

# ==================== РАБОТА С ТАБЛИЦАМИ ====================

type
  TableData* = object
    headers*: seq[string]
    rows*: seq[seq[string]]

proc extractTable*(tableNode: XmlNode): TableData =
  ## Извлекает данные из HTML таблицы
  result = TableData(headers: @[], rows: @[])
  
  if tableNode.kind != xnElement or cmpIgnoreCase(tableNode.tag, "table") != 0:
    return
  
  # Ищем заголовки
  for node in tableNode:
    if node.kind == xnElement:
      if cmpIgnoreCase(node.tag, "thead") == 0:
        for tr in node:
          if tr.kind == xnElement and cmpIgnoreCase(tr.tag, "tr") == 0:
            for th in tr:
              if th.kind == xnElement and cmpIgnoreCase(th.tag, "th") == 0:
                var text = ""
                for child in th:
                  if child.kind == xnText:
                    text.add(child.text)
                result.headers.add(text.strip())
      elif cmpIgnoreCase(node.tag, "tbody") == 0 or cmpIgnoreCase(node.tag, "tr") == 0:
        var tbody = if cmpIgnoreCase(node.tag, "tbody") == 0: node else: tableNode
        for tr in tbody:
          if tr.kind == xnElement and cmpIgnoreCase(tr.tag, "tr") == 0:
            var row: seq[string] = @[]
            for td in tr:
              if td.kind == xnElement and (cmpIgnoreCase(td.tag, "td") == 0 or cmpIgnoreCase(td.tag, "th") == 0):
                var text = ""
                for child in td:
                  if child.kind == xnText:
                    text.add(child.text)
                row.add(text.strip())
            if row.len > 0:
              result.rows.add(row)

proc tableToCsv*(table: TableData): string =
  ## Конвертирует таблицу в CSV формат
  result = ""
  
  if table.headers.len > 0:
    result.add(table.headers.join(",") & "\n")
  
  for row in table.rows:
    result.add(row.join(",") & "\n")

# ==================== РАБОТА С ФОРМАМИ ====================

type
  FormField* = object
    name*: string
    fieldType*: string
    value*: string
    options*: seq[string]
  
  FormData* = object
    action*: string
    command*: string
    fields*: seq[FormField]

proc extractForm*(formNode: XmlNode): FormData =
  ## Извлекает данные из HTML формы
  result = FormData(action: "", command: "GET", fields: @[])
  
  if formNode.kind != xnElement or cmpIgnoreCase(formNode.tag, "form") != 0:
    return
  
  # Получаем атрибуты формы
  if formNode.attrs != nil:
    if formNode.attrs.hasKey("action"):
      result.action = formNode.attrs["action"]
    if formNode.attrs.hasKey("command"):
      result.command = formNode.attrs["command"]
  
  # Извлекаем поля
  proc extractFields(node: XmlNode, fields: var seq[FormField]) =
    if node.kind != xnElement:
      return
    
    let tag = toLowerAscii(node.tag)
    
    case tag
    of "input":
      var field = FormField()
      if node.attrs != nil:
        field.name = node.attrs.getOrDefault("name", "")
        field.fieldType = node.attrs.getOrDefault("type", "text")
        field.value = node.attrs.getOrDefault("value", "")
      if field.name != "":
        fields.add(field)
    
    of "textarea":
      var field = FormField()
      field.fieldType = "textarea"
      if node.attrs != nil:
        field.name = node.attrs.getOrDefault("name", "")
      for child in node:
        if child.kind == xnText:
          field.value.add(child.text)
      if field.name != "":
        fields.add(field)
    
    of "select":
      var field = FormField()
      field.fieldType = "select"
      if node.attrs != nil:
        field.name = node.attrs.getOrDefault("name", "")
      field.options = @[]
      
      for option in node:
        if option.kind == xnElement and cmpIgnoreCase(option.tag, "option") == 0:
          var optValue = ""
          if option.attrs != nil and option.attrs.hasKey("value"):
            optValue = option.attrs["value"]
          else:
            for child in option:
              if child.kind == xnText:
                optValue.add(child.text)
          field.options.add(optValue.strip())
      
      if field.name != "":
        fields.add(field)
    
    else:
      for child in node:
        extractFields(child, fields)
  
  extractFields(formNode, result.fields)

# ==================== РАБОТА СО ССЫЛКАМИ ====================

proc extractLinks*(node: XmlNode): seq[(string, string)] =
  ## Извлекает все ссылки из документа в формате (href, текст)
  result = @[]

  proc findLinks(n: XmlNode; links: var seq[(string, string)]) =
    if n.kind == xnElement:
      if cmpIgnoreCase(n.tag, "a") == 0:
        var href = ""
        var text = ""

        if n.attrs != nil and n.attrs.hasKey("href"):
          href = n.attrs["href"]

        for child in n:
          if child.kind == xnText:
            text.add(child.text)

        if href != "":
          links.add((href, text.strip()))

      # Рекурсия по потомкам только для элементов
      for child in n:
        findLinks(child, links)

  findLinks(node, result)




proc extractImages*(node: XmlNode): seq[(string, string)] =
  result = @[]

  for img in node.findAll("img"):
    # findAll возвращает только xnElement с tag == "img" (case insensitive)
    let src = img.attr("src")
    if src.len > 0:
      let alt = img.attr("alt").strip()
      result.add((src, alt))




#[ proc extractImages*(node: XmlNode): seq[(string, string)] =
  ## Извлекает все изображения из узла в формате (src, alt).
  ## Возвращает последовательность кортежей (ссылка на изображение, альтернативный текст).
  result = @[]

  proc collect(n: XmlNode; acc: var seq[(string, string)]) =
    # Проверяем тип узла ПЕРЕД любым доступом к tag/attr
    if n.kind == xnElement:
      # Только теперь безопасно обращаться к tag и attr
      if cmpIgnoreCase(n.tag, "img") == 0:
        let src = n.attr("src")
        if src.len > 0:
          let alt = n.attr("alt").strip()
          acc.add((src, alt))

    # Обходим детей независимо от типа текущего узла
    for child in n:
      collect(child, acc)

  collect(node, result) ]#



# ==================== ФИЛЬТРАЦИЯ И ПОИСК ====================

proc findAllByTag*(node: XmlNode, tag: string): seq[XmlNode] =
  ## Находит все узлы с указанным тегом
  result = @[]
  
  if node.kind != xnElement:
    return
  
  if cmpIgnoreCase(node.tag, tag) == 0:
    result.add(node)
  
  for child in node:
    result.add(findAllByTag(child, tag))

proc findAllByClass*(node: XmlNode, className: string): seq[XmlNode] =
  ## Находит все узлы с указанным классом
  result = @[]
  
  if node.kind != xnElement:
    return
  
  if node.attrs != nil and node.attrs.hasKey("class"):
    let classes = node.attrs["class"].split(Whitespace)
    if className in classes:
      result.add(node)
  
  for child in node:
    result.add(findAllByClass(child, className))

proc findById*(node: XmlNode, id: string): XmlNode =
  ## Находит узел по ID
  if node.kind != xnElement:
    return nil
  
  if node.attrs != nil and node.attrs.hasKey("id") and node.attrs["id"] == id:
    return node
  
  for child in node:
    let found = findById(child, id)
    if found != nil:
      return found
  
  return nil

proc findAllByAttr*(node: XmlNode, attr: string, value = ""): seq[XmlNode] =
  ## Находит все узлы с указанным атрибутом
  result = @[]
  
  if node.kind != xnElement:
    return
  
  if node.attrs != nil:
    if value == "":
      if node.attrs.hasKey(attr):
        result.add(node)
    else:
      if node.attrs.hasKey(attr) and node.attrs[attr] == value:
        result.add(node)
  
  for child in node:
    result.add(findAllByAttr(child, attr, value))

proc findAllByText*(node: XmlNode, text: string, exact = false): seq[XmlNode] =
  ## Находит все узлы, содержащие указанный текст
  result = @[]
  
  if node.kind != xnElement:
    return
  
  var nodeText = ""
  for child in node:
    if child.kind == xnText:
      nodeText.add(child.text)
  
  let matches = if exact:
    nodeText.strip() == text
  else:
    text.toLowerAscii() in nodeText.toLowerAscii()
  
  if matches:
    result.add(node)
  
  for child in node:
    result.add(findAllByText(child, text, exact))

# ==================== СТАТИСТИКА И АНАЛИЗ ====================

proc countTags*(node: XmlNode): Table[string, int] =
  ## Подсчитывает количество каждого тега (без учёта регистра)
  var stats = initCountTable[string]()

  proc count(n: XmlNode; tbl: var CountTable[string]) =
    if n.kind == xnElement:
      tbl.inc(toLowerAscii(n.tag))
      for child in n:
        count(child, tbl)

  count(node, stats)

  # Преобразование: pairs → seq[(string, int)] → Table
  result = stats.pairs.toSeq.toTable()



proc getDepth*(node: XmlNode): int =
  ## Вычисляет максимальную глубину дерева
  if node.kind != xnElement or node.len == 0:
    return 0
  
  var maxDepth = 0
  for child in node:
    let depth = getDepth(child)
    if depth > maxDepth:
      maxDepth = depth
  
  return maxDepth + 1



proc getStats*(node: XmlNode): Table[string, int] =
  ## Возвращает статистику документа: количество элементов, текстовых узлов и т.д.
  result = initTable[string, int]()

  proc analyze(n: XmlNode; stats: var Table[string, int]) =
    case n.kind
    of xnElement:
      stats["elements"] = stats.getOrDefault("elements", 0) + 1
      
      if n.attrs != nil and n.attrs.len > 0:
        stats["elements_with_attrs"] = stats.getOrDefault("elements_with_attrs", 0) + 1
        stats["total_attrs"] = stats.getOrDefault("total_attrs", 0) + n.attrs.len
      
      # Можно добавить больше метрик, например:
      # stats["tags"] = stats.getOrDefault(n.tag, 0) + 1   # ← статистика по тегам
      
      # Рекурсия только для элементов
      for child in n:
        analyze(child, stats)
      
    of xnText:
      stats["text_nodes"] = stats.getOrDefault("text_nodes", 0) + 1
      
    of xnComment:
      stats["comments"] = stats.getOrDefault("comments", 0) + 1
      
    else:
      discard

  analyze(node, result)

  # Глубина дерева — считаем отдельно
  result["depth"] = getDepth(node)



# ==================== МОДИФИКАЦИЯ ДОКУМЕНТА ====================

proc removeNode*(node: XmlNode, parent: XmlNode): bool =
  ## Удаляет узел из родителя
  if parent == nil or parent.kind != xnElement:
    return false
  
  for i in 0..<parent.len:
    if parent[i] == node:
      parent.delete(i)
      return true
  
  return false



proc replaceNode*(oldNode: XmlNode, newNode: XmlNode, parent: var XmlNode): bool =
  ## Заменяет oldNode на newNode в списке детей parent.
  ## Возвращает true, если замена произошла.
  if parent == nil or parent.kind != xnElement:
    return false

  for i in 0 ..< parent.len:
    if parent[i] == oldNode:
      parent.delete(i)           # сначала удаляем старый
      parent.insert(newNode, i)  # вставляем новый на то же место
      return true

  return false


proc unwrap*(node: XmlNode, parent: XmlNode): bool =
  ## Убирает обертку узла, оставляя его содержимое
  if parent == nil or parent.kind != xnElement or node.kind != xnElement:
    return false
  
  for i in 0..<parent.len:
    if parent[i] == node:
      # Вставляем детей node вместо node
      var children = newSeq[XmlNode](node.len)
      for j in 0..<node.len:
        children[j] = node[j]
      
      parent.delete(i)
      for j in countdown(children.high, 0):
        parent.insert(children[j], i)
      
      return true
  
  return false


proc wrap*(node: XmlNode, wrapperTag: string, parent: var XmlNode): bool =
  ## Оборачивает указанный узел новым элементом с тегом wrapperTag.
  ## Возвращает true, если оборачивание произошло.
  if parent == nil or parent.kind != xnElement:
    return false

  for i in 0 ..< parent.len:
    if parent[i] == node:
      let wrapper = newElement(wrapperTag)
      wrapper.add(node)               # переносим старый узел внутрь wrapper
      parent.replace(i, [wrapper])    # заменяем старый узел на wrapper
      return true

  return false


# ==================== ВАЛИДАЦИЯ ====================

proc hasRequiredAttrs*(node: XmlNode, attrs: seq[string]): bool =
  ## Проверяет наличие всех требуемых атрибутов
  if node.kind != xnElement or node.attrs == nil:
    return false
  
  for attr in attrs:
    if not node.attrs.hasKey(attr):
      return false
  
  return true

proc validateStructure*(node: XmlNode, rules: Table[string, seq[string]]): seq[string] =
  ## Проверяет структуру документа по правилам (tag -> allowed_children)
  result = @[]
  
  proc validate(n: XmlNode, path: string) =
    if n.kind != xnElement:
      return
    
    let tag = toLowerAscii(n.tag)
    let currentPath = if path == "": tag else: path & " > " & tag
    
    if rules.hasKey(tag):
      let allowedChildren = rules[tag]
      for child in n:
        if child.kind == xnElement:
          let childTag = toLowerAscii(child.tag)
          if childTag notin allowedChildren:
            result.add("Invalid child '" & childTag & "' in '" & currentPath & "'")
          validate(child, currentPath)
    else:
      for child in n:
        validate(child, currentPath)
  
  validate(node, "")

# ==================== XPATH-ПОДОБНЫЕ ФУНКЦИИ ====================

proc findByPath*(node: XmlNode, path: string): seq[XmlNode] =
  ## Простой XPath-подобный поиск
  ## Поддерживает: "tag1/tag2/tag3", "//tag" (рекурсивный поиск)
  result = @[]
  
  if path.startsWith("//"):
    # Рекурсивный поиск
    let tag = path[2..^1]
    return findAllByTag(node, tag)
  
  let parts = path.split("/")
  var current = @[node]
  
  for part in parts:
    if part == "":
      continue
    
    var next: seq[XmlNode] = @[]
    for n in current:
      if n.kind == xnElement:
        for child in n:
          if child.kind == xnElement and cmpIgnoreCase(child.tag, part) == 0:
            next.add(child)
    
    current = next
  
  result = current

# ==================== УТИЛИТЫ ДЛЯ ОЧИСТКИ ====================

proc removeEmptyTags*(node: XmlNode): XmlNode =
  ## Удаляет пустые теги (без текста и без детей)
  if node.kind != xnElement:
    return node
  
  var newChildren: seq[XmlNode] = @[]
  
  for child in node:
    if child.kind == xnElement:
      let cleaned = removeEmptyTags(child)
      
      # Проверяем, пустой ли элемент
      var isEmpty = true
      for grandchild in cleaned:
        if grandchild.kind == xnText and grandchild.text.strip() != "":
          isEmpty = false
          break
        elif grandchild.kind == xnElement:
          isEmpty = false
          break
      
      if not isEmpty or cleaned.htmlTag in ExtendedSingleTags:
        newChildren.add(cleaned)
    else:
      newChildren.add(child)
  
  result = node
  # Очищаем и добавляем обратно
  while node.len > 0:
    node.delete(0)
  for child in newChildren:
    node.add(child)

proc removeComments*(node: XmlNode): XmlNode =
  ## Удаляет все комментарии
  if node.kind != xnElement:
    return node
  
  var newChildren: seq[XmlNode] = @[]
  
  for child in node:
    if child.kind != xnComment:
      if child.kind == xnElement:
        newChildren.add(removeComments(child))
      else:
        newChildren.add(child)
  
  result = node
  while node.len > 0:
    node.delete(0)
  for child in newChildren:
    node.add(child)

proc sanitize*(node: XmlNode, allowedTags: seq[string]): XmlNode =
  ## Оставляет только разрешенные теги
  if node.kind != xnElement:
    return node
  
  let tag = toLowerAscii(node.tag)
  
  if tag in allowedTags:
    var newChildren: seq[XmlNode] = @[]
    for child in node:
      if child.kind == xnElement:
        newChildren.add(sanitize(child, allowedTags))
      elif child.kind == xnText:
        newChildren.add(child)
    
    result = node
    while node.len > 0:
      node.delete(0)
    for child in newChildren:
      node.add(child)
  else:
    # Возвращаем детей без обертки
    result = newElement("div")  # Временный контейнер
    for child in node:
      if child.kind == xnElement:
        result.add(sanitize(child, allowedTags))
      elif child.kind == xnText:
        result.add(child)











proc aboutHtmlParser*(): string = 
  """
HtmlParser — библиотека для автоматизированного разбора веб-ресурсов
и извлечения данных. Automated data extraction.

Версия 1.0 (2026-02-10)

Возможности:
- Три режима разбора: Strict, Relaxed, HTML5
- Автоматическое исправление ошибок HTML
- CSS селекторы для поиска элементов
- Извлечение текста и атрибутов
- Обработка „грязного“ HTML
- Совместимость с BeautifulSoup/lxml API

Режимы:
  strictOptions()   — строгий разбор (оригинальное поведение)
  defaultOptions()  — расслабленный разбор (рекомендуется)
  html5Options()    — максимальная толерантность к ошибкам
  """






when isMainModule:
  import os

  echo aboutHtmlParser()
  echo ""

  var path = "../tests/Nim-2.2.6.html"
  if paramCount() > 0: 
    path = paramStr(1)
  
  # Разбираем файл в разных режимах
  echo "========== RELAXED MODE (default) =========="
  var errors1: seq[string] = @[]
  var doc1 = loadHtml(path, errors1, defaultOptions())
  echo "Errors: ", errors1.len
  if errors1.len > 0 and errors1.len <= 10:
    for e in errors1:
      echo "  ", e
  elif errors1.len > 10:
    echo "  First 10 errors:"
    for i in 0..<10:
      echo "  ", errors1[i]
    echo "  ... and ", errors1.len - 10, " more"

  echo ""
  echo "========== HTML5 MODE =========="
  var errors2: seq[string] = @[]
  var doc2 = loadHtml(path, errors2, html5Options())
  echo "Errors: ", errors2.len

  # Демонстрация селекторов
  echo ""
  echo "========== CSS SELECTORS DEMO =========="
  
  # Поиск по тегу
  let divs = select(doc1, "div")
  echo "Found <div> tags: ", divs.len
  
  # Поиск по классу
  let headers = select(doc1, ".thdr2")
  echo "Found .thdr2 class: ", headers.len
  
  # Поиск по ID
  let title = selectOne(doc1, "#r_title")
  if title != nil:
    echo "Title text: ", getText(title)
  
  # Поиск всех ссылок
  let links = select(doc1, "a")
  echo "Found <a> tags: ", links.len
  if links.len > 0:
    echo "First link href: ", getAttribute(links[0], "href", "no href")
  
  # Сохранение результата
  var f: File
  if open(f, "../tests/test.txt", fmWrite):
    write(f, $doc1)
    close(f)
    echo ""
    echo "Output saved to ../tests/test.txt"
  else:
    echo "Cannot write output file"



  echo "\n\nHTML Utils — testing\n"
  # Создаем простой HTML для тестирования
  let html = """
  <html>
    <body>
      <div class="container">
        <h1 id="title">Test Document</h1>
        <table>
          <thead>
            <tr><th>Name</th><th>Value</th></tr>
          </thead>
          <tbody>
            <tr><td>Item 1</td><td>100</td></tr>
            <tr><td>Item 2</td><td>200</td></tr>
          </tbody>
        </table>
        <form action="/submit" command="POST">
          <input type="text" name="username" value="">
          <input type="password" name="password" value="">
          <select name="country">
            <option value="ru">Russia</option>
            <option value="us">USA</option>
          </select>
          <textarea name="comment">Comment here</textarea>
        </form>
        <div>
          <a href="http://example.com">Link 1</a>
          <a href="http://test.com">Link 2</a>
          <img src="image.png" alt="Test Image">
        </div>
      </div>
    </body>
  </html>
  """
  
  let doc = parseHtml(html)
  
  # Тестируем извлечение таблицы
  let tbl = findAllByTag(doc, "table")
  if tbl.len > 0:
    echo "=== TABLE EXTRACTION ==="
    let tableData = extractTable(tbl[0])
    echo "Headers: ", tableData.headers
    echo "Rows: ", tableData.rows
    echo ""
  
  # Тестируем извлечение формы
  let forms = findAllByTag(doc, "form")
  if forms.len > 0:
    echo "=== FORM EXTRACTION ==="
    let formData = extractForm(forms[0])
    echo "Action: ", formData.action
    echo "Command: ", formData.command
    echo "Fields:"
    for field in formData.fields:
      echo "  - ", field.name, " (", field.fieldType, ")"
      if field.options.len > 0:
        echo "    Options: ", field.options
    echo ""
  
  # Тестируем извлечение ссылок
  echo "=== LINKS EXTRACTION ==="
  let lnk = extractLinks(doc)
  for link in lnk:
    echo "  ", link[0], " -> ", link[1]
  echo ""
  
  # Тестируем извлечение изображений
  echo "=== IMAGES EXTRACTION ==="
  let images = extractImages(doc)
  for img in images:
    echo "  ", img[0], " (alt: ", img[1], ")"
  echo ""
  
  # Статистика
  echo "=== DOCUMENT STATS ==="
  let stats = getStats(doc)
  for key, val in stats.pairs:
    echo "  ", key, ": ", val
  echo ""
  
  # Подсчет тегов
  echo "=== TAG COUNTS ==="
  let tagCounts = countTags(doc)
  for tag, count in tagCounts.pairs:
    echo "  ", tag, ": ", count











# Компиляция:
# nim c -d:release htmlparser.nim



