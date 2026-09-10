import Foundation
import SwiftUI

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

    var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .meatPoultry: "common.category.meatPoultry"
        case .fishSeafood: "common.category.fishSeafood"
        case .dairyEggs: "common.category.dairyEggs"
        case .grocery: "common.category.grocery"
        case .oilCanned: "common.category.oilCanned"
        case .produce: "common.category.produce"
        case .frozen: "common.category.frozen"
        case .bakery: "common.category.bakery"
        case .saucesSpices: "common.category.saucesSpices"
        case .alcohol: "common.category.alcohol"
        case .coldDrinks: "common.category.coldDrinks"
        case .hotDrinks: "common.category.hotDrinks"
        case .sweetsSnacks: "common.category.sweetsSnacks"
        case .babyFood: "common.category.babyFood"
        case .household: "common.category.household"
        case .other: "common.category.other"
        }
    }

    var localizedName: String {
        switch self {
        case .meatPoultry: String(localized: "common.category.meatPoultry")
        case .fishSeafood: String(localized: "common.category.fishSeafood")
        case .dairyEggs: String(localized: "common.category.dairyEggs")
        case .grocery: String(localized: "common.category.grocery")
        case .oilCanned: String(localized: "common.category.oilCanned")
        case .produce: String(localized: "common.category.produce")
        case .frozen: String(localized: "common.category.frozen")
        case .bakery: String(localized: "common.category.bakery")
        case .saucesSpices: String(localized: "common.category.saucesSpices")
        case .alcohol: String(localized: "common.category.alcohol")
        case .coldDrinks: String(localized: "common.category.coldDrinks")
        case .hotDrinks: String(localized: "common.category.hotDrinks")
        case .sweetsSnacks: String(localized: "common.category.sweetsSnacks")
        case .babyFood: String(localized: "common.category.babyFood")
        case .household: String(localized: "common.category.household")
        case .other: String(localized: "common.category.other")
        }
    }

    var symbolName: String {
        switch self {
        case .meatPoultry: "fork.knife"
        case .fishSeafood: "fish.fill"
        case .dairyEggs: "cup.and.saucer.fill"
        case .grocery: "basket.fill"
        case .oilCanned: "shippingbox.fill"
        case .produce: "leaf.fill"
        case .frozen: "snowflake"
        case .bakery: "birthday.cake.fill"
        case .saucesSpices: "flame.fill"
        case .alcohol: "wineglass.fill"
        case .coldDrinks: "waterbottle.fill"
        case .hotDrinks: "mug.fill"
        case .sweetsSnacks: "party.popper.fill"
        case .babyFood: "stroller.fill"
        case .household: "bubbles.and.sparkles"
        case .other: "cart.fill"
        }
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
        for rule in inferenceRules where rule.matches(value) {
            return rule.category
        }
        return .other
    }

    // MARK: - Inference rules

    private struct CategoryRule {
        let keywords: [String]
        let prefixes: [String]
        let category: ProductCategory

        func matches(_ value: String) -> Bool {
            keywords.contains { value.contains($0) }
                || prefixes.contains { value.hasPrefix($0) }
        }
    }

    private static let inferenceRules: [CategoryRule] = [
        CategoryRule(
            keywords: ["детск", "дитяч", "пюре", "смесь", "суміш", "baby", "infant", "formula"],
            prefixes: [],
            category: .babyFood
        ),
        CategoryRule(
            keywords: ["морожен", "мороженое", "пельмен", "вареник", "заморож", "наггетс",
                       "ice cream", "frozen", "dumpling", "nugget"],
            prefixes: [],
            category: .frozen
        ),
        CategoryRule(
            keywords: ["конфет", "шоколад", "торт", "печенье", "печив", "чипс", "снек", "вафл",
                       "зефир", "маршмел", "попкорн", "candy", "chocolate", "cookie", "cake",
                       "chips", "snack", "cracker", "waffle"],
            prefixes: [],
            category: .sweetsSnacks
        ),
        CategoryRule(
            keywords: ["хлеб", "хліб", "батон", "булк", "лаваш", "выпеч", "круассан", "бублик",
                       "багет", "bread", "bakery", "bagel", "bun", "pastry", "croissant", "lavash"],
            prefixes: [],
            category: .bakery
        ),
        CategoryRule(
            keywords: ["вино", "пиво", "водк", "віскі", "виски", "коньяк", "шампан", "алкогол",
                       "beer", "wine", "vodka", "whisky", "whiskey", "alcohol", "cider"],
            prefixes: [],
            category: .alcohol
        ),
        CategoryRule(
            keywords: ["кава", "кофе", "чай", "какао", "coffee", "tea", "cocoa", "hot chocolate"],
            prefixes: [],
            category: .hotDrinks
        ),
        CategoryRule(
            keywords: ["сок", "вода", "кола", "газиров", "лимонад", "квас", "juice", "water",
                       "cola", "soda", "lemonade", "drink"],
            prefixes: [],
            category: .coldDrinks
        ),
        CategoryRule(
            keywords: ["соус", "специ", "кетчуп", "майонез", "гірчиц", "горчиц", "приправ",
                       "перец", "перець", "sauce", "spice", "ketchup", "mayo", "mustard",
                       "seasoning"],
            prefixes: [],
            category: .saucesSpices
        ),
        CategoryRule(
            keywords: ["олі", "олія", "уксус", "оцет", "консерв", "масло растит", "подсолнеч",
                       "оливков", "vinegar", "canned", "olive oil", "sunflower"],
            prefixes: [],
            category: .oilCanned
        ),
        CategoryRule(
            keywords: ["молоко", "йогурт", "сыр", "сир", "кефир", "кефір", "ряженк", "сметан",
                       "творог", "яйц", "масло сливоч", "milk", "yogurt", "yoghurt", "cheese",
                       "butter", "kefir", "cottage", "sour cream", "egg"],
            prefixes: [],
            category: .dairyEggs
        ),
        CategoryRule(
            keywords: ["рыб", "риб", "морепродукт", "кревет", "лосос", "тунц", "селед", "оселед",
                       "икр", "fish", "seafood", "shrimp", "salmon", "tuna", "crab"],
            prefixes: [],
            category: .fishSeafood
        ),
        CategoryRule(
            keywords: ["мясо", "мʼясо", "м’ясо", "курица", "курка", "фарш", "индейк", "говяд",
                       "свинин", "баранин", "колбас", "ковбас", "сосис", "ветчин", "бекон",
                       "стейк", "филе", "meat", "chicken", "beef", "pork", "turkey", "sausage",
                       "ham", "bacon", "steak", "mince", "poultry"],
            prefixes: [],
            category: .meatPoultry
        ),
        CategoryRule(
            keywords: ["круп", "макарон", "мук", "сахар", "цукор", "соль", "хлопья", "рис",
                       "гречк", "овсян", "каша", "pasta", "flour", "sugar", "salt", "cereal",
                       "rice", "oat", "buckwheat", "grocery", "porridge", "grits"],
            prefixes: ["каш"],
            category: .grocery
        ),
        CategoryRule(
            keywords: ["яблок", "банан", "овощ", "фрукт", "помидор", "огірок", "томат", "зелен",
                       "ягод", "огурец", "капуст", "морков", "apple", "banana", "tomato", "fruit",
                       "vegetable", "salad", "cucumber", "lemon", "potato", "onion", "carrot",
                       "berry", "greens", "lettuce"],
            prefixes: [],
            category: .produce
        ),
        CategoryRule(
            keywords: ["мыло", "мило", "порошок", "шампун", "средств", "засіб", "soap",
                       "detergent", "shampoo", "laundry", "cleaner", "bleach"],
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
