import Foundation

enum ProductCategory: String, CaseIterable, Identifiable {
    case meatPoultry
    case fishSeafood
    case dairyEggs
    case grocery
    case oilCanned
    case produce
    case frozen
    case bakery
    case saucesSpices
    case alcohol
    case coldDrinks
    case hotDrinks
    case sweetsSnacks
    case babyFood
    case household
    case other

    var id: String {
        rawValue
    }

    static func resolved(storedRawValue: String?) -> ProductCategory {
        let raw = storedRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let value = ProductCategory(rawValue: raw) {
            return value
        }
        switch raw {
        case "fresh", "produce":
            return .produce
        case "meat", "deli":
            return .meatPoultry
        case "dairy":
            return .dairyEggs
        case "drinks":
            return .coldDrinks
        default:
            return .other
        }
    }

    static func groupedSections<Item>(
        from items: [Item],
        category: (Item) -> ProductCategory
    ) -> [(category: ProductCategory, items: [Item])] {
        var buckets: [ProductCategory: [Item]] = [:]
        for item in items {
            let key = category(item)
            buckets[key, default: []].append(item)
        }
        return allCases.compactMap { key in
            guard let group = buckets[key], !group.isEmpty else { return nil }
            return (key, group)
        }
    }

    static func inferred(from productName: String) -> ProductCategory {
        let value = productName.lowercased()
        let tokens = value.split { !$0.isLetter && !$0.isNumber }
        for rule in inferenceRules where rule.matches(value, tokens: tokens) {
            return rule.category
        }
        return .other
    }

    // MARK: - Inference rules

    private struct CategoryRule {
        let keywords: [String]
        let prefixes: [String]
        /// Words that match only as a whole word, for stems that start too many unrelated
        /// words ("bun" in "bunch" and "bundle", "egg" in "eggplant").
        var wholeWords: [String] = []
        let category: ProductCategory

        func matches(_ value: String, tokens: [Substring]) -> Bool {
            keywords.contains { Self.keyword($0, matches: value, tokens: tokens) }
                || wholeWords.contains { word in tokens.contains { $0 == word } }
                || prefixes.contains { value.hasPrefix($0) }
        }

        /// Short keywords collide inside unrelated words ("tea" in "steak",
        /// "ham" in "shampoo", "oil" in "toilet"), so they match on word
        /// boundaries only. Stems of up to three characters must start a word;
        /// four-character ones may also end it ("cheesecake", "swordfish").
        /// Longer keywords keep substring matching for compounds and inflections.
        private static func keyword(_ keyword: String, matches value: String, tokens: [Substring]) -> Bool {
            switch keyword.count {
            case ...3:
                tokens.contains { $0.hasPrefix(keyword) }
            case 4:
                tokens.contains { $0.hasPrefix(keyword) || $0.hasSuffix(keyword) }
            default:
                value.contains(keyword)
            }
        }
    }

    private static let inferenceRules: [CategoryRule] = [
        // Names that contain another rule's keyword ("butter", "сир" in "сироп"); checked first.
        CategoryRule(
            keywords: ["peanut butter", "арахисов", "сироп", "syrup"],
            prefixes: [],
            category: .grocery
        ),
        CategoryRule(
            keywords: ["eggplant", "watermelon", "watercress", "butternut"],
            prefixes: [],
            category: .produce
        ),
        CategoryRule(
            keywords: ["детск", "дитяч", "пюре", "смесь", "суміш", "baby", "infant", "formula"],
            prefixes: [],
            category: .babyFood
        ),
        CategoryRule(
            keywords: [
                "морожен", "мороженое", "пельмен", "вареник", "заморож", "наггетс",
                "ice cream", "frozen", "dumpling", "nugget",
            ],
            prefixes: [],
            category: .frozen
        ),
        CategoryRule(
            keywords: [
                "конфет", "шоколад", "торт", "печенье", "печив", "чипс", "снек", "вафл",
                "зефир", "маршмел", "попкорн", "candy", "chocolate", "cookie", "cake",
                "chips", "snack", "cracker", "waffle",
            ],
            prefixes: [],
            category: .sweetsSnacks
        ),
        CategoryRule(
            keywords: [
                "хлеб", "хліб", "батон", "булк", "лаваш", "выпеч", "круассан", "бублик",
                "багет", "bread", "bakery", "bagel", "pastry", "croissant", "lavash",
            ],
            prefixes: [],
            wholeWords: ["bun", "buns"],
            category: .bakery
        ),
        CategoryRule(
            keywords: [
                "вино", "пиво", "водк", "віскі", "виски", "коньяк", "шампан", "алкогол",
                "beer", "wine", "vodka", "whisky", "whiskey", "alcohol", "cider",
            ],
            prefixes: [],
            category: .alcohol
        ),
        CategoryRule(
            keywords: ["кава", "кофе", "чай", "какао", "coffee", "tea", "cocoa", "hot chocolate"],
            prefixes: [],
            category: .hotDrinks
        ),
        CategoryRule(
            keywords: [
                "сок", "вода", "кола", "газиров", "лимонад", "квас", "juice", "water",
                "cola", "soda", "lemonade", "drink",
            ],
            prefixes: [],
            category: .coldDrinks
        ),
        CategoryRule(
            keywords: [
                "соус", "специ", "кетчуп", "майонез", "гірчиц", "горчиц", "приправ",
                "перец", "перець", "sauce", "spice", "ketchup", "mayo", "mustard",
                "seasoning",
            ],
            prefixes: [],
            category: .saucesSpices
        ),
        CategoryRule(
            keywords: [
                "олі", "олія", "уксус", "оцет", "консерв", "масло растит", "подсолнеч",
                "оливков", "vinegar", "canned", "olive oil", "sunflower",
            ],
            prefixes: [],
            category: .oilCanned
        ),
        CategoryRule(
            keywords: [
                "молоко", "йогурт", "сыр", "сир", "кефир", "кефір", "ряженк", "сметан",
                "творог", "яйц", "масло сливоч", "milk", "yogurt", "yoghurt", "cheese",
                "butter", "kefir", "cottage", "sour cream",
            ],
            prefixes: [],
            wholeWords: ["egg", "eggs"],
            category: .dairyEggs
        ),
        CategoryRule(
            keywords: [
                "рыб", "риб", "морепродукт", "кревет", "лосос", "тунц", "селед", "оселед",
                "икр", "fish", "seafood", "shrimp", "salmon", "tuna", "crab",
            ],
            prefixes: [],
            category: .fishSeafood
        ),
        CategoryRule(
            keywords: [
                "мясо", "мʼясо", "м’ясо", "курица", "курка", "фарш", "индейк", "говяд",
                "свинин", "баранин", "колбас", "ковбас", "сосис", "ветчин", "бекон",
                "стейк", "филе", "meat", "chicken", "beef", "pork", "turkey", "sausage",
                "ham", "bacon", "steak", "mince", "poultry",
            ],
            prefixes: [],
            category: .meatPoultry
        ),
        CategoryRule(
            keywords: [
                "круп", "макарон", "мук", "сахар", "цукор", "соль", "хлопья", "рис",
                "гречк", "овсян", "каша", "pasta", "flour", "sugar", "salt", "cereal",
                "rice", "oat", "buckwheat", "grocery", "porridge", "grits",
            ],
            prefixes: ["каш"],
            category: .grocery
        ),
        CategoryRule(
            keywords: [
                "яблок", "банан", "овощ", "фрукт", "помидор", "огірок", "томат", "зелен",
                "ягод", "огурец", "капуст", "морков", "баклажан", "арбуз", "кавун", "дын", "диня", "дині", "диню",
                "тыкв", "гарбуз", "кабач", "apple", "banana", "tomato", "fruit",
                "vegetable", "salad", "cucumber", "lemon", "potato", "onion", "carrot",
                "berry", "greens", "lettuce", "melon", "squash", "pumpkin", "zucchini",
            ],
            prefixes: [],
            category: .produce
        ),
        CategoryRule(
            keywords: [
                "мыло", "мило", "порошок", "шампун", "средств", "засіб", "soap",
                "detergent", "shampoo", "laundry", "cleaner", "bleach",
            ],
            prefixes: [],
            category: .household
        ),
        // Generic "oil" after more specific oilCanned phrases
        CategoryRule(
            keywords: ["oil"],
            prefixes: [],
            category: .oilCanned
        ),
    ]
}
