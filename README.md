# NetBlaze 🔥

> A powerful toolkit for web data extraction, processing, and network operations in Nim

[![Nim Version](https://img.shields.io/badge/nim-2.0.4+-blue.svg)](https://nim-lang.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-stable-brightgreen.svg)]()

NetBlaze is a comprehensive library for working with data transmission networks, featuring robust HTML parsing, CSS/XPath selectors, and web scraping capabilities. Built for reliability and performance on the Nim programming language.

---

## ✨ Features

### 🎯 Advanced HTML Parser
- **Fault-tolerant parsing** - Handles "dirty" HTML with automatic error correction
- **Multiple parsing modes** - Strict, Relaxed, and HTML5-compatible
- **CSS selectors** - Full CSS3 selector support
- **XPath queries** - Basic XPath expression support
- **Auto-correction** - Automatic tag closing and nesting fixes
- **DOM navigation** - Complete tree traversal and manipulation

### 🌐 Web Scraping Engine
- **CSS3 selectors** - Complete W3C specification compliance
- **XPath support** - Extract data using XPath expressions
- **Chainable API** - Fluent, intuitive syntax
- **Response handling** - Convenient HTTP response wrapper
- **Link extraction** - Smart URL extraction with filtering
- **Item loaders** - Structured data extraction

### ⚡ Performance
- **Query caching** - Automatic caching of compiled selectors
- **Async support** - Non-blocking HTTP requests with async/await
- **Memory efficient** - Optimized for large documents
- **Fast parsing** - High-performance lexer and parser

### 🛠 Additional Tools
- **Data export** - JSON, CSV, JSON Lines formats
- **Middleware system** - Request/response processing pipeline
- **Table extraction** - Parse HTML tables to structured data
- **Form handling** - Extract form data and fields
- **Text utilities** - Strip tags, normalize whitespace, decode entities

---

## 📦 Installation

### Via Nimble

```bash
nimble install netblaze
```

### Manual Installation

```bash
git clone https://github.com/Balans097/NetBlaze.git
cd NetBlaze
nimble install
```

---

## 🚀 Quick Start

### Basic HTML Parsing

```nim
import netblaze/htmlparser

# Parse HTML with automatic error correction
let html = """
<div class="container">
  <h1>Hello World</h1>
  <p class="text">First paragraph
  <p class="text">Second paragraph
</div>
"""

let doc = parseHtml(html)

# Find elements using CSS selectors
let heading = selectOne(doc, "h1")
echo getText(heading)  # "Hello World"

let paragraphs = select(doc, "p.text")
for p in paragraphs:
  echo getText(p)
```

### Web Scraping

```nim
import netblaze/nimbrowser

# Create a response object
let response = newResponse(
  url = "https://example.com",
  status = 200,
  body = """
    <div class="product">
      <h2 class="title">Product Name</h2>
      <span class="price">$99.99</span>
    </div>
  """
)

# Use chainable API for data extraction
let title = response.css(".product .title").get()
let price = response.css(".price").get()

echo "Title: ", title
echo "Price: ", price
```

### Async Fetching

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

### Table Extraction

```nim
import netblaze/htmlparser

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

# Export to CSV
let csv = tableToCsv(data)
writeFile("output.csv", csv)
```

---

## 📚 Documentation

### HTML Parser

#### Parsing Modes

NetBlaze supports three parsing modes:

- **Strict** - Original XML parser behavior, no auto-correction
- **Relaxed** (default) - Automatic error fixing, balanced approach
- **HTML5** - Maximum tolerance for modern web pages

```nim
import netblaze/htmlparser

# Use default (relaxed) mode
let doc1 = parseHtml(html)

# Strict mode
let doc2 = parseHtml(html, strictOptions())

# HTML5 mode for maximum compatibility
let doc3 = parseHtml(html, html5Options())
```

#### CSS Selectors

```nim
# By tag
let divs = select(doc, "div")

# By class
let items = select(doc, ".item")

# By ID
let header = selectOne(doc, "#header")

# By attribute
let links = select(doc, "a[href]")
let httpsLinks = select(doc, "a[href^='https']")

# Combinators
let directChildren = select(doc, "div > p")
let descendants = select(doc, "div p")
let adjacent = select(doc, "h1 + p")

# Pseudo-classes
let firstItem = selectOne(doc, "li:first-child")
let evenRows = select(doc, "tr:nth-child(even)")
let notExcluded = select(doc, "p:not(.exclude)")
```

#### Data Extraction

```nim
# Get text content
let text = getText(element)
let textClean = getTextClean(element)  # Normalized whitespace

# Get attributes
let href = getAttribute(element, "href")
let allAttrs = getAttributes(element)

# Get all text from descendants
let allText = getAllText(element)
```

### Web Scraping

#### ItemLoader

Structure your data extraction:

```nim
import netblaze/nimbrowser

let response = newResponse(url = "...", body = html)

# Create item loader
let loader = newItemLoader(response.css(".product"))

# Add fields
loader.addCss("title", "h2.title")
loader.addCss("price", ".price", attrib = "data-price")
loader.addCss("image", "img", attrib = "src")

# Load structured data
let item = loader.loadItem()

echo item["title"]
echo item["price"]
echo item["image"]
```

#### LinkExtractor

Extract and filter links:

```nim
import netblaze/nimbrowser
import re

# Create link extractor with filters
let extractor = newLinkExtractor(
  allowDomains = @["example.com"],
  denyPatterns = @[re".*\.(pdf|zip)$"],
  unique = true
)

let links = extractor.extractLinks(response)
for link in links:
  echo link.url
```

#### Export Data

```nim
import netblaze/nimbrowser

var items: seq[Item] = @[]

# ... collect items ...

# Export to JSON
let jsonData = items.toJson()
writeFile("data.json", jsonData)

# Export to JSON Lines
let jsonlData = items.toJsonLines()
writeFile("data.jsonl", jsonlData)

# Export to CSV
let csvData = items.toCsv()
writeFile("data.csv", csvData)
```

---

## 🎯 Use Cases

- **Data Scraping** - Extract structured data from websites
- **Web Monitoring** - Track changes on web pages
- **Content Migration** - Parse and transform HTML content
- **SEO Analysis** - Extract metadata and analyze page structure
- **Research** - Collect data for analysis and research
- **Testing** - Parse HTML responses in tests
- **Web Crawlers** - Build spiders and crawlers

---

## 📖 Examples

### Scrape Product Information

```nim
import netblaze/nimbrowser
import asyncdispatch

proc scrapeProducts(url: string) {.async.} =
  let response = await fetchAsync(url)
  
  # Extract all products
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

### Parse News Articles

```nim
import netblaze/htmlparser

let doc = loadHtml("article.html")

# Extract article metadata
let title = selectOne(doc, "h1.article-title")
let author = selectOne(doc, ".author-name")
let date = selectOne(doc, "time[datetime]")

# Extract article content
let paragraphs = select(doc, "article p")
var content = ""
for p in paragraphs:
  content &= getText(p) & "\n"

echo "Title: ", getText(title)
echo "Author: ", getText(author)
echo "Date: ", getAttribute(date, "datetime")
echo "\nContent:\n", content
```

### Extract Email Addresses

```nim
import netblaze/htmlparser
import re

let doc = loadHtml("contacts.html")
let allText = getAllText(doc)

# Find all email addresses
let emailPattern = re"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"
var emails: seq[string] = @[]

for match in findAll(allText, emailPattern):
  emails.add(match)

echo "Found emails: ", emails
```

---

## 🔧 Advanced Features

### Custom Parser Options

```nim
import netblaze/htmlparser

var options = defaultOptions()
options.autoClose = true
options.fixNesting = true
options.removeInvalid = true
options.preserveWhitespace = false
options.decodeEntities = true

let doc = parseHtml(html, options)
```

### XPath Queries

```nim
import netblaze/nimbrowser

let response = newResponse(url = "...", body = html)

# XPath expressions
let allParagraphs = response.xpath("//p").getall()
let firstDiv = response.xpath("//div[1]").get()
let linksWithHref = response.xpath("//a[@href]").getall()
```

### Middleware System

```nim
import netblaze/nimbrowser

# Create middleware for request processing
proc logMiddleware(request: Request): Request =
  echo "Processing: ", request.url
  return request

# Use in your scraper
# middleware.add(logMiddleware)
```

---

## 🧪 Testing

```bash
# Run tests
nimble test

# Run specific test
nim c -r tests/test_htmlparser.nim
nim c -r tests/test_nimbrowser.nim
```

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Thanks to the Nim community for creating an amazing programming language
- Inspired by Python's BeautifulSoup and Scrapy frameworks
- Built with performance and reliability in mind

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/Balans097/NetBlaze/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Balans097/NetBlaze/discussions)

---

## 🗺 Roadmap

- [ ] JavaScript rendering support
- [ ] More XPath features
- [ ] Proxy support
- [ ] Rate limiting
- [ ] Cookie handling
- [ ] Session management
- [ ] Enhanced middleware system
- [ ] Plugin architecture

---

**Made with ❤️ in Nim**

NetBlaze - Making web data extraction simple and efficient! 🚀
