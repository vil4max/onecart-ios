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

    func sanitized(forProductName productName: String) -> Self {
        let cleanSum = OfficialCatalogProductQuality.cleanSummary(summary, productName: productName)
        let cleanIng = OfficialCatalogProductQuality.cleanSummary(ingredients, productName: productName)
        let cleanProd = producer?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCtry = country?.trimmingCharacters(in: .whitespacesAndNewlines)

        return OfficialCatalogProductDetails(
            summary: cleanSum,
            ingredients: cleanIng,
            producer: (cleanProd?.isEmpty ?? true) ? nil : cleanProd,
            country: (cleanCtry?.isEmpty ?? true) ? nil : cleanCtry
        )
    }
}

struct OfficialCatalogProduct: Equatable, Identifiable {
    static let freshnessInterval: TimeInterval = 5 * 60

    let name: String
    let price: Double
    let originalPrice: Double?
    let loyaltyPrice: Double?
    let imageURL: URL?
    let sourceURL: URL
    let storeName: String
    let details: OfficialCatalogProductDetails?
    /// Category of the store section the product was scraped from (authoritative when set).
    let pageCategory: ProductCategory?
    /// Official price basis. This is separate from the user's desired purchase quantity.
    let priceQuantity: Double
    let priceUnit: ProductUnit
    /// Promotion deadline as published by the retailer. Nil means the source did not publish one.
    let promotionEndsAt: Date?
    /// Time when this exact price was read from the official source.
    let fetchedAt: Date
    /// True only after the product page itself, rather than a category shelf, was parsed.
    let isDetailVerified: Bool

    init(
        name: String,
        price: Double,
        originalPrice: Double?,
        loyaltyPrice: Double? = nil,
        imageURL: URL?,
        sourceURL: URL,
        storeName: String,
        details: OfficialCatalogProductDetails? = nil,
        pageCategory: ProductCategory? = nil,
        priceQuantity: Double = 1,
        priceUnit: ProductUnit = .piece,
        promotionEndsAt: Date? = nil,
        fetchedAt: Date = Date(),
        isDetailVerified: Bool = false
    ) {
        self.name = OfficialCatalogProductQuality.cleanTitle(name)
        self.price = price
        self.originalPrice = originalPrice
        self.loyaltyPrice = loyaltyPrice
        self.imageURL = imageURL
        self.sourceURL = sourceURL
        self.storeName = storeName
        self.details = details
        self.pageCategory = pageCategory
        self.priceQuantity = max(priceQuantity, 0.001)
        self.priceUnit = priceUnit
        self.promotionEndsAt = promotionEndsAt
        self.fetchedAt = fetchedAt
        self.isDetailVerified = isDetailVerified
    }

    var id: String {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return sourceURL.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? sourceURL.absoluteString
    }

    /// Prefer the store aisle we actually loaded over fragile name guessing.
    var category: ProductCategory {
        pageCategory ?? ProductCategory.inferred(from: name)
    }

    func discountPercent(at date: Date) -> Int? {
        if let promotionEndsAt, promotionEndsAt <= date { return nil }
        guard let originalPrice, originalPrice > price, price > 0 else { return nil }
        let percent = Int((((originalPrice - price) / originalPrice) * 100).rounded())
        // Extreme "discounts" are almost always parse errors, not real promotions.
        // Real store promos often hit 50–70%; keep room up to 90%.
        guard (1 ... 90).contains(percent) else { return nil }
        return percent
    }

    var discountPercent: Int? {
        discountPercent(at: Date())
    }

    func isPriceFresh(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) <= Self.freshnessInterval
            && (promotionEndsAt == nil || promotionEndsAt! > date)
    }

    var priceBasisLabel: String {
        if priceQuantity == 1 {
            return "за \(priceUnit.localizedName)"
        }
        return "за \(priceQuantity.oneCartQuantity) \(priceUnit.localizedName)"
    }

    var draft: ProductDraft {
        ProductDraft(
            name: name,
            quantity: priceQuantity,
            unit: priceUnit,
            category: category,
            estimatedPrice: price,
            note: "",
            imageURL: imageURL?.absoluteString,
            sourceURL: sourceURL.absoluteString,
            originalPrice: discountPercent == nil ? nil : originalPrice,
            loyaltyPrice: loyaltyPrice,
            catalogFetchedAt: fetchedAt,
            promotionEndsAt: promotionEndsAt
        )
    }

    func mergingMissingMedia(from previous: OfficialCatalogProduct) -> OfficialCatalogProduct {
        let samePrice = abs(price - previous.price) < 0.01
        let mergedOriginalPrice = originalPrice ?? (samePrice ? previous.originalPrice : nil)
        let mergedLoyaltyPrice = loyaltyPrice ?? (samePrice ? previous.loyaltyPrice : nil)
        let mergedPromotionEndsAt = promotionEndsAt ?? (samePrice ? previous.promotionEndsAt : nil)

        let validPreviousName = OfficialCatalogProductQuality.isAcceptableName(previous.name) ? previous.name : nil
        let validNewName = OfficialCatalogProductQuality.isAcceptableName(name) ? name : nil
        let mergedName = validPreviousName ?? validNewName ?? previous.name

        let rawMergedDetails = details?.mergingMissingValues(from: previous.details) ?? previous.details
        let mergedDetails = rawMergedDetails?.sanitized(forProductName: mergedName)

        return OfficialCatalogProduct(
            name: mergedName,
            price: price,
            originalPrice: mergedOriginalPrice,
            loyaltyPrice: mergedLoyaltyPrice,
            imageURL: imageURL ?? previous.imageURL,
            sourceURL: sourceURL,
            storeName: storeName,
            details: (mergedDetails?.isEmpty ?? true) ? nil : mergedDetails,
            pageCategory: pageCategory ?? previous.pageCategory,
            priceQuantity: priceQuantity > 0 ? priceQuantity : previous.priceQuantity,
            priceUnit: priceUnit,
            promotionEndsAt: mergedPromotionEndsAt,
            fetchedAt: fetchedAt,
            isDetailVerified: isDetailVerified || previous.isDetailVerified
        )
    }
}

extension ProductCategory {
    /// Bakery/sweets that must never land in produce via "фрукт" / fruit-flavoured names.
    private static let produceBlocklistPattern = try! NSRegularExpression(
        pattern: #"""
        (?xi)
        торт|торта|торті|торты|cake|пирог|пиріг|пирож|печив|печень|вафл|
        цукерк|конфет|шоколад|тістеч|пирожн|кекс|маффін|маффин|круасан|
        бісквіт|бисквит|пряник|зефір|зефир|мармелад|халв|батончик|снек\s*бар|
        морозиво|мороженое|йогурт\s*десерт|десерт
        """#
    )

    static func inferred(from productName: String) -> ProductCategory {
        let value = StoreBrand.normalize(productName)
        let words = value
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let isBlockedFromProduce: Bool = {
            let range = NSRange(value.startIndex..., in: value)
            return produceBlocklistPattern.firstMatch(in: value, range: range) != nil
        }()
        let groups: [(ProductCategory, CategoryVocabulary)] = [
            (
                .household,
                CategoryVocabulary(
                    exactWords: [
                        "мило", "мыло", "порошок", "відбілювач", "отбеливатель",
                        "засіб", "средство", "очисник", "очиститель", "освіжувач",
                        "освежитель", "антисептик", "бальзам", "кондиціонер",
                        "кондиционер", "серветки", "салфетки", "губка", "щітка", "щетка",
                    ],
                    prefixes: [
                        "пран", "стир", "чистяч", "чистящ", "мийни", "моющ", "прибиран",
                        "уборк", "сервет", "салфет", "побут", "бытов", "шампун", "туалетн",
                        "дезинф", "дезінф", "відбіл", "отбел", "посуд", "посудн", "засоб",
                        "средств", "гігієн", "гигиен", "космет", "пеленк", "підгуз", "подгуз",
                    ],
                    phrases: [
                        "для миття", "для мытья", "гель для прання", "гель для стирки",
                        "для дому", "для дома", "побутова хімія", "бытовая химия",
                        "для посуду", "для посуды", "для унітазу", "для унитаза",
                    ]
                )
            ),
            (
                .dairy,
                CategoryVocabulary(
                    exactWords: [
                        "молоко",
                        "молока",
                        "сир",
                        "сиру",
                        "сыр",
                        "йогурт",
                        "кефір",
                        "кефир",
                        "сметана",
                        "сметани",
                        "масло",
                        "вершки",
                        "сливки",
                        "творог",
                        "ряжанка",
                    ],
                    prefixes: ["молоч", "кисломолоч", "сирн", "сырн", "сирок", "творож"],
                    phrases: []
                )
            ),
            (
                .meat,
                CategoryVocabulary(
                    exactWords: ["фарш", "мясо", "мяса"],
                    prefixes: [
                        "мяс",
                        "ковбас",
                        "колбас",
                        "куряч",
                        "курин",
                        "курят",
                        "курк",
                        "індич",
                        "индей",
                        "сосиск",
                        "сардель",
                        "шинка",
                        "ветчин",
                        "свинин",
                        "ялович",
                        "говяж",
                        "теляч",
                        "бекон",
                    ],
                    phrases: ["м'яс"]
                )
            ),
            (
                .drinks,
                CategoryVocabulary(
                    exactWords: [
                        "вода",
                        "води",
                        "воду",
                        "водой",
                        "сік",
                        "соку",
                        "сок",
                        "сока",
                        "соком",
                        "чай",
                        "чаю",
                        "кава",
                        "кави",
                        "кофе",
                        "квас",
                        "узвар",
                        "компот",
                        "нектар",
                    ],
                    prefixes: ["напій", "напит", "лимонад", "енергет", "энергет", "газован", "мінерал", "минерал"],
                    phrases: []
                )
            ),
            (
                .produce,
                CategoryVocabulary(
                    exactWords: [
                        "банан",
                        "банани",
                        "бананы",
                        "томат",
                        "томати",
                        "помідор",
                        "помидор",
                        "огірок",
                        "огурец",
                        "картопля",
                        "картофель",
                        "цибуля",
                        "лук",
                        "морква",
                        "морковь",
                        "апельсин",
                        "яблуко",
                        "яблоко",
                        "авокадо",
                        "кабачок",
                        "баклажан",
                        "буряк",
                        "свекла",
                        "капуста",
                        "персик",
                        "нектарин",
                        "лимон",
                        "лайм",
                        "грейпфрут",
                        "виноград",
                        "полуниця",
                        "клубника",
                        "малина",
                        "груша",
                    ],
                    // Avoid bare "фрукт" — it matches "фруктовий торт" and similar bakery.
                    prefixes: [
                        "яблуч",
                        "яблоч",
                        "банан",
                        "томат",
                        "помід",
                        "помид",
                        "огір",
                        "огур",
                        "картоп",
                        "картоф",
                        "цибул",
                        "морк",
                        "апельс",
                        "овоч",
                        "овощ",
                        "авокад",
                        "кабач",
                        "баклаж",
                        "капуст",
                        "персик",
                        "виноград",
                        "полуниц",
                        "клубник",
                        "малин",
                        "груш",
                        "ягод",
                        "ягід",
                    ],
                    phrases: [
                        "овочі та фрукти",
                        "овощи и фрукты",
                        "свіжі овочі",
                        "свежие овощи",
                        "свіжі фрукти",
                        "свежие фрукты",
                    ]
                )
            ),
        ]
        return groups.first { category, vocabulary in
            if category == .produce, isBlockedFromProduce { return false }
            return vocabulary.matches(normalizedName: value, words: words)
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

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .relevance: "По популярности"
        case .priceAscending: "Сначала дешевле"
        case .priceDescending: "Сначала дороже"
        case .discount: "Максимальная скидка"
        }
    }

    var systemImage: String {
        switch self {
        case .relevance: "sparkles"
        case .priceAscending: "arrow.up"
        case .priceDescending: "arrow.down"
        case .discount: "tag.fill"
        }
    }

    func apply(to products: [OfficialCatalogProduct]) -> [OfficialCatalogProduct] {
        switch self {
        case .relevance:
            products
        case .priceAscending:
            products.sorted { $0.price < $1.price }
        case .priceDescending:
            products.sorted { $0.price > $1.price }
        case .discount:
            products.sorted {
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

        for product in incoming {
            // Re-validate after merge inputs — keeps bad scrape rows out of the list UI.
            guard OfficialCatalogProductQuality.isAcceptableName(product.name),
                  OfficialCatalogProductQuality.isAcceptableProductURL(product.sourceURL),
                  let prices = OfficialCatalogProductQuality.sanitizedPrices(
                      price: product.price,
                      originalPrice: product.originalPrice,
                      loyaltyPrice: product.loyaltyPrice
                  ) else { continue }

            let cleaned = OfficialCatalogProduct(
                name: product.name,
                price: prices.price,
                originalPrice: prices.originalPrice,
                loyaltyPrice: prices.loyaltyPrice,
                imageURL: OfficialCatalogProductQuality.upgradedImageURL(product.imageURL)
                    ?? product.imageURL,
                sourceURL: product.sourceURL,
                storeName: product.storeName,
                details: product.details,
                pageCategory: product.pageCategory,
                priceQuantity: product.priceQuantity,
                priceUnit: product.priceUnit,
                promotionEndsAt: prices.originalPrice == nil ? nil : product.promotionEndsAt,
                fetchedAt: product.fetchedAt,
                isDetailVerified: product.isDetailVerified
            )

            if let index = positions[cleaned.id] {
                result[index] = cleaned.mergingMissingMedia(from: result[index])
            } else {
                positions[cleaned.id] = result.count
                result.append(cleaned)
            }
        }
        return result
    }
}

final class OfficialCatalogBrowserState: ObservableObject {
    @Published private(set) var products: [OfficialCatalogProduct] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorText: String?
    @Published private(set) var isExhausted = false
    @Published private(set) var lastSuccessfulRefreshAt: Date?

    private var consecutiveEmptyLoads = 0
    private var rootURL: URL?
    private var initialContinuationURLs: [URL] = []
    private var remainingContinuationURLs: [URL] = []
    private var lastLoadMoreAt: Date = .distantPast

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
        lastLoadMoreAt = .distantPast
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
        lastSuccessfulRefreshAt = incoming.map(\.fetchedAt).max() ?? Date()
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

    func reloadIfPriceExpiredOrStale(at date: Date = Date()) {
        guard !isLoading, !isLoadingMore else { return }
        let hasExpiredPromotion = products.contains {
            guard let promotionEndsAt = $0.promotionEndsAt else { return false }
            return promotionEndsAt <= date
        }
        let stale = lastSuccessfulRefreshAt.map {
            date.timeIntervalSince($0) >= OfficialCatalogProduct.freshnessInterval
        } ?? false
        if hasExpiredPromotion || stale { reload() }
    }

    func loadMore() {
        guard let webView, !isLoadingMore, !isExhausted, !isLoading else { return }
        // Debounce scroll-triggered pagination — LazyVStack can fire many onAppears.
        let now = Date()
        guard now.timeIntervalSince(lastLoadMoreAt) > 0.85 else { return }
        lastLoadMoreAt = now

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
                   url.host?.lowercased() == webView.url?.host?.lowercased()
                {
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

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    webView.evaluateJavaScript(OfficialCatalogExtraction.script) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            self.isLoadingMore = false
                            guard self.products.count == previousCount else {
                                self.consecutiveEmptyLoads = 0
                                return
                            }
                            // One quiet retry only — avoid recursive loadMore storms.
                            if self.consecutiveEmptyLoads < 1 {
                                self.consecutiveEmptyLoads += 1
                                self.lastLoadMoreAt = .distantPast
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
      const isVarus = /(^|\.)varus\.ua$/i.test(location.hostname);
      const isSilpo = /(^|\.)silpo\.ua$/i.test(location.hostname);
      const isZakaz = /(^|\.)zakaz\.ua$/i.test(location.hostname);
      const plainText = (value) => {
        const values = Array.isArray(value) ? value : [value];
        const container = document.createElement('div');
        container.innerHTML = values.filter(Boolean).join(' ');
        return clean(container.textContent || container.innerText || '');
      };
      const absolute = (value) => {
        try {
          let href = new URL(value, location.href).href;
          href = href.replace('://varus.ua:443/', '://varus.ua/').replace('://www.varus.ua:443/', '://varus.ua/');
          return href;
        } catch (_) { return ''; }
      };
      const isJunkName = (name) => {
        if (!name || name.length < 3 || name.length > 180) return true;
        if (/^(каталог|catalog|акци[яі]|знижк|скидк|меню|menu|пошук|search|увійти|войти|login|кошик|корзина|cart|cookie|файл|file|download|pdf)$/i.test(name)) return true;
        if (/\.(pdf|docx?|xlsx?|csv|zip|rar)$/i.test(name)) return true;
        if (/\b(оберіть\s+спосіб|выберите\s+способ|спосіб\s+доставки|способ\s+доставки|оберіть\s+магазин|выберите\s+магазин|особистий\s+кабінет|оформити\s+замовлення|оформить\s+заказ)\b/i.test(name)) return true;
        return false;
      };
      const cleanSummary = (rawSummary, productName) => {
        if (!rawSummary) return '';
        let text = String(rawSummary).replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, '');
        text = text.replace(/\b(купити|купить)\s+в\s+[^\n.]*/gi, '');
        text = text.replace(/\b(доставка\s+додому|доставка\s+на\s+дом|по\s+всій\s+україні|по\s+всей\s+украине)\b[^\n.]*/gi, '');
        text = text.replace(/\b(великий\s+вибір|большой\s+выбор)\b[^\n.]*/gi, '');
        text = text.replace(/\b(контроль\s+якості|контроль\s+качества)\b[^\n.]*/gi, '');
        text = text.replace(/\b(низькими\s+цінами|низким\s+ценам|кращі\s+ціни|лучшие\s+цены)\b[^\n.]*/gi, '');
        text = text.replace(/\b(0-800-\d+|\bгаряча\s+лінія\b|\bгорячая\s+линия\b)\b[^\n.]*/gi, '');
        text = text.replace(/\b(в\s+супермаркеті|в\s+супермаркете|в\s+інтернет[- ]магазині|в\s+интернет[- ]магазине)\b[^\n.]*/gi, '');
        text = text.replace(/\s+/g, ' ').replace(/^[\s.,\-–—:;!]+|[\s.,\-–—:;!]+$/g, '').trim();
        if (productName) {
          const normSummary = text.toLowerCase().replace(/[\s\W]/g, '');
          const normName = String(productName).toLowerCase().replace(/[\s\W]/g, '');
          if (normSummary === normName || !normSummary) return '';
        }
        return text;
      };
      const mergeDetails = (next, prev) => ({
        summary: cleanSummary(next?.summary || prev?.summary, next?.name || prev?.name),
        ingredients: next?.ingredients || prev?.ingredients || '',
        producer: next?.producer || prev?.producer || '',
        country: next?.country || prev?.country || ''
      });
      const imageValue = (value) => {
        if (Array.isArray(value)) {
          for (const item of value) {
            const found = imageValue(item);
            if (found) return found;
          }
          return '';
        }
        if (value && typeof value === 'object') {
          return value.s1350x1350 || value.s350x350 || value.s200x200 || value.s150x150
            || value.url || value.contentUrl || value.src || '';
        }
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
      const isProductURL = (value) => {
        try {
          const url = new URL(value, location.href);
          const path = url.pathname.toLowerCase();
          const host = url.hostname.toLowerCase();
          if (/\.(pdf|docx?|xlsx?|csv|zip|rar|jpe?g|png|gif|webp|svg|mp4|json)(\/|$)/i.test(path)) return false;
          if (/(^|\/)(cart|checkout|login|account|search|download|static|assets|category|categories|catalog)(\/|$)/i.test(path)) return false;
          if (/\/(product|products|p)(\/|$)/i.test(path)) return true;
          // VARUS product pages are bare slugs, not /product/...
          if (/(^|\.)varus\.ua$/i.test(host)) {
            const segments = path.split('/').filter(Boolean);
            if (segments.length !== 1) return false;
            const slug = segments[0];
            if (slug.length < 4 || slug.includes('.')) return false;
            return !/^(cart|checkout|login|own-clean|own-trademarks|ru|uk|ua|assets|img|blog|promo)$/i.test(slug);
          }
          return false;
        } catch (_) {
          return false;
        }
      };
      const preferLargerImage = (value) => {
        let url = absolute(imageValue(value));
        if (!url || url.startsWith('data:')) return '';
        if (/placeholder|blank|spacer|1x1|pixel|lazy-load|no[_-]?image/i.test(url)) return '';
        return url
          .replace(/s150x150/g, 's1350x1350')
          .replace(/s200x200/g, 's1350x1350')
          .replace(/s350x350/g, 's1350x1350')
          .replace(/s100x100/g, 's1350x1350')
          .replace(/\/img\/product\/(?:72|150|200)\/(?:72|150|200)\//g, '/img/product/420/420/')
          .replace(/\/products\/(?:200|300|400)x(?:200|300|400)\//g, '/products/744x744/')
          .replace(/catalog_product_gal_mob_/g, 'catalog_product_gal_');
      };
      const cleanTitle = (rawName) => {
        let name = clean(rawName);
        if (!name) return rawName;
        name = name.replace(/\s*[★⭐☆|•\-\—\–]?\s*\b(АТБ[- ]?Маркет|АТБ|Сільпо|Сильпо|Silpo|Varus|VARUS|Варус|Ашан|Auchan|Новус|Novus|Метро|Metro|Zakaz(?:\.ua)?|Фора|Fora)\b\s*$/i, '');
        name = name.replace(/\b(купити|купить)\s+в\s+(києві|україні|днепре|днепропетровске|харькове|одессе|львове|запорожье)\b[^\n]*/gi, '');
        name = name.replace(/\b(купити|купить)\s+за\s+ціною\s+від\s+\d+(?:[.,]\d+)?[^\n]*/gi, '');
        name = name.replace(/\b(купити|купить)\s+по\s+цене\s+от\s+\d+(?:[.,]\d+)?[^\n]*/gi, '');
        name = name.replace(/\bза\s+ціною\s+від\s+\d+(?:[.,]\d+)?\s*(грн|грн\.)?[^\n]*/gi, '');
        name = name.replace(/\bпо\s+цене\s+от\s+\d+(?:[.,]\d+)?\s*(грн|грн\.)?[^\n]*/gi, '');
        name = name.replace(/\b(в\s+інтернет[- ]магазині|в\s+интернет[- ]магазине)\b[^\n]*/gi, '');
        name = name.replace(/\b(з\s+доставкою\s+по|с\s+доставкой\s+по)\b[^\n]*/gi, '');
        name = name.replace(/^[\s★⭐☆|•\-\—\–,:;]+|[\s★⭐☆|•\-\—\–,:;]+$/g, '');
        name = name.replace(/\s+/g, ' ').trim();
        return name || rawName;
      };
      const add = (value) => {
        const name = cleanTitle(value.name);
        const sourceURL = absolute(value.sourceURL || value.url);
        const price = numberValue(value.price);
        if (isJunkName(name) || !sourceURL || !isProductURL(sourceURL) || !price || price < 1 || price > 50000) return;
        const key = sourceURL.split('#')[0].split('?')[0];
        const oldPrice = numberValue(value.originalPrice);
        const discountPct = oldPrice > price ? ((oldPrice - price) / oldPrice) * 100 : 0;
        const plausibleOld = oldPrice > price && oldPrice / price <= 10 && discountPct >= 1 && discountPct <= 90
          ? oldPrice
          : 0;
        const product = {
          name,
          price,
          originalPrice: plausibleOld,
          loyaltyPrice: numberValue(value.loyaltyPrice),
          priceText: clean(value.priceText),
          priceUnit: clean(value.priceUnit),
          promotionEnd: clean(value.promotionEnd),
          promotionText: clean(value.promotionText),
          sourcePriority: Number(value.sourcePriority || 0),
          imageURL: preferLargerImage(value.imageURL || value.image),
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
          // Structured retailer data must not be overwritten by a generic DOM guess.
          // ATB's dedicated text parser still receives priceText below.
          const monetary = product.sourcePriority >= existing.sourcePriority ? product : existing;
          products[existingIndex] = {
            name: product.name || existing.name,
            price: monetary.price,
            originalPrice: monetary.originalPrice,
            loyaltyPrice: monetary.loyaltyPrice,
            priceText: product.priceText || existing.priceText,
            priceUnit: monetary.priceUnit || existing.priceUnit,
            promotionEnd: monetary.promotionEnd || product.promotionEnd || existing.promotionEnd,
            promotionText: product.promotionText || existing.promotionText,
            sourcePriority: monetary.sourcePriority,
            imageURL: product.imageURL || existing.imageURL,
            sourceURL: product.sourceURL || existing.sourceURL,
            details: mergeDetails(product.details, existing.details)
          };
          return;
        }
        positions.set(key, products.length);
        products.push(product);
      };

      const brandName = (value) => {
        if (!value) return '';
        if (typeof value === 'string') return value;
        return value.name || value.trademark || '';
      };

      const addStructuredProduct = (product) => {
        const offers = Array.isArray(product.offers) ? product.offers[0] : (product.offers || {});
        const specification = Array.isArray(offers.priceSpecification)
          ? offers.priceSpecification[0]
          : (offers.priceSpecification || {});
        add({
          name: product.name,
          price: offers.price || offers.lowPrice || specification.price,
          originalPrice: offers.highPrice || specification.maxPrice || specification.price,
          priceUnit: specification.unitText || offers.unitText || product.unitText,
          promotionEnd: offers.priceValidUntil || specification.validThrough || product.validThrough,
          sourcePriority: 2,
          image: product.image,
          sourceURL: product.url || product['@id'] || location.href,
          details: {
            summary: product.description,
            producer: brandName(product.brand || product.manufacturer),
            country: product.countryOfOrigin || product.country
          }
        });
      };

      const addZakazProduct = (product) => {
        const discount = product.discount || {};
        const images = product.img || product.gallery?.[0] || {};
        const producer = product.producer || {};
        add({
          name: product.title,
          price: minorCurrencyValue(product.price),
          originalPrice: discount.status ? minorCurrencyValue(discount.old_price) : 0,
          priceUnit: product.unit,
          promotionEnd: discount.status ? discount.due_date : '',
          sourcePriority: 3,
          imageURL: images.s1350x1350 || images.s350x350 || images.s200x200 || images.s150x150,
          sourceURL: product.web_url,
          details: {
            summary: product.description,
            ingredients: product.ingredients,
            producer: producer.trademark || producer.name,
            country: product.country
          }
        });
      };

      // Zakaz (Auchan / Novus / Metro): products live in Redux-like initialState, not pageProps.
      const nextDataNode = document.getElementById('__NEXT_DATA__');
      if (nextDataNode) {
        try {
          const nextData = JSON.parse(nextDataNode.textContent || '{}');
          const catalogue = nextData?.props?.initialState?.catalogue || {};
          const initialProps = nextData?.props?.pageProps?.initialProps || {};
          const collections = [
            catalogue.categoryData?.results,
            catalogue.searchData?.results,
            catalogue.products?.results,
            catalogue.categoryData?.category_results,
            initialProps.categoryData?.results,
            initialProps.searchData?.results,
            initialProps.products?.results
          ];
          collections.forEach((collection) => {
            if (Array.isArray(collection)) collection.forEach(addZakazProduct);
          });
          // Deep walk for any leftover product-shaped nodes.
          const walkZakaz = (value, depth) => {
            if (!value || depth > 8) return;
            if (Array.isArray(value)) {
              value.forEach((item) => walkZakaz(item, depth + 1));
              return;
            }
            if (typeof value !== 'object') return;
            if (value.title && value.price != null && (value.web_url || value.img)) {
              addZakazProduct(value);
              return;
            }
            Object.values(value).forEach((child) => walkZakaz(child, depth + 1));
          };
          if (isZakaz) walkZakaz(nextData?.props?.initialState, 0);
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

      const bestImageFromCard = (card) => {
        const candidates = [];
        const push = (raw, scoreBonus) => {
          const url = preferLargerImage(raw);
          if (!url) return;
          let score = scoreBonus || 0;
          const sizeMatch = url.match(/(\d{2,4})x(\d{2,4})/);
          if (sizeMatch) score += Math.min(Number(sizeMatch[1]), Number(sizeMatch[2]));
          if (/s1350x1350|744x744|420\/420/.test(url)) score += 2000;
          if (/images\.silpo\.ua|img\d?\.zakaz\.ua|src\.zakaz\.atbmarket|varus\.ua\/img\/product/.test(url)) score += 500;
          candidates.push({ url, score });
        };
        for (const img of card.querySelectorAll('img')) {
          push(img.currentSrc, 50);
          push(img.getAttribute('src'), 40);
          push(img.getAttribute('data-src'), 45);
          push(img.getAttribute('data-original'), 45);
          push(img.getAttribute('data-lazy-src'), 40);
          push(img.getAttribute('data-image'), 40);
          const srcset = img.getAttribute('srcset') || img.getAttribute('data-srcset') || '';
          srcset.split(',').forEach((part) => {
            const bit = part.trim().split(/\s+/)[0];
            const w = Number((part.match(/(\d+)w/) || [])[1] || 0);
            push(bit, w / 10);
          });
        }
        for (const source of card.querySelectorAll('source[srcset], source[data-srcset]')) {
          const srcset = source.getAttribute('srcset') || source.getAttribute('data-srcset') || '';
          srcset.split(',').forEach((part) => push(part.trim().split(/\s+/)[0], 30));
        }
        // CSS background-image fallbacks (some Silpo cards).
        for (const node of [card, ...card.querySelectorAll('[style*="background"]')].slice(0, 12)) {
          const style = node.getAttribute?.('style') || '';
          const match = style.match(/url\(["']?([^"')]+)["']?\)/i);
          if (match) push(match[1], 20);
        }
        candidates.sort((a, b) => b.score - a.score);
        return candidates[0]?.url || '';
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
              .filter((url) => isProductURL(url))
          );
          if (productURLs.size > 1) break;
          if (productURLs.size === 1 && (/(?:₴|грн\.?|uah)/i.test(node.textContent || '') || isVarus || isSilpo)) {
            candidate = node;
          }
          node = node.parentElement;
        }
        return candidate || link.closest(
          '[data-testid*="product" i], [data-test*="product" i], [class*="product-card" i], [class*="productitem" i], [class*="ProductCard" i], article, li'
        ) || link.parentElement;
      };

      const links = [...document.querySelectorAll('a[href]')]
        .filter((link) => isProductURL(absolute(link.href)));

      for (const link of links) {
        const card = cardForProductLink(link);
        if (!card) continue;

        const heading = card.querySelector('h1, h2, h3, h4, [class*="title" i], [class*="name" i], [data-testid*="title" i]');
        const imageURL = bestImageFromCard(card);
        const name = clean(
          heading?.textContent ||
          link.textContent ||
          link.getAttribute('aria-label') ||
          link.getAttribute('title') ||
          card.querySelector('img')?.getAttribute('alt')
        );

        const explicitOldNode = card.querySelector(
          '[data-marker*="Old Price" i], [class*="oldPrice" i], [class*="old-price" i], [class*="price-old" i], [class*="special_price" i] ~ *, del, s'
        );
        const explicitDiscountedNode = card.querySelector(
          '[data-marker*="Discounted Price" i], [class*="price_discount" i], [class*="discountedPrice" i], [class*="sale-price" i], [class*="new-price" i], [class*="special_price" i], [class*="finalPrice" i]'
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
          const isOld = /old|previous|regular|cross|strike|before|base|minor|through/.test(marker) || node.matches('del, s');
          (isOld ? oldValues : currentValues).push(...values);
        }

        if (!currentValues.length) currentValues.push(...moneyValues(card.textContent));
        let price = explicitDiscountedPrice || currentValues[0] || 0;
        let originalPrice = explicitOldPrice || oldValues[0] || 0;
        if (!originalPrice && currentValues.length > 1) {
          const firstPair = currentValues.slice(0, 2);
          if (firstPair[0] !== firstPair[1]) {
            price = Math.min(...firstPair);
            originalPrice = Math.max(...firstPair);
          }
        }
        if (originalPrice && originalPrice > price && currentValues.length) {
          // Prefer the lower visible amount as the shelf/promo price.
          const lower = Math.min(...currentValues.filter((v) => v > 0));
          if (lower && lower < originalPrice) price = lower;
        }

        const promotionNode = card.querySelector(
          '[data-marker*="Promotion_until_date" i], [class*="discountDisclaimer" i], [class*="promotion" i][class*="date" i], [class*="promo" i][class*="date" i]'
        );
        const promotionTextMatch = clean(card.innerText || card.textContent).match(
          /(?:до|по|until|through|діє[^\n]{0,40}(?:до|по))\s*\d{1,2}[./-]\d{1,2}(?:[./-]\d{2,4})?/i
        );

        add({
          name,
          price,
          originalPrice,
          imageURL,
          sourceURL: link.href,
          priceText: (isATB || isSilpo) ? (card.innerText || card.textContent) : '',
          priceUnit: clean(card.getAttribute('data-unit') || card.querySelector('[data-unit]')?.getAttribute('data-unit')),
          promotionText: clean(promotionNode?.textContent || promotionTextMatch?.[0]),
          sourcePriority: isATB ? 4 : 1
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
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Stay close to mobile Safari — store CDNs / Cloudflare are less hostile than custom bots.
        configuration.applicationNameForUserAgent = "Mobile/15E148"

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
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

    static func dismantleUIView(_ webView: WKWebView, coordinator _: Coordinator) {
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
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
                decisionHandler(.allow)
                return
            }
            decisionHandler(brand.acceptsCatalogURL(url) ? .allow : .cancel)
        }

        func webView(
            _: WKWebView,
            didStartProvisionalNavigation _: WKNavigation!
        ) {
            generation = UUID()
            state.continueLoading()
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            let currentGeneration = generation
            // Silpo/ATB may spend longer on Cloudflare/client render before cards exist.
            let delays: [TimeInterval] = [0.25, 1.0, 2.2, 4.0, 6.5]
            for (index, delay) in delays.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                    guard let self,
                          let webView,
                          generation == currentGeneration else { return }
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
            _: WKWebView,
            didFail _: WKNavigation!,
            withError error: Error
        ) {
            state.show(error: error)
        }

        func webView(
            _: WKWebView,
            didFailProvisionalNavigation _: WKNavigation!,
            withError error: Error
        ) {
            state.show(error: error)
        }

        func userContentController(
            _: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageName,
                  let body = message.body as? [String: Any],
                  let values = body["products"] as? [[String: Any]] else { return }

            guard let pageURL = (message.webView?.url) ?? requestedURL else { return }
            let pageCategory = brand.productCategory(forCatalogURL: pageURL)
            let fetchedAt = Date()
            let isDetailPage = OfficialCatalogProductQuality.isAcceptableProductURL(pageURL)

            let products = values.compactMap { value -> OfficialCatalogProduct? in
                guard let sourceValue = value["sourceURL"] as? String,
                      let sourceURL = URL(string: sourceValue),
                      brand.acceptsCatalogURL(sourceURL),
                      let rawName = value["name"] as? String
                else {
                    return nil
                }
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                let atbPriceInfo = (value["priceText"] as? String).flatMap { text in
                    sourceURL.host?.lowercased().hasSuffix("atbmarket.com") == true
                        ? OfficialCatalogPriceParser.atbPriceInfo(from: text)
                        : nil
                }
                guard let price = atbPriceInfo?.price
                    ?? OfficialCatalogPriceParser.value(from: value["price"])
                else {
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
                let promotionRaw = value["promotionEnd"]
                    ?? value["promotionText"]
                    ?? value["priceText"]
                let promotionEndsAt = originalPrice == nil
                    ? nil
                    : OfficialCatalogPromotionParser.expiryDate(
                        from: promotionRaw,
                        fetchedAt: fetchedAt
                    )
                // Some official promo pages keep expired cards in their HTML. Do not
                // present their discounted price as current when the source date is past.
                if originalPrice != nil,
                   let promotionEndsAt,
                   promotionEndsAt <= fetchedAt
                {
                    return nil
                }
                let priceBasis = OfficialCatalogPriceBasisParser.parse(
                    rawUnit: value["priceUnit"],
                    priceText: (value["priceText"] as? String) ?? "",
                    productName: name
                )
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
                return OfficialCatalogProductQuality.sanitize(
                    name: name,
                    price: price,
                    originalPrice: originalPrice,
                    loyaltyPrice: loyaltyPrice,
                    imageURL: imageURL,
                    sourceURL: sourceURL,
                    storeName: brand.name,
                    details: parsedDetails.isEmpty ? nil : parsedDetails,
                    pageCategory: pageCategory,
                    priceQuantity: priceBasis.quantity,
                    priceUnit: priceBasis.unit,
                    promotionEndsAt: promotionEndsAt,
                    fetchedAt: fetchedAt,
                    isDetailVerified: isDetailPage
                )
            }
            state.merge(products)
        }
    }
}

struct OfficialCatalogSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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
            // Prefer store aisle (pageCategory). Name inference is only a fallback for mixed pages.
            let matchesCategory: Bool = {
                guard let selectedCategory else { return true }
                if let pageCategory = product.pageCategory {
                    return pageCategory == selectedCategory
                }
                return product.category == selectedCategory
            }()
            let matchesHouseholdRoute: Bool = {
                guard isShowingHouseholdRoute else { return true }
                // Trust the store household shelf when we actually loaded it.
                if product.pageCategory == .household { return true }
                return OfficialCatalogProductQuality.isPlausibleForHouseholdRoute(product)
            }()
            return matchesSearch && matchesCategory && matchesHouseholdRoute
        }
        return sort.apply(to: filtered)
    }

    private var selectedRoute: StoreCatalogRoute? {
        brand.catalogRoutes.first { $0.id == selectedRouteID }
    }

    private var isShowingDiscounts: Bool {
        selectedRoute?.isDiscountRoute == true
    }

    private var isShowingHouseholdRoute: Bool {
        selectedRoute?.title == "Для дома" || selectedCategory == .household
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
        ProductCategory.allCases.filter { category in
            !brand.catalogURLs(for: category).isEmpty
                || browser.products.contains { $0.pageCategory == category }
        }
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
            OfficialCatalogProductDetailSheet(
                product: product,
                brand: brand,
                canAdd: model.canEdit && !addedProductIDs.contains(product.id),
                onVerified: { verifiedProduct in
                    browser.merge([verifiedProduct])
                },
                onAdd: { verifiedProduct in
                    browser.merge([verifiedProduct])
                    add(verifiedProduct)
                }
            )
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                browser.reloadIfPriceExpiredOrStale()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { browser.reloadIfPriceExpiredOrStale() }
        }
        .onChange(of: browser.products) { products in
            let snapshots = products
                .filter(\.isDetailVerified)
                .map {
                    CatalogPriceSnapshot(
                        sourceURL: $0.sourceURL.absoluteString,
                        price: $0.price,
                        originalPrice: $0.discountPercent == nil ? nil : $0.originalPrice,
                        loyaltyPrice: $0.loyaltyPrice,
                        fetchedAt: $0.fetchedAt,
                        promotionEndsAt: $0.promotionEndsAt
                    )
                }
            guard !snapshots.isEmpty else { return }
            Task { await model.refreshCatalogPrices(in: listID, snapshots: snapshots) }
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
                          let categoryURL = brand.catalogURLs(for: category).first
                {
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
            brand.completeCatalogURLs
        case "Для дома":
            brand.catalogURLs(for: .household)
        default:
            []
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if browser.isLoading, browser.products.isEmpty {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(0 ..< 7, id: \.self) { _ in
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
            if browser.isExhausted {
                nativeStatusView(
                    image: "magnifyingglass",
                    title: "Ничего не найдено",
                    message: "Проверен весь доступный официальный каталог. Измените запрос или категорию.",
                    buttonTitle: "Сбросить фильтры"
                ) {
                    searchText = ""
                    selectedCategory = nil
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Ищем во всём официальном каталоге…")
                        .font(.subheadline.weight(.semibold))
                    Text("Загружаем следующие страницы и разделы магазина.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { browser.loadMore() }
                .id("catalog-empty-loader-\(browser.products.count)-\(destinationURL.absoluteString)")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(displayedProducts) { product in
                        catalogProductRow(product)
                    }

                    if !browser.isExhausted {
                        HStack {
                            Spacer()
                            if browser.isLoadingMore {
                                ProgressView()
                                    .controlSize(.regular)
                                    .padding(.vertical, 12)
                            } else {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear { browser.loadMore() }
                            }
                            Spacer()
                        }
                        .id(
                            "catalog-loader-\(browser.products.count)-\(selectedRouteID)-\(selectedCategory?.id ?? "all")"
                        )
                    }
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
                                .foregroundColor(product.discountPercent == nil ? .primary : .red)
                            if let oldPrice = product.originalPrice, product.discountPercent != nil {
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
                            Text(product.priceBasisLabel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let loyaltyPrice = product.loyaltyPrice {
                            Text("\(loyaltyPrice.oneCartCurrency) с картой ATB")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(OneCartPalette.primaryStrong)
                        }
                        if let promotionEndsAt = product.promotionEndsAt,
                           product.discountPercent != nil
                        {
                            CatalogPromotionCountdown(endsAt: promotionEndsAt, compact: true)
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
                selectedProduct = product
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
            .accessibilityLabel("Проверить цену и добавить \(product.name)")
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

struct CatalogPromotionCountdown: View {
    let endsAt: Date
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let remaining = endsAt.timeIntervalSince(context.date)
            Label(
                remaining > 0
                    ? "До конца акции \(CatalogCountdownFormatter.string(from: remaining))"
                    : "Акция завершена — цена требует обновления",
                systemImage: remaining > 0 ? "timer" : "exclamationmark.triangle.fill"
            )
            .font(compact ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundColor(remaining > 0 ? .orange : .red)
            .lineLimit(compact ? 1 : nil)
        }
    }
}

enum CatalogCountdownFormatter {
    static func string(from interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded(.down)), 0)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days) д. \(hours) ч." }
        if hours > 0 { return "\(hours) ч. \(minutes) мин." }
        return "\(max(minutes, 1)) мин."
    }
}

enum CatalogDateFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Europe/Kyiv")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

private struct OfficialCatalogProductDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @StateObject private var verifier = OfficialCatalogBrowserState()
    @State private var serverProduct: OfficialCatalogProduct?
    @State private var isServerVerifying = true

    let product: OfficialCatalogProduct
    let brand: StoreBrand
    let canAdd: Bool
    let onVerified: (OfficialCatalogProduct) -> Void
    let onAdd: (OfficialCatalogProduct) -> Void

    private var currentProduct: OfficialCatalogProduct {
        let base = serverProduct
            ?? verifier.products.first(where: { $0.id == product.id })
            ?? verifier.products.first
            ?? product
        return base.mergingMissingMedia(from: product)
    }

    private var isVerificationLoading: Bool {
        !currentProduct.isDetailVerified && (isServerVerifying || verifier.isLoading)
    }

    private var displayImageURL: URL? {
        OfficialCatalogProductQuality.upgradedImageURL(currentProduct.imageURL)
            ?? currentProduct.imageURL
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    productHero
                    priceCard
                    infoCard

                    if let summary = currentProduct.details?.summary, !summary.isEmpty {
                        detailSection(title: "О товаре", text: summary)
                    }
                    if let ingredients = currentProduct.details?.ingredients, !ingredients.isEmpty {
                        detailSection(title: "Состав", text: ingredients)
                    }

                    Button {
                        onAdd(currentProduct)
                        dismiss()
                    } label: {
                        Label("Добавить", systemImage: "cart.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
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
        .background(
            OfficialCatalogDataBridge(
                brand: brand,
                destinationURL: product.sourceURL,
                continuationURLs: [],
                state: verifier
            )
            .frame(width: 390, height: 844)
            .opacity(0.001)
            .allowsHitTesting(false)
        )
        .task(id: product.id) {
            await verifyOnServer()
        }
        .onChange(of: verifier.products) { products in
            guard serverProduct == nil,
                  let verified = products.first(where: { $0.isDetailVerified }) else { return }
            onVerified(verified)
        }
    }

    @ViewBuilder
    private var verificationCard: some View {
        if currentProduct.isDetailVerified {
            Label(
                "Цена проверена в оригинальной карточке магазина",
                systemImage: "checkmark.shield.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.green)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        } else if isVerificationLoading {
            Label("Проверяем цену в оригинальной карточке…", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OneCartPalette.surface, in: RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Не удалось подтвердить цену", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                Text("Добавление заблокировано, чтобы в список не попала неподтверждённая цена.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Проверить ещё раз") {
                    verifier.reload()
                    Task { await verifyOnServer() }
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func verifyOnServer() async {
        isServerVerifying = true
        let verified = await model.verifyOfficialCatalogProduct(product, brand: brand)
        guard !Task.isCancelled else { return }
        serverProduct = verified
        isServerVerifying = false
        if let verified { onVerified(verified) }
    }

    private var productHero: some View {
        VStack(spacing: 14) {
            // Unified white studio plate for every product (transparent looked mixed).
            Group {
                if let imageURL = displayImageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(16)
                        case .failure:
                            heroFallback
                        case .empty:
                            ZStack {
                                heroFallback
                                ProgressView()
                            }
                        @unknown default:
                            heroFallback
                        }
                    }
                } else {
                    heroFallback
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 240, maxHeight: 320)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
            )

            VStack(spacing: 6) {
                Text(currentProduct.name)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(currentProduct.storeName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var heroFallback: some View {
        VStack(spacing: 10) {
            Image(systemName: currentProduct.category.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(OneCartPalette.primary.opacity(0.78))
            Text(currentProduct.category.localizedName)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Цена")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(currentProduct.price.oneCartCurrency)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(currentProduct.discountPercent == nil ? .primary : .red)
                if let oldPrice = currentProduct.originalPrice,
                   currentProduct.discountPercent != nil
                {
                    Text(oldPrice.oneCartCurrency)
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                if let discount = currentProduct.discountPercent {
                    Text("−\(discount)%")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red, in: Capsule())
                }
            }

            Text(currentProduct.priceBasisLabel)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let promotionEndsAt = currentProduct.promotionEndsAt,
               currentProduct.discountPercent != nil
            {
                CatalogPromotionCountdown(endsAt: promotionEndsAt, compact: false)
            }

            if let loyaltyPrice = currentProduct.loyaltyPrice {
                Label("\(loyaltyPrice.oneCartCurrency) с картой ATB", systemImage: "creditcard.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(OneCartPalette.primaryStrong)
            } else if currentProduct.discountPercent != nil {
                Text("Акционная цена")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Актуальная цена")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(OneCartPalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Информация")
                .font(.headline)

            factRow(title: "Магазин", value: currentProduct.storeName)
            factRow(title: "Категория", value: currentProduct.category.localizedName)
            factRow(title: "Получена", value: CatalogDateFormatter.string(from: currentProduct.fetchedAt))

            if let producer = currentProduct.details?.producer, !producer.isEmpty {
                factRow(title: "Производитель", value: producer)
            }
            if let country = currentProduct.details?.country, !country.isEmpty {
                factRow(title: "Страна", value: country)
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
