@testable import OneCart
import XCTest

final class ProductCategoryInferenceTests: XCTestCase {
    func testMetroStyleRussianUkrainian() {
        XCTAssertEqual(ProductCategory.inferred(from: "Мясо"), .meatPoultry)
        XCTAssertEqual(ProductCategory.inferred(from: "курица"), .meatPoultry)
        XCTAssertEqual(ProductCategory.inferred(from: "колбаса"), .meatPoultry)
        XCTAssertEqual(ProductCategory.inferred(from: "рыба"), .fishSeafood)
        XCTAssertEqual(ProductCategory.inferred(from: "креветки"), .fishSeafood)
        XCTAssertEqual(ProductCategory.inferred(from: "Молоко"), .dairyEggs)
        XCTAssertEqual(ProductCategory.inferred(from: "яйца"), .dairyEggs)
        XCTAssertEqual(ProductCategory.inferred(from: "гречка"), .grocery)
        XCTAssertEqual(ProductCategory.inferred(from: "каша"), .grocery)
        XCTAssertEqual(ProductCategory.inferred(from: "оливковое масло"), .oilCanned)
        XCTAssertEqual(ProductCategory.inferred(from: "консервы"), .oilCanned)
        XCTAssertEqual(ProductCategory.inferred(from: "яблоки"), .produce)
        XCTAssertEqual(ProductCategory.inferred(from: "пельмени"), .frozen)
        XCTAssertEqual(ProductCategory.inferred(from: "Хлеб"), .bakery)
        XCTAssertEqual(ProductCategory.inferred(from: "кетчуп"), .saucesSpices)
        XCTAssertEqual(ProductCategory.inferred(from: "пиво"), .alcohol)
        XCTAssertEqual(ProductCategory.inferred(from: "сок"), .coldDrinks)
        XCTAssertEqual(ProductCategory.inferred(from: "кофе"), .hotDrinks)
        XCTAssertEqual(ProductCategory.inferred(from: "шоколад"), .sweetsSnacks)
        XCTAssertEqual(ProductCategory.inferred(from: "чипсы"), .sweetsSnacks)
        XCTAssertEqual(ProductCategory.inferred(from: "детское пюре"), .babyFood)
        XCTAssertEqual(ProductCategory.inferred(from: "порошок"), .household)
    }

    func testEnglishKeywords() {
        XCTAssertEqual(ProductCategory.inferred(from: "Milk"), .dairyEggs)
        XCTAssertEqual(ProductCategory.inferred(from: "Bread"), .bakery)
        XCTAssertEqual(ProductCategory.inferred(from: "Coffee"), .hotDrinks)
        XCTAssertEqual(ProductCategory.inferred(from: "Tomatoes"), .produce)
        XCTAssertEqual(ProductCategory.inferred(from: "Pasta"), .grocery)
        XCTAssertEqual(ProductCategory.inferred(from: "Ice cream"), .frozen)
        XCTAssertEqual(ProductCategory.inferred(from: "Salmon"), .fishSeafood)
        XCTAssertEqual(ProductCategory.inferred(from: "Sausage"), .meatPoultry)
        XCTAssertEqual(ProductCategory.inferred(from: "Laundry detergent"), .household)
    }

    func testLegacyStoredCategories() {
        XCTAssertEqual(ProductCategory.resolved(storedRawValue: "produce"), .produce)
        XCTAssertEqual(ProductCategory.resolved(storedRawValue: "fresh"), .produce)
        XCTAssertEqual(ProductCategory.resolved(storedRawValue: "meat"), .meatPoultry)
        XCTAssertEqual(ProductCategory.resolved(storedRawValue: "dairy"), .dairyEggs)
        XCTAssertEqual(ProductCategory.resolved(storedRawValue: "drinks"), .coldDrinks)
        XCTAssertEqual(ProductCategory.resolved(storedRawValue: "bakery"), .bakery)
    }

    func testUnknownFallsBackToOther() {
        XCTAssertEqual(ProductCategory.inferred(from: "xyz"), .other)
        XCTAssertEqual(ProductCategory.inferred(from: ""), .other)
    }

    func testGroupedSectionsKeepsMetroOrderAndSkipsEmpty() {
        let items: [(name: String, category: ProductCategory)] = [
            ("Дыня", .other),
            ("Молоко", .dairyEggs),
            ("Арбуз", .other),
            ("Хлеб", .bakery),
        ]
        let sections = ProductCategory.groupedSections(from: items) { $0.category }
        XCTAssertEqual(sections.map(\.category), [.dairyEggs, .bakery, .other])
        XCTAssertEqual(sections[0].items.map(\.name), ["Молоко"])
        XCTAssertEqual(sections[1].items.map(\.name), ["Хлеб"])
        XCTAssertEqual(sections[2].items.map(\.name), ["Дыня", "Арбуз"])
    }

    func testKeywordClassifierMatchesInferred() async {
        let classifier = KeywordCategoryClassifier()
        let category = await classifier.classify("Хлеб")
        XCTAssertEqual(category, .bakery)
        XCTAssertEqual(category.symbolName, "birthday.cake.fill")
    }
}
