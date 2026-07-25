import Foundation

enum OfficialCatalogPromotionParser {
    private static let kyivTimeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current

    static func expiryDate(from rawValue: Any?, fetchedAt: Date = Date()) -> Date? {
        guard let rawValue else { return nil }
        if let seconds = rawValue as? NSNumber {
            let value = seconds.doubleValue
            guard value > 0 else { return nil }
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }

        let text = String(describing: rawValue)
            .replacingOccurrences(of: " ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kyivTimeZone
        let fetchedComponents = calendar.dateComponents([.year], from: fetchedAt)
        let currentYear = fetchedComponents.year ?? 2026

        let fullPattern = #"(?<!\d)(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?!\d)"#
        if let components = lastComponents(in: text, pattern: fullPattern),
           components.count == 3,
           let year = Int(components[0]),
           let month = Int(components[1]),
           let day = Int(components[2])
        {
            return endOfDay(year: year, month: month, day: day, calendar: calendar)
        }

        let localizedPattern = #"(?<!\d)(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?(?!\d)"#
        guard let components = lastComponents(in: text, pattern: localizedPattern),
              components.count >= 2,
              let day = Int(components[0]),
              let month = Int(components[1]) else { return nil }

        var year = components.count > 2 ? Int(components[2]) : nil
        if let value = year, value < 100 { year = 2000 + value }
        if year == nil { year = currentYear }
        guard var result = endOfDay(
            year: year ?? currentYear,
            month: month,
            day: day,
            calendar: calendar
        ) else { return nil }

        if components.count <= 2,
           fetchedAt.timeIntervalSince(result) > 180 * 24 * 60 * 60,
           let nextYear = endOfDay(
               year: (year ?? currentYear) + 1,
               month: month,
               day: day,
               calendar: calendar
           )
        {
            result = nextYear
        }
        return result
    }

    private static func lastComponents(in text: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        guard let match = matches.last else { return nil }
        return (1 ..< match.numberOfRanges).compactMap { index in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func endOfDay(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) -> Date? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return nextDay.addingTimeInterval(-1)
    }
}

enum OfficialCatalogPriceBasisParser {
    static func parse(
        rawUnit: Any?,
        priceText: String,
        productName: String
    ) -> (quantity: Double, unit: ProductUnit) {
        let unit = StoreBrand.normalize(String(describing: rawUnit ?? ""))
        switch unit {
        case "kg", "kilogram", "кілограм", "кг": return (1, .kg)
        case "g", "gram", "г": return (1, .g)
        case "l", "liter", "літр", "л": return (1, .l)
        case "ml", "milliliter", "мл": return (1, .ml)
        case "pack", "package", "уп", "упаковка": return (1, .pack)
        case "pcs", "pc", "piece", "шт", "штука": return (1, .piece)
        default: break
        }

        let text = StoreBrand.normalize(priceText)
        let patterns: [(String, ProductUnit)] = [
            (#"(?:за|/)\s*(\d+(?:[.,]\d+)?)?\s*кг\b"#, .kg),
            (#"(?:за|/)\s*(\d+(?:[.,]\d+)?)?\s*г\b"#, .g),
            (#"(?:за|/)\s*(\d+(?:[.,]\d+)?)?\s*л\b"#, .l),
            (#"(?:за|/)\s*(\d+(?:[.,]\d+)?)?\s*мл\b"#, .ml),
            (#"(?:за|/)\s*(\d+(?:[.,]\d+)?)?\s*шт\b"#, .piece),
        ]
        for (pattern, productUnit) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                      in: text,
                      range: NSRange(text.startIndex..., in: text)
                  ) else { continue }
            var quantity = 1.0
            if match.numberOfRanges > 1,
               match.range(at: 1).location != NSNotFound,
               let range = Range(match.range(at: 1), in: text)
            {
                quantity = Double(text[range].replacingOccurrences(of: ",", with: ".")) ?? 1
            }
            return (max(quantity, 0.001), productUnit)
        }

        _ = productName
        return (1, .piece)
    }
}

enum OfficialCatalogProductQuality {
    static let minimumPrice = 1.0
    static let maximumPrice = 50000.0

    private static let junkNamePattern = try! NSRegularExpression(
        pattern: #"""
        (?xi)
        ^(
            каталог|catalog|акци[яі]|знижк|скидк|меню|menu|пошук|search|
            увійти|войти|login|кошик|корзина|cart|cookie|файли?|file|download|
            pdf|doc|xlsx?|csv|zip|rar|показати\s+ще|завантажити|load\s+more|
            спосіб\s+доставки|способ\s+доставки|оберіть\s+спосіб|выберите\s+способ|
            оберіть\s+магазин|выберите\s+магазин|оберіть\s+адресу|выберите\s+адрес|
            особистий\s+кабінет|личный\s+кабинет|вхід|вход|реєстрація|регистрация|
            оформити\s+замовлення|оформить\s+заказ|оплата|доставка|служба\s+підтримки|
            контакти|о\s+нас|про\s+нас|головна|главная|всі\s+товари|все\s+товары
        )$
        |
        \.(pdf|docx?|xlsx?|csv|zip|rar|jpe?g|png|gif|webp|svg|mp4|json)$
        |
        (?xi)\b(оберіть\s+спосіб|выберите\s+способ|спосіб\s+доставки|способ\s+доставки|оберіть\s+магазин|выберите\s+магазин|особистий\s+кабінет|личный\s+кабинет|оформити\s+замовлення|оформить\s+заказ)\b
        """#
    )

    private static let productPathPattern = try! NSRegularExpression(
        pattern: #"/(product|products|p)(/|$)"#,
        options: .caseInsensitive
    )

    private static let fileExtensionPattern = try! NSRegularExpression(
        pattern: #"\.(pdf|docx?|xlsx?|csv|zip|rar|jpe?g|png|gif|webp|svg|mp4|json|txt)(/|$|\?)"#,
        options: .caseInsensitive
    )

    private static let varusReservedSlugs: Set<String> = [
        "cart", "checkout", "login", "account", "search", "catalog", "category",
        "own-clean", "own-trademarks", "ru", "uk", "ua", "assets", "img", "static",
        "blog", "promo", "promotions", "delivery", "about", "contacts", "brands",
    ]

    static func cleanTitle(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return rawName }

        let storeTailPattern = #"""
        (?xi)
        \s*[★⭐☆|•\-\—\–]?\s*
        \b(
            АТБ[- ]?Маркет|АТБ|
            Сільпо|Сильпо|Silpo|
            Varus|VARUS|Варус|
            Ашан|Auchan|
            Новус|Novus|
            Метро|Metro|
            Zakaz(?:\.ua)?|
            Фора|Fora
        )\b
        \s*$
        """#
        if let regex = try? NSRegularExpression(pattern: storeTailPattern) {
            let range = NSRange(name.startIndex..., in: name)
            name = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        }

        let seoPatterns = [
            #"(?xi)\b(купити|купить)\s+в\s+(києві|україні|днепре|днепропетровске|харькове|одессе|львове|запорожье)\b[^\n]*"#,
            #"(?xi)\b(купити|купить)\s+за\s+ціною\s+(від\s+)?\d+(?:[.,]\d+)?[^\n]*"#,
            #"(?xi)\b(купити|купить)\s+по\s+цене\s+(от\s+)?\d+(?:[.,]\d+)?[^\n]*"#,
            #"(?xi)\bза\s+ціною\s+(від\s+)?\d+(?:[.,]\d+)?\s*(грн|грн\.)?[^\n]*"#,
            #"(?xi)\bпо\s+цене\s+(от\s+)?\d+(?:[.,]\d+)?\s*(грн|грн\.)?[^\n]*"#,
            #"(?xi)\b(в\s+інтернет[- ]магазині|в\s+интернет[- ]магазине)\b[^\n]*"#,
            #"(?xi)\b(з\s+доставкою\s+по|с\s+доставкой\s+по)\b[^\n]*"#,
        ]

        for pattern in seoPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(name.startIndex..., in: name)
                name = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
            }
        }

        let cleanupPattern = #"""
        (?x)
        ^[\s★⭐☆|•\-\—\–,:;]+|[\s★⭐☆|•\-\—\–,:;]+$
        """#
        if let regex = try? NSRegularExpression(pattern: cleanupPattern) {
            let range = NSRange(name.startIndex..., in: name)
            name = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        }

        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return name.isEmpty ? rawName : name
    }

    static func cleanSummary(_ rawSummary: String?, productName: String = "") -> String? {
        guard let rawSummary else { return nil }
        var text = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        text = text.unicodeScalars.filter { !($0.properties.isEmoji && $0.properties.isEmojiPresentation) }
            .map(String.init).joined()

        let adPatterns = [
            #"(?xi)\b(купити|купить)\s+в\s+[^.\n]*"#,
            #"(?xi)\b(доставка\s+додому|доставка\s+на\s+дом|по\s+всій\s+україні|по\s+всей\s+украине)\b[^.\n]*"#,
            #"(?xi)\b(великий\s+вибір|большой\s+выбор)\b[^.\n]*"#,
            #"(?xi)\b(контроль\s+якості|контроль\s+качества)\b[^.\n]*"#,
            #"(?xi)\b(низькими\s+цінами|низким\s+ценам|кращі\s+ціни|лучшие\s+цены)\b[^.\n]*"#,
            #"(?xi)\b(0-800-\d+|\bгаряча\s+лінія\b|\bгорячая\s+линия\b)\b[^.\n]*"#,
            #"(?xi)\b(в\s+супермаркеті|в\s+супермаркете|в\s+інтернет[- ]магазині|в\s+интернет[- ]магазине)\b[^.\n]*"#,
        ]

        for pattern in adPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            }
        }

        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,-–—:;!")))

        if !productName.isEmpty {
            let punctuation = CharacterSet.punctuationCharacters
                .union(.symbols)
                .union(.whitespacesAndNewlines)
            let normSummary = StoreBrand.normalize(text)
                .components(separatedBy: punctuation)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let normName = StoreBrand.normalize(productName)
                .components(separatedBy: punctuation)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if normSummary == normName || normSummary.isEmpty {
                return nil
            }
        }

        return text.isEmpty ? nil : text
    }

    static func isAcceptableName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 180 else { return false }
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 2 else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return junkNamePattern.firstMatch(in: trimmed, range: range) == nil
    }

    static func isAcceptableProductURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path
        let range = NSRange(path.startIndex..., in: path)
        if fileExtensionPattern.firstMatch(in: path, range: range) != nil { return false }
        let lowered = path.lowercased()
        let blockedFragments = [
            "/cart", "/checkout", "/login", "/account", "/search",
            "/static/", "/assets/", "/media/files", "/download",
            "/category/", "/categories/", "/catalog/",
        ]
        if blockedFragments.contains(where: { lowered.contains($0) }) { return false }

        if productPathPattern.firstMatch(in: path, range: range) != nil {
            return true
        }

        if host == "varus.ua" || host.hasSuffix(".varus.ua") {
            let segments = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            guard segments.count == 1 else { return false }
            let slug = segments[0].lowercased()
            return slug.count >= 4
                && !varusReservedSlugs.contains(slug)
                && !slug.contains(".")
                && slug.contains(where: \.isLetter)
        }

        return false
    }

    static func sanitizedPrices(
        price: Double,
        originalPrice: Double?,
        loyaltyPrice: Double?
    ) -> (price: Double, originalPrice: Double?, loyaltyPrice: Double?)? {
        guard price >= minimumPrice, price <= maximumPrice else { return nil }

        let cleanOriginal: Double?
        if let originalPrice,
           originalPrice > price,
           originalPrice <= maximumPrice
        {
            let ratio = originalPrice / price
            cleanOriginal = ratio <= 10.0 ? originalPrice : nil
        } else {
            cleanOriginal = nil
        }

        let cleanLoyalty: Double? = if let loyaltyPrice,
                                       loyaltyPrice >= minimumPrice,
                                       loyaltyPrice < price
        {
            loyaltyPrice
        } else {
            nil
        }

        if let cleanOriginal {
            let percent = ((cleanOriginal - price) / cleanOriginal) * 100
            if percent < 1 || percent > 90 {
                return (price, nil, cleanLoyalty)
            }
        }
        return (price, cleanOriginal, cleanLoyalty)
    }

    static func upgradedImageURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        var value = url.absoluteString
        value = value.replacingOccurrences(of: "://varus.ua:443/", with: "://varus.ua/")
        value = value.replacingOccurrences(of: "://www.varus.ua:443/", with: "://varus.ua/")
        let replacements = [
            ("s150x150", "s1350x1350"),
            ("s200x200", "s1350x1350"),
            ("s350x350", "s1350x1350"),
            ("s100x100", "s1350x1350"),
            ("/img/product/72/72/", "/img/product/420/420/"),
            ("/img/product/150/150/", "/img/product/420/420/"),
            ("/img/product/200/200/", "/img/product/420/420/"),
            ("/thumb/", "/"),
            ("_thumb.", "."),
            ("catalog_product_gal_mob_", "catalog_product_gal_"),
            ("/products/200x200/", "/products/744x744/"),
            ("/products/300x300/", "/products/744x744/"),
            ("/products/400x400/", "/products/744x744/"),
        ]
        for (from, to) in replacements {
            value = value.replacingOccurrences(of: from, with: to)
        }
        if value.hasPrefix("data:") { return nil }
        return URL(string: value) ?? url
    }

    static func isPlausibleForHouseholdRoute(_ product: OfficialCatalogProduct) -> Bool {
        switch product.category {
        case .produce, .dairy, .meat, .drinks:
            false
        case .household, .other:
            true
        }
    }

    static func sanitize(
        name: String,
        price: Double,
        originalPrice: Double?,
        loyaltyPrice: Double?,
        imageURL: URL?,
        sourceURL: URL,
        storeName: String,
        details: OfficialCatalogProductDetails?,
        pageCategory: ProductCategory? = nil,
        priceQuantity: Double = 1,
        priceUnit: ProductUnit = .piece,
        promotionEndsAt: Date? = nil,
        fetchedAt: Date = Date(),
        isDetailVerified: Bool = false
    ) -> OfficialCatalogProduct? {
        let cleanedName = cleanTitle(name)
        guard isAcceptableName(cleanedName), isAcceptableProductURL(sourceURL) else { return nil }
        guard let prices = sanitizedPrices(
            price: price,
            originalPrice: originalPrice,
            loyaltyPrice: loyaltyPrice
        ) else { return nil }

        let cleanedDetails = details?.sanitized(forProductName: cleanedName)

        return OfficialCatalogProduct(
            name: cleanedName,
            price: prices.price,
            originalPrice: prices.originalPrice,
            loyaltyPrice: prices.loyaltyPrice,
            imageURL: upgradedImageURL(imageURL),
            sourceURL: sourceURL,
            storeName: storeName,
            details: (cleanedDetails?.isEmpty ?? true) ? nil : cleanedDetails,
            pageCategory: pageCategory,
            priceQuantity: priceQuantity,
            priceUnit: priceUnit,
            promotionEndsAt: prices.originalPrice == nil ? nil : promotionEndsAt,
            fetchedAt: fetchedAt,
            isDetailVerified: isDetailVerified
        )
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
        let hasLoyaltyPrice = normalizedText.range(
            of: #"картк|карточк|atb\s*card|атб\s*card"#,
            options: .regularExpression
        ) != nil

        let originalPrice = secondaryValues.first(where: { $0 > price })
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
