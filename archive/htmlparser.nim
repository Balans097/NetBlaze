## Этот код демонстрирует, как вы можете итеративно проходить по всем тегам в HTML-файле
## и записывать обратно модифицированную версию. В этом случае мы ищем гиперссылки
## заканчивающиеся расширением `.rst` и преобразуем их в `.html`.
##
##   ```Nim test
##   import std/xmltree  # Для использования '$' для XmlNode
##   import std/strtabs  # Для доступа к XmlAttributes
##   import std/os       # Для использования splitFile
##   import std/strutils # Для использования cmpIgnoreCase
##
##   proc transformHyperlinks() =
##     let html = loadHtml("input.html")
##
##     for a in html.findAll("a"):
##       if a.attrs.hasKey "href":
##         let (dir, filename, ext) = splitFile(a.attrs["href"])
##         if cmpIgnoreCase(ext, ".rst") == 0:
##           a.attrs["href"] = dir / filename & ".html"
##
##     writeFile("output.html", $html)
##   ```

import std/[strutils, streams, parsexml, xmltree, unicode, strtabs]
import htmlentities

when defined(nimPreviewSlimSystem):
  import std/syncio

proc entityToUtf8*(entity: string): string =
  ## Преобразует имя HTML-сущности вроде `&Uuml;` или значения вроде `&#220;`
  ## или `&#x000DC;` в эквивалент UTF-8.
  ## "" возвращается, если имя сущности неизвестно. Парсер HTML уже преобразует сущности в UTF-8.
  runnableExamples:
    const sigma = "Σ"
    doAssert entityToUtf8("") == ""
    doAssert entityToUtf8("a") == ""
    doAssert entityToUtf8("gt") == ">"
    doAssert entityToUtf8("Uuml") == "Ü"
    doAssert entityToUtf8("quest") == "?"
    doAssert entityToUtf8("#63") == "?"
    doAssert entityToUtf8("Sigma") == sigma
    doAssert entityToUtf8("#931") == sigma
    doAssert entityToUtf8("#0931") == sigma
    doAssert entityToUtf8("#x3A3") == sigma
    doAssert entityToUtf8("#x03A3") == sigma
    doAssert entityToUtf8("#x3a3") == sigma
    doAssert entityToUtf8("#X3a3") == sigma
  let rune = entityToRune(entity)
  if rune.ord <= 0: result = ""
  else: result = toUTF8(rune)

proc addNode(father, son: XmlNode) =
  ## Добавляет сына к отцу, если сын не nil.
  if son != nil: add(father, son)

proc parse(x: var XmlParser, errors: var seq[string]): XmlNode {.gcsafe.}

proc expected(x: var XmlParser, n: XmlNode): string =
  ## Возвращает сообщение об ожидаемом закрывающем теге.
  result = errorMsg(x, "</" & n.tag & "> expected")

template elemName(x: untyped): untyped = rawData(x)

template adderr(x: untyped) =
  errors.add(x)

proc untilElementEnd(x: var XmlParser, result: XmlNode,
                     errors: var seq[string]) =
  ## Продолжает парсинг до конца элемента, добавляя подузлы и обрабатывая неявные закрытия.
  # мы парсили, например, `<br>` и не ожидаем `</br>`:
  if result.htmlTag in SingleTags:
    if x.kind != xmlElementEnd or cmpIgnoreCase(x.elemName, result.tag) != 0:
      return
  while true:
    case x.kind
    of xmlElementStart, xmlElementOpen:
      case result.htmlTag
      of tagP, tagInput, tagOption:
        # некоторые теги обычно не имеют `</end>`, как `<li>`, но
        # разрешаем `<p>` в `<dd>`, `<dt>` и `<li>` в следующем случае
        if htmlTag(x.elemName) in {tagLi, tagP, tagDt, tagDd, tagInput,
                                   tagOption}:
          adderr(expected(x, result))
          break
      of tagDd, tagDt, tagLi:
        if htmlTag(x.elemName) in {tagLi, tagDt, tagDd, tagInput,
                                   tagOption}:
          adderr(expected(x, result))
          break
      of tagTd, tagTh:
        if htmlTag(x.elemName) in {tagTr, tagTd, tagTh, tagTfoot, tagThead}:
          adderr(expected(x, result))
          break
      of tagTr:
        if htmlTag(x.elemName) == tagTr:
          adderr(expected(x, result))
          break
      of tagOptgroup:
        if htmlTag(x.elemName) in {tagOption, tagOptgroup}:
          adderr(expected(x, result))
          break
      else: discard
      result.addNode(parse(x, errors))
    of xmlElementEnd:
      if cmpIgnoreCase(x.elemName, result.tag) != 0:
        #echo "5; expected: ", result.htmltag, " ", x.elemName
        adderr(expected(x, result))
        # это кажется лучше соответствует исправлениям ошибок в браузерах:
        while x.kind in {xmlElementEnd, xmlWhitespace}:
          if x.kind == xmlElementEnd and cmpIgnoreCase(x.elemName,
              result.tag) == 0:
            break
          next(x)
      next(x)
      break
    of xmlEof:
      adderr(expected(x, result))
      break
    else:
      result.addNode(parse(x, errors))

proc parse(x: var XmlParser, errors: var seq[string]): XmlNode =
  ## Парсит следующий узел XML/HTML.
  case x.kind
  of xmlComment:
    result = newComment(x.rawData)
    next(x)
  of xmlCharData, xmlWhitespace:
    result = newText(x.rawData)
    next(x)
  of xmlPI, xmlSpecial:
    # мы просто игнорируем инструкции обработки на данный момент
    next(x)
  of xmlError:
    adderr(errorMsg(x))
    next(x)
  of xmlElementStart:
    result = newElement(toLowerAscii(x.elemName))
    next(x)
    untilElementEnd(x, result, errors)
  of xmlElementEnd:
    adderr(errorMsg(x, "unexpected ending tag: " & x.elemName))
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
        adderr(errorMsg(x))
        next(x)
        break
      else:
        adderr(errorMsg(x, "'>' expected"))
        next(x)
        break
    untilElementEnd(x, result, errors)
  of xmlAttribute, xmlElementClose:
    adderr(errorMsg(x, "<some_tag> expected"))
    next(x)
  of xmlCData:
    result = newCData(x.rawData)
    next(x)
  of xmlEntity:
    var u = entityToUtf8(x.rawData)
    if u.len != 0: result = newText(u)
    next(x)
  of xmlEof: discard

proc parseHtml*(s: Stream, filename: string,
                errors: var seq[string]): XmlNode =
  ## Парсит HTML из потока `s` и возвращает `XmlNode`. Каждая произошедшая ошибка парсинга добавляется в последовательность `errors`.
  var x: XmlParser
  open(x, s, filename, {reportComments, reportWhitespace, allowUnquotedAttribs,
    allowEmptyAttribs})
  next(x)
  # пропускаем DOCTYPE:
  if x.kind == xmlSpecial: next(x)

  result = newElement("document")
  result.addNode(parse(x, errors))
  #if x.kind != xmlEof:
  #  adderr(errorMsg(x, "EOF expected"))
  while x.kind != xmlEof:
    var oldPos = x.bufpos # небольшой хак, чтобы увидеть, есть ли прогресс
    result.addNode(parse(x, errors))
    if x.bufpos == oldPos:
      # принудительно прогресс!
      next(x)
  close(x)
  if result.len == 1:
    result = result[0]

proc parseHtml*(s: Stream): XmlNode =
  ## Парсит HTML из потока `s` и возвращает `XmlNode`. Все ошибки парсинга игнорируются.
  var errors: seq[string] = @[]
  result = parseHtml(s, "unknown_html_doc", errors)

proc parseHtml*(html: string): XmlNode =
  ## Парсит HTML из строки `html` и возвращает `XmlNode`. Все ошибки парсинга игнорируются.
  parseHtml(newStringStream(html))

proc loadHtml*(path: string, errors: var seq[string]): XmlNode =
  ## Загружает и парсит HTML из файла, указанного в `path`, и возвращает `XmlNode`. Каждая произошедшая ошибка парсинга добавляется в последовательность `errors`.
  var s = newFileStream(path, fmRead)
  if s == nil: raise newException(IOError, "Unable to read file: " & path)
  result = parseHtml(s, path, errors)

proc loadHtml*(path: string): XmlNode =
  ## Загружает и парсит HTML из файла, указанного в `path`, и возвращает `XmlNode`. Все ошибки парсинга игнорируются.
  var errors: seq[string] = @[]
  result = loadHtml(path, errors)














proc aboutHtmlParser*(): string = 
  """

HtmlParser — библиотека для автоматизированного разбора веб-ресурсов
и извлечения данных. Automated data extraction.

Версия 1.0 (2026-02-10).
  """




when isMainModule:
  import os

  echo aboutHtmlParser()

  var path = "../tests/Nim-2.2.6.html"
  if paramCount() > 0: path = paramStr(1)
  var
    errors: seq[string] = @[]
    x = loadHtml(path, errors)

  for e in items(errors): echo e

  var f: File
  if open(f, "../tests/test.txt", fmWrite):
    write(f, $x)
    close(f)
  else:
    quit("Cannot write ../tests/test.txt")






# nim c -d:release htmlparser.nim

