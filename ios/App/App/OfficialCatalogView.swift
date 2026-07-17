import SwiftUI
import WebKit

struct OfficialCatalogProductDetails: Equatable {
    let summary: String?
    let ingredients: String?
    let producer: String?
    let country: String?

    var isEmpty: Bool {
        [summary, ingredients, producer, country].allSatisfy { $0 == nil }
    }

    func mergingMissingValues(from previous: OfficialCatalogProductDetails?) -> Self {
        OfficialCatalogProductDetails(
            summary: summary ?? previous?.summary,
            ingredients: ingredients ?? previous?.ingredients,
            producer: producer ?? previous?.producer,
            country: country ?? previous?.country
        )
    }
}

struct OfficialCatalogProduct: Equatable, Identifiable {
    let name: String
    let price: Double
    let originalPrice: Double?
    let loyaltyPrice: Double?
    let imageURL: URL?
    let sourceURL: URL
    let storeName: String
    let details: OfficialCatalogProductDetails?

    init(
        name: String,
        price: Double,
        originalPrice: Double?,
        loyaltyPrice: Double? = nil,
        imageURL: URL?,
        sourceURL: URL,
        storeName: String,
        details: OfficialCatalogProductDetails? = nil
    ) {
        self.name = name
        self.price = price
        self.originalPrice = originalPrice
        self.loyaltyPrice = loyaltyPrice
        self.imageURL = imageURL
        self.sourceURL = sourceURL
        self.storeName = storeName
        self.details = details
    }

    var id: String {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return sourceURL.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? sourceURL.absoluteString
    }

    var category: ProductCategory {
        ProductCategory.inferred(from: name)
    }

    var discountPercent: Int? {
        guard let originalPrice, originalPrice > price, price > 0 else { return nil }
        return Int((((originalPrice - price) / originalPrice) * 100).rounded())
    }

    var draft: ProductDraft {
        ProductDraft(
            name: name,
            quantity: 1,
            unit: .piece,
            category: category,
            estimatedPrice: price,
            note: "",
            imageURL: imageURL?.absoluteString,
            sourceURL: sourceURL.absoluteString,
            originalPrice: originalPrice
        )
    }

    func mergingMissingMedia(from previous: OfficialCatalogProduct) -> OfficialCatalogProduct {
        OfficialCatalogProduct(
            name: name,
            price: price,
            originalPrice: originalPrice ?? previous.originalPrice,
            loyaltyPrice: loyaltyPrice ?? previous.loyaltyPrice,
            imageURL: imageURL ?? previous.imageURL,
            sourceURL: sourceURL,
            storeName: storeName,
            details: details?.mergingMissingValues(from: previous.details) ?? previous.details
        )
    }
}

extension ProductCategory {
    static func inferred(from productName: String) -> ProductCategory {
        let value = StoreBrand.normalize(productName)
        let words = value
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let groups: [(ProductCategory, CategoryVocabulary)] = [
            (
                .household,
                CategoryVocabulary(
                    exactWords: ["мило", "мыло", "порошок", "відбілювач", "отбеливатель"],
                    prefixes: ["пран", "стир", "чистяч", "чистящ", "мийни", "моющ", "прибиран", "уборк", "сервет", "салфет", "побут", "бытов", "шампун", "туалетн"],
                    phrases: ["для миття", "для мытья", "гель для прання", "гель для стирки"]
                )
            ),
            (
                .dairy,
                CategoryVocabulary(
                    exactWords: ["молоко", "молока", "сир", "сиру", "сыр", "йогурт", "кефір", "кефир", "сметана", "сметани", "масло", "вершки", "сливки", "творог", "ряжанка"],
                    prefixes: ["молоч", "кисломолоч", "сирн", "сырн", "сирок", "творож"],
                    phrases: []
                )
            ),
            (
                .meat,
                CategoryVocabulary(
                    exactWords: ["фарш", "мясо", "мяса"],
                    prefixes: ["мяс", "ковбас", "колбас", "куряч", "курин", "курят", "курк", "індич", "индей", "сосиск", "сардель", "шинка", "ветчин", "свинин", "ялович", "говяж", "теляч", "бекон"],
                    phrases: ["м'яс"]
                )
            ),
            (
                .drinks,
                CategoryVocabulary(
                    exactWords: ["вода", "води", "воду", "водой", "сік", "соку", "сок", "сока", "соком", "чай", "чаю", "кава", "кави", "кофе", "квас", "узвар", "компот", "нектар"],
                    prefixes: ["напій", "напит", "лимонад", "енергет", "энергет", "газован", "мінерал", "минерал"],
                    phrases: []
                )
            ),
            (
                .produce,
                CategoryVocabulary(
                    exactWords: ["банан", "банани", "бананы", "томат", "томати", "помідор", "помидор", "огірок", "огурец", "картопля", "картофель", "цибуля", "лук", "морква", "морковь", "апельсин", "яблуко", "яблоко", "авокадо", "кабачок", "баклажан", "буряк", "свекла", "капуста", "персик", "нектарин", "лимон", "лайм", "грейпфрут", "виноград", "полуниця", "клубника", "малина", "груша"],
                    prefixes: ["яблуч", "яблоч", "банан", "томат", "помід", "помид", "огір", "огур", "картоп", "картоф", "цибул", "морк", "апельс", "овоч", "овощ", "фрукт", "авокад", "кабач", "баклаж", "капуст", "персик", "виноград", "полуниц", "клубник", "малин", "груш"],
                    phrases: []
                )
            ),
        ]
        return groups.first { _, vocabulary in
            vocabulary.matches(normalizedName: value, words: words)
        }?.0 ?? .other
    }

    private struct CategoryVocabulary {
        let exactWords: Set<String>
        let prefixes: [String]
        let phrases: [String]

        func matches(normalizedName: String, words: [String]) -> Bool {
            if phrases.contains(where: normalizedName.contains) { return true }
            return words.contains { word in
                exactWords.contains(word)
                    || prefixes.contains(where: word.hasPrefix)
            }
        }
    }
}

enum OfficialCatalogSort: String, CaseIterable, Identifiable {
    case relevance
    case priceAscending
    case priceDescending
    case discount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: return "По популярности"
        case .priceAscending: return "Сначала дешевле"
        case .priceDescending: return "Сначала дороже"
        case .discount: return "Максимальная скидка"
        }
    }

    var systemImage: String {
        switch self {
        case .relevance: return "sparkles"
        case .priceAscending: return "arrow.up"
        case .priceDescending: return "arrow.down"
        case .discount: return "tag.fill"
        }
    }

    func apply(to products: [OfficialCatalogProduct]) -> [OfficialCatalogProduct] {
        switch self {
        case .relevance:
            return products
        case .priceAscending:
            return products.sorted { $0.price < $1.price }
        case .priceDescending:
            return products.sorted { $0.price > $1.price }
        case .discount:
            return products.sorted {
                ($0.discountPercent ?? -1) > ($1.discountPercent ?? -1)
            }
        }
    }
}

enum OfficialCatalogProductCollection {
    static func discounted(_ products: [OfficialCatalogProduct]) -> [OfficialCatalogProduct] {
        products.filter { $0.discountPercent != nil }
    }

    static func merged(
        current: [OfficialCatalogProduct],
        incoming: [OfficialCatalogProduct]
    ) -> [OfficialCatalogProduct] {
        var result = current
        var positions = Dictionary(
            uniqueKeysWithValues: current.enumerated().map { ($0.element.id, $0.offset) }
        )

        for product in incoming where product.price > 0 {
            if let index = positions[product.id] {
                result[index] = product.mergingMissingMedia(from: result[index])
            } else {
                positions[product.id] = result.count
                result.append(product)
            }
        }
        return result
    }
}

enum OfficialCatalogPriceParser {
    struct ATBPriceInfo: Equatable {
        let price: Double
        let originalPrice: Double?
        let loyaltyPrice: Double?
    }

    static func value(from rawValue: Any?) -> Double? {
        if let number = rawValue as? NSNumber {
            return number.doubleValue > 0 ? number.doubleValue : nil
        }
        guard let rawText = rawValue as? String else { return nil }
        let text = rawText
            .replacingOccurrences(of: " ", with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let pattern = #"\d[\d\s]*(?:[.,]\s*\d{1,2})?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range, in: text) else { return nil }
        let normalized = text[range]
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    static func atbPriceInfo(from rawText: String) -> ATBPriceInfo? {
        let text = rawText
            .replacingOccurrences(of: " ", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let currencyPattern = #"(\d[\d\s]*(?:[.,]\s*\d{1,2})?)\s*(?:₴|грн\.?|uah)(?:\s*/\s*(?:шт|кг))?"#
        guard let expression = try? NSRegularExpression(
            pattern: currencyPattern,
            options: [.caseInsensitive]
        ),
        let match = expression.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ),
        let priceRange = Range(match.range(at: 1), in: text),
        let price = value(from: String(text[priceRange])) else { return nil }

        let tailStart = Range(match.range, in: text)?.upperBound ?? text.endIndex
        let tail = String(text[tailStart...].prefix(180))
        let decimalPattern = #"\d[\d\s]*(?:[.,]\s*\d{1,2})"#
        let decimalExpression = try? NSRegularExpression(pattern: decimalPattern)
        let secondaryValues = decimalExpression?.matches(
            in: tail,
            range: NSRange(tail.startIndex..., in: tail)
        ).compactMap { match -> Double? in
            guard let range = Range(match.range, in: tail) else { return nil }
            return value(from: String(tail[range]))
        } ?? []

        let normalizedText = StoreBrand.normalize(text)
        let hasDiscount = normalizedText.range(
            of: #"(?:-|−)\s*\d+\s*%|акц|зниж|скид|економ"#,
            options: .regularExpression
        ) != nil
        let hasLoyaltyPrice = normalizedText.range(
            of: #"картк|карточк|atb\s*card|атб\s*card"#,
            options: .regularExpression
        ) != nil

        let originalPrice = hasDiscount
            ? secondaryValues.first(where: { $0 > price })
            : nil
        let loyaltyPrice = hasLoyaltyPrice
            ? secondaryValues.first(where: { $0 < price })
            : nil
        return ATBPriceInfo(
            price: price,
            originalPrice: originalPrice,
            loyaltyPrice: loyaltyPrice
        )
    }
}

final class OfficialCatalogBrowserState: ObservableObject {
    @Published private(set) var products: [OfficialCatalogProduct] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorText: String?
    @Published private(set) var isExhausted = false

    private var consecutiveEmptyLoads = 0
    private var rootURL: URL?
    private var initialContinuationURLs: [URL] = []
    private var remainingContinuationURLs: [URL] = []

    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func beginLoading(
        clearProducts: Bool,
        rootURL: URL? = nil,
        continuationURLs: [URL]? = nil
    ) {
        if let rootURL {
            self.rootURL = rootURL
        }
        if let continuationURLs {
            initialContinuationURLs = continuationURLs
            remainingContinuationURLs = continuationURLs
        }
        if clearProducts { products = [] }
        consecutiveEmptyLoads = 0
        isLoading = true
        isLoadingMore = false
        isExhausted = false
        errorText = nil
    }

    func continueLoading() {
        if products.isEmpty { isLoading = true }
        errorText = nil
    }

    func merge(_ incoming: [OfficialCatalogProduct]) {
        guard !incoming.isEmpty else { return }
        let previousCount = products.count
        products = OfficialCatalogProductCollection.merged(
            current: products,
            incoming: incoming
        )
        if products.count > previousCount {
            consecutiveEmptyLoads = 0
        }
        isLoading = false
        isLoadingMore = false
        errorText = nil
    }

    func finishLoadingIfNeeded() {
        isLoading = false
        isLoadingMore = false
        guard products.isEmpty else { return }
        errorText = "Официальный каталог пока не отдал карточки товаров. Повторите загрузку чуть позже."
    }

    func show(error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        isLoading = false
        isLoadingMore = false
        if products.isEmpty {
            errorText = "Не удалось обновить официальный каталог. Проверьте интернет и повторите."
        }
    }

    func reload() {
        guard let webView, let rootURL else { return }
        beginLoading(
            clearProducts: true,
            rootURL: rootURL,
            continuationURLs: initialContinuationURLs
        )
        var request = URLRequest(url: rootURL, cachePolicy: .reloadRevalidatingCacheData)
        request.timeoutInterval = 18
        webView.load(request)
    }

    func loadMore() {
        guard let webView, !isLoadingMore, !isExhausted else { return }
        let previousCount = products.count
        isLoadingMore = true
        webView.evaluateJavaScript(OfficialCatalogExtraction.scrollScript) { [weak self, weak webView] result, _ in
            DispatchQueue.main.async {
                guard let self, let webView else { return }
                let payload = result as? [String: Any]
                let action = payload?["action"] as? String

                if action == "navigate",
                   let value = payload?["url"] as? String,
                   let url = URL(string: value),
                   url.host?.lowercased() == webView.url?.host?.lowercased() {
                    var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
                    request.timeoutInterval = 18
                    webView.load(request)
                    return
                }

                if action == "end" {
                    if self.loadNextContinuation(in: webView) { return }
                    self.isLoadingMore = false
                    self.isExhausted = true
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    webView.evaluateJavaScript(OfficialCatalogExtraction.script) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            self.isLoadingMore = false
                            guard self.products.count == previousCount else { return }
                            // One quiet retry only — avoid recursive loadMore storms.
                            if self.consecutiveEmptyLoads < 1 {
                                self.consecutiveEmptyLoads += 1
                                self.loadMore()
                            } else if self.loadNextContinuation(in: webView) {
                                self.consecutiveEmptyLoads = 0
                            } else {
                                self.isExhausted = true
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadNextContinuation(in webView: WKWebView) -> Bool {
        guard let nextURL = remainingContinuationURLs.first else { return false }
        remainingContinuationURLs.removeFirst()
        var request = URLRequest(url: nextURL, cachePolicy: .reloadRevalidatingCacheData)
        request.timeoutInterval = 18
        webView.load(request)
        return true
    }
}

private final class WeakCatalogScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

private enum OfficialCatalogExtraction {
    static let scrollScript = #"""
    (() => {
      const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();
      const absolute = (value) => {
        try { return new URL(value, location.href).href; } catch (_) { return ''; }
      };
      const nextPage = document.querySelector(
        'a[aria-label="Next page"][href]:not([aria-disabled="true"]), a[rel="next"][href]'
      );
      if (nextPage) {
        return { action: 'navigate', url: absolute(nextPage.href) };
      }
      const currentURL = new URL(location.href);
      const currentPage = Number(currentURL.searchParams.get('page') || '1');
      const numberedNextPage = [...document.querySelectorAll('a[href]')].find((link) => {
        try {
          const candidate = new URL(link.href, location.href);
          return candidate.host === currentURL.host
            && candidate.pathname === currentURL.pathname
            && Number(candidate.searchParams.get('page')) === currentPage + 1;
        } catch (_) {
          return false;
        }
      });
      if (numberedNextPage) {
        return { action: 'navigate', url: absolute(numberedNextPage.href) };
      }
      const morePattern = /^(показати ще|показать ещё|показать еще|дивитись ще|завантажити ще|load more|show more)$/i;
      const moreButton = [...document.querySelectorAll('button, a')].find((element) => {
        const style = window.getComputedStyle(element);
        const visible = style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
        return visible && morePattern.test(clean(element.textContent));
      });
      if (moreButton) {
        moreButton.click();
        return { action: 'clicked' };
      }
      if (document.querySelector('.Pagination, [class*="Pagination"]')) {
        return { action: 'end' };
      }
      if (document.getElementById('__NEXT_DATA__') && /\/(categories|custom-categories)\//.test(location.pathname)) {
        return { action: 'end' };
      }
      const distance = Math.max(window.innerHeight * 1.6, 900);
      window.scrollTo({ top: Math.min(document.body.scrollHeight, window.scrollY + distance), behavior: 'auto' });
      return { action: 'scrolled' };
    })();
    """#

    static let script = #"""
    (() => {
      const products = [];
      const positions = new Map();
      const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
      const isATB = /(^|\.)atbmarket\.com$/i.test(location.hostname);
      const plainText = (value) => {
        const values = Array.isArray(value) ? value : [value];
        const container = document.createElement('div');
        container.innerHTML = values.filter(Boolean).join(' ');
        return clean(container.textContent || container.innerText || '');
      };
      const absolute = (value) => {
        try { return new URL(value, location.href).href; } catch (_) { return ''; }
      };
      const imageValue = (value) => {
        if (Array.isArray(value)) return imageValue(value[0]);
        if (value && typeof value === 'object') return value.url || value.contentUrl || '';
        return value || '';
      };
      const numberValue = (value) => {
        if (typeof value === 'number') return value > 0 ? value : 0;
        const match = clean(value).replace(/\u00a0/g, ' ').match(/\d[\d\s]*(?:[.,]\d{1,2})?/);
        if (!match) return 0;
        const parsed = Number(match[0].replace(/\s/g, '').replace(',', '.'));
        return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
      };
      const minorCurrencyValue = (value) => {
        const parsed = Number(value);
        return Number.isFinite(parsed) && parsed > 0 ? parsed / 100 : 0;
      };
      const add = (value) => {
        const name = clean(value.name);
        const sourceURL = absolute(value.sourceURL || value.url);
        const price = numberValue(value.price);
        if (name.length < 3 || !sourceURL || !price || price > 1000000) return;
        const key = sourceURL.split('#')[0].split('?')[0];
        const oldPrice = numberValue(value.originalPrice);
        const product = {
          name,
          price,
          originalPrice: oldPrice > price ? oldPrice : 0,
          loyaltyPrice: numberValue(value.loyaltyPrice),
          priceText: clean(value.priceText),
          imageURL: absolute(imageValue(value.imageURL || value.image)),
          sourceURL,
          details: {
            summary: plainText(value.details?.summary),
            ingredients: plainText(value.details?.ingredients),
            producer: clean(value.details?.producer),
            country: clean(value.details?.country)
          }
        };
        const existingIndex = positions.get(key);
        if (existingIndex !== undefined) {
          const existing = products[existingIndex];
          if (isATB && product.priceText && !existing.priceText) {
            products[existingIndex] = {
              ...existing,
              ...product,
              imageURL: product.imageURL || existing.imageURL,
              details: existing.details
            };
          }
          return;
        }
        positions.set(key, products.length);
        products.push(product);
      };

      const addStructuredProduct = (product) => {
        const offers = Array.isArray(product.offers) ? product.offers[0] : (product.offers || {});
        const specification = Array.isArray(offers.priceSpecification)
          ? offers.priceSpecification[0]
          : (offers.priceSpecification || {});
        add({
          name: product.name,
          price: offers.price || offers.lowPrice || specification.price,
          originalPrice: offers.highPrice || specification.maxPrice,
          image: product.image,
          sourceURL: product.url || product['@id'] || location.href
        });
      };

      const addZakazProduct = (product) => {
        const discount = product.discount || {};
        const images = product.img || {};
        const producer = product.producer || {};
        add({
          name: product.title,
          price: minorCurrencyValue(product.price),
          originalPrice: discount.status ? minorCurrencyValue(discount.old_price) : 0,
          imageURL: images.s350x350 || images.s200x200 || images.s150x150,
          sourceURL: product.web_url,
          details: {
            summary: product.description,
            ingredients: product.ingredients,
            producer: producer.trademark || producer.name,
            country: product.country
          }
        });
      };

      const nextDataNode = document.getElementById('__NEXT_DATA__');
      if (nextDataNode) {
        try {
          const nextData = JSON.parse(nextDataNode.textContent || '{}');
          const initialProps = nextData?.props?.pageProps?.initialProps || {};
          const collections = [
            initialProps.categoryData?.results,
            initialProps.searchData?.results,
            initialProps.products?.results
          ];
          collections.forEach((collection) => {
            if (Array.isArray(collection)) collection.forEach(addZakazProduct);
          });
        } catch (_) {}
      }

      const visit = (value) => {
        if (!value) return;
        if (Array.isArray(value)) {
          value.forEach(visit);
          return;
        }
        if (typeof value !== 'object') return;
        const type = Array.isArray(value['@type'])
          ? value['@type'].join(' ')
          : String(value['@type'] || '');
        if (type.toLowerCase().includes('product')) addStructuredProduct(value);
        Object.values(value).forEach(visit);
      };

      for (const node of document.querySelectorAll('script[type="application/ld+json"]')) {
        try { visit(JSON.parse(node.textContent)); } catch (_) {}
      }

      const moneyValues = (value) => {
        const text = clean(value);
        const values = [];
        const currencyPattern = /(\d[\d\s\u00a0]*(?:[.,]\d{1,2})?)\s*(?:₴|грн\.?|uah)/gi;
        let match;
        while ((match = currencyPattern.exec(text)) !== null) {
          const amount = numberValue(match[1]);
          if (amount) values.push(amount);
        }
        if (!values.length && /^\s*\d[\d\s]*(?:[.,]\d{1,2})?\s*$/.test(text)) {
          const amount = numberValue(text);
          if (amount) values.push(amount);
        }
        return values;
      };

      const canonicalProductURL = (value) => {
        const url = absolute(value);
        return url ? url.split('#')[0].split('?')[0] : '';
      };
      const cardForProductLink = (link) => {
        let node = link;
        let candidate = null;
        for (let depth = 0; node && depth < 12; depth += 1) {
          const productURLs = new Set(
            [...node.querySelectorAll('a[href]')]
              .map((item) => canonicalProductURL(item.href))
              .filter((url) => /\/(product|products|p)(\/|$)/i.test(url))
          );
          if (productURLs.size > 1) break;
          if (productURLs.size === 1 && /(?:₴|грн\.?|uah)/i.test(node.textContent || '')) {
            candidate = node;
          }
          node = node.parentElement;
        }
        return candidate || link.closest(
          '[data-testid*="product" i], [data-test*="product" i], [class*="product-card" i], [class*="productitem" i], article, li'
        ) || link.parentElement;
      };

      const links = [...document.querySelectorAll('a[href]')]
        .filter((link) => /\/(product|products|p)(\/|$)/i.test(absolute(link.href)));

      for (const link of links.slice(0, 240)) {
        const card = cardForProductLink(link);
        if (!card) continue;

        const image = card.querySelector('img');
        const heading = card.querySelector('h2, h3, h4, [class*="title" i], [class*="name" i]');
        const name = clean(
          heading?.textContent ||
          link.textContent ||
          link.getAttribute('aria-label') ||
          link.getAttribute('title') ||
          image?.getAttribute('alt')
        );

        const explicitOldNode = card.querySelector(
          '[data-marker*="Old Price" i], [class*="oldPrice" i], [class*="old-price" i], [class*="price-old" i], del, s'
        );
        const explicitDiscountedNode = card.querySelector(
          '[data-marker*="Discounted Price" i], [class*="price_discount" i], [class*="discountedPrice" i], [class*="sale-price" i], [class*="new-price" i]'
        );
        const explicitOldPrice = moneyValues(explicitOldNode?.textContent)[0] || 0;
        const explicitDiscountedPrice = moneyValues(explicitDiscountedNode?.textContent)[0] || 0;
        const priceSelector = '[itemprop="price"], meta[property="product:price:amount"], [data-price], [data-testid*="price" i], [class*="price" i], del, s';
        const priceNodes = [...card.querySelectorAll(priceSelector)]
          .filter((node) => !node.querySelector(priceSelector));
        const currentValues = [];
        const oldValues = [];
        for (const node of priceNodes) {
          const raw = node.getAttribute('content') || node.getAttribute('data-price') || node.textContent;
          const values = moneyValues(raw);
          let contextNode = node;
          let marker = '';
          while (contextNode && contextNode !== card.parentElement) {
            marker += ` ${contextNode.tagName} ${contextNode.className || ''} ${contextNode.getAttribute?.('data-testid') || ''} ${contextNode.getAttribute?.('data-marker') || ''}`;
            if (contextNode === card) break;
            contextNode = contextNode.parentElement;
          }
          marker = marker.toLowerCase();
          const isOld = /old|previous|regular|cross|strike|before|base|minor/.test(marker) || node.matches('del, s');
          (isOld ? oldValues : currentValues).push(...values);
        }

        if (!currentValues.length) currentValues.push(...moneyValues(card.textContent));
        let price = explicitDiscountedPrice || currentValues[0] || 0;
        let originalPrice = explicitOldPrice || oldValues[0] || 0;
        const discountMarker = /акц|зниж|скид|discount|sale|\-\s*\d+\s*%/i.test(card.textContent || '');
        if (!originalPrice && discountMarker && currentValues.length > 1) {
          const firstPair = currentValues.slice(0, 2);
          price = Math.min(...firstPair);
          originalPrice = Math.max(...firstPair);
        }

        const srcset = image?.getAttribute('srcset') || image?.getAttribute('data-srcset') || '';
        const imageURL =
          image?.currentSrc ||
          image?.getAttribute('src') ||
          image?.getAttribute('data-src') ||
          image?.getAttribute('data-lazy-src') ||
          srcset.split(',')[0]?.trim().split(/\s+/)[0] ||
          '';

        add({
          name,
          price,
          originalPrice,
          imageURL,
          sourceURL: link.href,
          priceText: isATB ? (card.innerText || card.textContent) : ''
        });
      }

      if (products.length) {
        window.webkit.messageHandlers.oneCartProducts.postMessage({ products });
      }
    })();
    """#
}

private struct OfficialCatalogDataBridge: UIViewRepresentable {
    let brand: StoreBrand
    let destinationURL: URL
    let continuationURLs: [URL]
    @ObservedObject var state: OfficialCatalogBrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(brand: brand, state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        context.coordinator.install(in: contentController)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = "OneCart/1.0 MobileCatalog"

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        state.attach(webView)
        context.coordinator.load(
            destinationURL,
            continuationURLs: continuationURLs,
            in: webView
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.requestedURL != destinationURL
                || context.coordinator.requestedContinuationURLs != continuationURLs else { return }
        context.coordinator.load(
            destinationURL,
            continuationURLs: continuationURLs,
            in: webView
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageName
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageName = "oneCartProducts"

        let brand: StoreBrand
        let state: OfficialCatalogBrowserState
        var requestedURL: URL?
        var requestedContinuationURLs: [URL] = []

        private var weakHandler: WeakCatalogScriptHandler?
        private var generation = UUID()

        init(brand: StoreBrand, state: OfficialCatalogBrowserState) {
            self.brand = brand
            self.state = state
        }

        func install(in controller: WKUserContentController) {
            let handler = WeakCatalogScriptHandler(delegate: self)
            weakHandler = handler
            controller.add(handler, name: Self.messageName)
        }

        func load(_ url: URL, continuationURLs: [URL], in webView: WKWebView) {
            generation = UUID()
            requestedURL = url
            requestedContinuationURLs = continuationURLs
            state.beginLoading(
                clearProducts: true,
                rootURL: url,
                continuationURLs: continuationURLs
            )
            var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
            request.timeoutInterval = 18
            webView.load(request)
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            generation = UUID()
            state.continueLoading()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let currentGeneration = generation
            let delays: [TimeInterval] = [0.15, 0.8, 1.8, 3.5]
            for (index, delay) in delays.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                    guard let self,
                          let webView,
                          self.generation == currentGeneration else { return }
                    if index > 0 {
                        webView.evaluateJavaScript(OfficialCatalogExtraction.scrollScript)
                    }
                    webView.evaluateJavaScript(OfficialCatalogExtraction.script) { _, _ in
                        guard index == delays.indices.last else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            guard self.generation == currentGeneration else { return }
                            // Do not auto-paginate here: loadMore cascades into scroll/JS
                            // loops that freeze the UI. Prefetch happens from list onAppear.
                            self.state.finishLoadingIfNeeded()
                        }
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            state.show(error: error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            state.show(error: error)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageName,
                  let body = message.body as? [String: Any],
                  let values = body["products"] as? [[String: Any]] else { return }

            let products = values.compactMap { value -> OfficialCatalogProduct? in
                guard let sourceValue = value["sourceURL"] as? String,
                      let sourceURL = URL(string: sourceValue),
                      brand.acceptsCatalogURL(sourceURL),
                      let rawName = value["name"] as? String else {
                    return nil
                }
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.count > 2 else { return nil }
                let atbPriceInfo = (value["priceText"] as? String).flatMap { text in
                    sourceURL.host?.lowercased().hasSuffix("atbmarket.com") == true
                        ? OfficialCatalogPriceParser.atbPriceInfo(from: text)
                        : nil
                }
                guard let price = atbPriceInfo?.price
                        ?? OfficialCatalogPriceParser.value(from: value["price"]) else {
                    return nil
                }
                let rawOriginalPrice = OfficialCatalogPriceParser.value(from: value["originalPrice"])
                let originalPrice = atbPriceInfo != nil
                    ? atbPriceInfo?.originalPrice
                    : rawOriginalPrice.flatMap { $0 > price ? $0 : nil }
                let rawLoyaltyPrice = atbPriceInfo != nil
                    ? atbPriceInfo?.loyaltyPrice
                    : OfficialCatalogPriceParser.value(from: value["loyaltyPrice"])
                let loyaltyPrice = rawLoyaltyPrice.flatMap { $0 < price ? $0 : nil }
                let imageURL = (value["imageURL"] as? String).flatMap(URL.init(string:))
                let detailValues = value["details"] as? [String: Any]
                func detail(_ key: String) -> String? {
                    guard let text = detailValues?[key] as? String else { return nil }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                let parsedDetails = OfficialCatalogProductDetails(
                    summary: detail("summary"),
                    ingredients: detail("ingredients"),
                    producer: detail("producer"),
                    country: detail("country")
                )
                return OfficialCatalogProduct(
                    name: name,
                    price: price,
                    originalPrice: originalPrice,
                    loyaltyPrice: loyaltyPrice,
                    imageURL: imageURL,
                    sourceURL: sourceURL,
                    storeName: brand.name,
                    details: parsedDetails.isEmpty ? nil : parsedDetails
                )
            }
            state.merge(products)
        }
    }
}

struct OfficialCatalogSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let listID: UUID
    let brand: StoreBrand

    @StateObject private var browser = OfficialCatalogBrowserState()
    @State private var destinationURL: URL
    @State private var selectedRouteID: String
    @State private var searchText = ""
    @State private var selectedCategory: ProductCategory?
    @State private var sort = OfficialCatalogSort.relevance
    @State private var addingProductIDs: Set<String> = []
    @State private var addedProductIDs: Set<String> = []
    @State private var selectedProduct: OfficialCatalogProduct?

    init(listID: UUID, brand: StoreBrand) {
        self.listID = listID
        self.brand = brand
        let fallback = brand.officialURL ?? URL(string: "about:blank")!
        let route = brand.catalogRoutes.first
        let completeCatalogURLs = brand.completeCatalogURLs
        let initialURL = route?.title == "Каталог"
            ? completeCatalogURLs.first ?? route?.url
            : route?.url
        _destinationURL = State(initialValue: initialURL ?? fallback)
        _selectedRouteID = State(initialValue: route?.id ?? fallback.absoluteString)
    }

    private var displayedProducts: [OfficialCatalogProduct] {
        let query = StoreBrand.normalize(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        let routeProducts = isShowingDiscounts
            ? OfficialCatalogProductCollection.discounted(browser.products)
            : browser.products
        let filtered = routeProducts.filter { product in
            let matchesSearch = query.isEmpty || StoreBrand.normalize(product.name).contains(query)
            let matchesCategory = selectedCategory == nil || product.category == selectedCategory
            return matchesSearch && matchesCategory
        }
        return sort.apply(to: filtered)
    }

    private var selectedRoute: StoreCatalogRoute? {
        brand.catalogRoutes.first { $0.id == selectedRouteID }
    }

    private var isShowingDiscounts: Bool {
        selectedRoute?.isDiscountRoute == true
    }

    private var continuationURLs: [URL] {
        let urls: [URL]
        if isShowingDiscounts {
            return []
        } else if let selectedCategory {
            urls = brand.catalogURLs(for: selectedCategory)
        } else if let selectedRoute {
            urls = catalogURLs(for: selectedRoute)
        } else {
            return []
        }
        guard urls.first == destinationURL else { return [] }
        return Array(urls.dropFirst())
    }

    private var availableCategories: [ProductCategory] {
        ProductCategory.allCases
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                catalogControls
                catalogContent
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .background(
                OfficialCatalogDataBridge(
                    brand: brand,
                    destinationURL: destinationURL,
                    continuationURLs: continuationURLs,
                    state: browser
                )
                .frame(width: 390, height: 844)
                .opacity(0.001)
                .allowsHitTesting(false)
            )
            .navigationTitle("Каталог \(brand.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { browser.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(browser.isLoading)
                    .accessibilityLabel("Обновить официальный каталог")
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $selectedProduct) { product in
            OfficialCatalogProductDetailSheet(product: product)
        }
    }

    private var catalogControls: some View {
        VStack(spacing: 10) {
            routePicker

            HStack(spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Найти товар", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 40)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                Menu {
                    Picker("Сортировка", selection: $sort) {
                        ForEach(OfficialCatalogSort.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: sort.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(OneCartPalette.primarySoft, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(OneCartPalette.primaryStrong)
                }
                .accessibilityLabel(sort.title)
            }
            .padding(.horizontal, 12)

            if !availableCategories.isEmpty {
                categoryPicker
            }
        }
        .padding(.bottom, 9)
        .background(OneCartPalette.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var routePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(brand.catalogRoutes) { route in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRouteID = route.id
                            destinationURL = catalogURLs(for: route).first ?? route.url
                            selectedCategory = nil
                            searchText = ""
                        }
                    } label: {
                        Label(route.title, systemImage: route.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                selectedRouteID == route.id
                                    ? OneCartPalette.primarySoft
                                    : Color(.secondarySystemBackground),
                                in: Capsule()
                            )
                            .foregroundColor(
                                selectedRouteID == route.id
                                    ? OneCartPalette.primaryStrong
                                    : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                categoryButton(title: "Все", image: "square.grid.2x2", category: nil)
                ForEach(availableCategories) { category in
                    categoryButton(
                        title: category.localizedName,
                        image: category.systemImage,
                        category: category
                    )
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func categoryButton(
        title: String,
        image: String,
        category: ProductCategory?
    ) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedCategory = category
                if isShowingDiscounts {
                    if let routeURL = selectedRoute?.url {
                        destinationURL = routeURL
                    }
                } else if let category,
                          let categoryURL = brand.catalogURLs(for: category).first {
                    if let catalogRoute = brand.catalogRoutes.first(where: { $0.title == "Каталог" }) {
                        selectedRouteID = catalogRoute.id
                    }
                    destinationURL = categoryURL
                } else if let selectedRoute {
                    destinationURL = catalogURLs(for: selectedRoute).first ?? selectedRoute.url
                }
            }
        } label: {
            Label(title, systemImage: image)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundColor(isSelected ? .white : .secondary)
                .background(
                    isSelected ? OneCartPalette.primary : Color(.tertiarySystemFill),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func catalogURLs(for route: StoreCatalogRoute) -> [URL] {
        switch route.title {
        case "Каталог":
            return brand.completeCatalogURLs
        case "Для дома":
            return brand.catalogURLs(for: .household)
        default:
            return []
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if browser.isLoading && browser.products.isEmpty {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { _ in
                        CatalogSkeletonRow()
                    }
                }
                .padding(12)
            }
        } else if let errorText = browser.errorText, browser.products.isEmpty {
            nativeStatusView(
                image: "wifi.exclamationmark",
                title: "Каталог не обновился",
                message: errorText,
                buttonTitle: "Повторить",
                action: browser.reload
            )
        } else if displayedProducts.isEmpty {
            nativeStatusView(
                image: "magnifyingglass",
                title: "Ничего не найдено",
                message: "Измените запрос или выберите другую категорию.",
                buttonTitle: "Сбросить фильтры"
            ) {
                searchText = ""
                selectedCategory = nil
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(displayedProducts.enumerated()), id: \.element.id) { index, product in
                        catalogProductRow(product)
                            .onAppear {
                                let prefetchIndex = max(0, displayedProducts.count - 8)
                                if index >= prefetchIndex {
                                    browser.loadMore()
                                }
                            }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("catalog-loader-\(browser.products.count)-\(selectedRouteID)-\(selectedCategory?.id ?? "all")")
                        .onAppear { browser.loadMore() }
                }
                .padding(12)
            }
        }
    }

    private func catalogProductRow(_ product: OfficialCatalogProduct) -> some View {
        HStack(spacing: 10) {
            Button {
                selectedProduct = product
            } label: {
                HStack(spacing: 10) {
                    OfficialProductThumbnail(
                        media: product.imageURL.map {
                            OfficialProductMedia(
                                imageURL: $0,
                                sourceURL: product.sourceURL,
                                sourceName: product.storeName
                            )
                        },
                        category: product.category,
                        size: 62
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        Text(product.category.localizedName)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(product.price.oneCartCurrency)
                                .font(.subheadline.bold())
                                .foregroundColor(product.originalPrice == nil ? .primary : .red)
                            if let oldPrice = product.originalPrice {
                                Text(oldPrice.oneCartCurrency)
                                    .strikethrough(true)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let discount = product.discountPercent {
                                Text("−\(discount)%")
                                    .font(.caption2.bold())
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.1), in: Capsule())
                            }
                        }
                        if let loyaltyPrice = product.loyaltyPrice {
                            Text("\(loyaltyPrice.oneCartCurrency) с картой ATB")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(OneCartPalette.primaryStrong)
                        }
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Открыть информацию о \(product.name)")

            Button {
                add(product)
            } label: {
                Group {
                    if addingProductIDs.contains(product.id) {
                        ProgressView()
                    } else if addedProductIDs.contains(product.id) {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .background(OneCartPalette.primary, in: Circle())
            .disabled(
                addingProductIDs.contains(product.id)
                    || addedProductIDs.contains(product.id)
                    || !model.canEdit
            )
            .accessibilityLabel("Добавить \(product.name)")
        }
        .padding(10)
        .background(OneCartPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    private func nativeStatusView(
        image: String,
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: image)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(OneCartPalette.primary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add(_ product: OfficialCatalogProduct) {
        guard let list = model.lists.first(where: { $0.id == listID }) else { return }
        addingProductIDs.insert(product.id)
        Task {
            await model.addProduct(to: list, draft: product.draft)
            addingProductIDs.remove(product.id)
            withAnimation(.easeInOut(duration: 0.2)) {
                addedProductIDs = addedProductIDs.union([product.id])
            }
        }
    }
}

private struct OfficialCatalogProductDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let product: OfficialCatalogProduct

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 12) {
                        OfficialProductThumbnail(
                            media: product.imageURL.map {
                                OfficialProductMedia(
                                    imageURL: $0,
                                    sourceURL: product.sourceURL,
                                    sourceName: product.storeName
                                )
                            },
                            category: product.category,
                            size: 138
                        )

                        Text(product.name)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)

                        Text(product.storeName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    priceCard

                    if let summary = product.details?.summary {
                        detailSection(title: "О товаре", text: summary)
                    }
                    if let ingredients = product.details?.ingredients {
                        detailSection(title: "Состав", text: ingredients)
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        Text("Характеристики")
                            .font(.headline)
                        factRow(title: "Категория", value: product.category.localizedName)
                        if let producer = product.details?.producer {
                            factRow(title: "Производитель", value: producer)
                        }
                        if let country = product.details?.country {
                            factRow(title: "Страна", value: country)
                        }
                    }
                    .padding(15)
                    .background(OneCartPalette.surface, in: RoundedRectangle(cornerRadius: 16))

                    Link(destination: product.sourceURL) {
                        Label("Открыть официальный источник", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(OneCartPalette.primaryStrong)
                    .background(OneCartPalette.primarySoft, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(16)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("Товар")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(product.price.oneCartCurrency)
                    .font(.title2.bold())
                    .foregroundColor(product.originalPrice == nil ? .primary : .red)
                if let oldPrice = product.originalPrice {
                    Text(oldPrice.oneCartCurrency)
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let discount = product.discountPercent {
                    Text("−\(discount)%")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.red, in: Capsule())
                }
            }
            if let loyaltyPrice = product.loyaltyPrice {
                Label("\(loyaltyPrice.oneCartCurrency) с картой ATB", systemImage: "creditcard.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(OneCartPalette.primaryStrong)
            }
        }
        .padding(15)
        .background(OneCartPalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneCartPalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func factRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct CatalogSkeletonRow: View {
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 110, height: 9)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 80, height: 12)
            }
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 34, height: 34)
        }
        .padding(10)
        .background(OneCartPalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .redacted(reason: .placeholder)
    }
}
