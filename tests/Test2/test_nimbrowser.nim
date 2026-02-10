## Тестовый файл для проверки nimBrowser v2.1
## Компиляция: nim c -r test_nimbrowser.nim

import nimBrowser, xmltree, htmlparser

echo "="[].repeat(60)
echo "nimBrowser v2.1 - Тестирование исправлений"
echo "="[].repeat(60)
echo ""

var testsPass = 0
var testsFail = 0

template test(name: string, body: untyped) =
  try:
    body
    echo "✓ PASS: ", name
    testsPass.inc
  except Exception as e:
    echo "✗ FAIL: ", name
    echo "  Ошибка: ", e.msg
    testsFail.inc

# ============================================================================
# ТЕСТ 1: Базовый парсинг data-атрибутов
# ============================================================================

test "Парсинг data-testid":
  let html = """<div data-testid="review-card">Контент</div>"""
  let doc = parseHtml(html)
  let element = doc.querySelector("[data-testid=review-card]")
  assert not element.isNil, "Элемент не найден"
  assert element.getDataAttr("testid") == "review-card"

# ============================================================================
# ТЕСТ 2: Оператор *= (содержит)
# ============================================================================

test "Оператор *=  (contains)":
  let html = """<div data-testid="review-card-123">Контент</div>"""
  let doc = parseHtml(html)
  let element = doc.querySelector("[data-testid*=review]")
  assert not element.isNil, "Элемент с *=review не найден"

test "Оператор *= для класса":
  let html = """<div class="user-review-container">Контент</div>"""
  let doc = parseHtml(html)
  let element = doc.querySelector("[class*=review]")
  assert not element.isNil, "Элемент с class*=review не найден"

# ============================================================================
# ТЕСТ 3: Оператор ^= (начинается с)
# ============================================================================

test "Оператор ^= (starts-with)":
  let html = """<div data-testid="hero-title">Заголовок</div>"""
  let doc = parseHtml(html)
  let element = doc.querySelector("[data-testid^=hero]")
  assert not element.isNil, "Элемент с ^=hero не найден"

# ============================================================================
# ТЕСТ 4: Оператор $= (заканчивается на)
# ============================================================================

test "Оператор $= (ends-with)":
  let html = """<div id="content-wrapper">Контент</div>"""
  let doc = parseHtml(html)
  let element = doc.querySelector("[id$=wrapper]")
  assert not element.isNil, "Элемент с $=wrapper не найден"

# ============================================================================
# ТЕСТ 5: Множественные дефисы в атрибутах
# ============================================================================

test "Множественные дефисы (aria-labelledby)":
  let html = """<div aria-labelledby="header-title-123">Контент</div>"""
  let doc = parseHtml(html)
  let element = doc.querySelector("[aria-labelledby]")
  assert not element.isNil, "Элемент с aria-labelledby не найден"

# ============================================================================
# ТЕСТ 6: Сложный IMDB-подобный HTML
# ============================================================================

test "Сложная структура (IMDB-style)":
  let html = """
  <div data-testid="review-card" data-review-id="rw12345">
    <h3 data-testid="review-title">Отличный фильм!</h3>
    <span data-testid="review-rating">
      <span>9</span>/10
    </span>
    <div class="ipc-html-content-inner-div">
      Это был потрясающий фильм с отличным сюжетом.
    </div>
  </div>
  """
  
  let doc = parseHtml(html)
  
  # Найти карточку отзыва
  let reviewCard = doc.querySelector("[data-testid=review-card]")
  assert not reviewCard.isNil, "Карточка отзыва не найдена"
  
  # Проверить ID отзыва
  let reviewId = reviewCard.getDataAttr("review-id")
  assert reviewId == "rw12345", "ID отзыва неверный: " & reviewId
  
  # Найти заголовок
  let title = reviewCard.getTextOrDefault("[data-testid=review-title]", "")
  assert title == "Отличный фильм!", "Заголовок неверный: " & title
  
  # Найти текст
  let text = reviewCard.getTextOrDefault(".ipc-html-content-inner-div", "")
  assert "потрясающий" in text, "Текст отзыва неверный"

# ============================================================================
# ТЕСТ 7: Вспомогательные функции
# ============================================================================

test "extractNumbers()":
  let text = "123 out of 456 found this helpful"
  let numbers = extractNumbers(text)
  assert numbers.len == 2, "Должно быть 2 числа"
  assert numbers[0] == 123.0, "Первое число неверное"
  assert numbers[1] == 456.0, "Второе число неверное"

test "parseRating()":
  let rating1 = parseRating("8/10")
  assert rating1 == 8.0, "Рейтинг должен быть 8.0"
  
  let rating2 = parseRating("9.5/10")
  assert rating2 == 9.5, "Рейтинг должен быть 9.5"

test "hasAnyClass()":
  let html = """<div class="review spoiler container">Контент</div>"""
  let doc = parseHtml(html)
  let element = doc.querySelector("div")
  
  assert element.hasAnyClass(["spoiler", "warning"]), "Должен найти класс spoiler"
  assert element.hasAnyClass(["review", "post"]), "Должен найти класс review"
  assert not element.hasAnyClass(["missing", "none"]), "Не должен найти эти классы"

# ============================================================================
# ТЕСТ 8: querySelectorAll
# ============================================================================

test "querySelectorAll с data-атрибутами":
  let html = """
  <div>
    <div data-testid="review-card">Отзыв 1</div>
    <div data-testid="review-card">Отзыв 2</div>
    <div data-testid="review-card">Отзыв 3</div>
  </div>
  """
  
  let doc = parseHtml(html)
  let reviews = doc.querySelectorAll("[data-testid=review-card]")
  assert reviews.len == 3, "Должно быть найдено 3 отзыва, найдено: " & $reviews.len

# ============================================================================
# ТЕСТ 9: Комбинированные селекторы
# ============================================================================

test "Комбинированные селекторы":
  let html = """
  <div class="container">
    <div data-testid="review-card" class="spoiler">Спойлер</div>
    <div data-testid="review-card">Обычный</div>
  </div>
  """
  
  let doc = parseHtml(html)
  
  # Найти отзыв со спойлером
  let spoilerReview = doc.querySelector("[data-testid=review-card].spoiler")
  assert not spoilerReview.isNil, "Отзыв со спойлером не найден"
  assert spoilerReview.innerTextClean() == "Спойлер"

# ============================================================================
# ТЕСТ 10: Вложенные селекторы
# ============================================================================

test "Вложенные data-атрибуты":
  let html = """
  <div data-testid="review-container">
    <div data-testid="review-header">
      <h3 data-testid="review-title">Заголовок</h3>
    </div>
  </div>
  """
  
  let doc = parseHtml(html)
  let container = doc.querySelector("[data-testid=review-container]")
  assert not container.isNil, "Контейнер не найден"
  
  let title = container.querySelector("[data-testid=review-title]")
  assert not title.isNil, "Заголовок не найден"
  assert title.innerTextClean() == "Заголовок"

# ============================================================================
# РЕЗУЛЬТАТЫ
# ============================================================================

echo ""
echo "="[].repeat(60)
echo "РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ"
echo "="[].repeat(60)
echo "Пройдено: ", testsPass
echo "Провалено: ", testsFail
echo "Всего: ", testsPass + testsFail
echo ""

if testsFail == 0:
  echo "✓ ВСЕ ТЕСТЫ ПРОЙДЕНЫ! Библиотека работает корректно."
  echo ""
  echo "Теперь можно использовать для парсинга IMDB и других сайтов!"
else:
  echo "✗ ЕСТЬ ОШИБКИ! Проверьте вывод выше."
  quit(1)

echo "="[].repeat(60)
