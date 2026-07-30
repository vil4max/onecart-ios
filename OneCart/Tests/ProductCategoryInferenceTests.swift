import XCTest
@testable import OneCart

final class ProductCategoryInferenceTests: XCTestCase {
    func testRussianKeywords() {
        XCTAssertEqual(ProductCategory.inferred(from: "Молоко"), .dairy)
        XCTAssertEqual(ProductCategory.inferred(from: "курица"), .meat)
        XCTAssertEqual(ProductCategory.inferred(from: "сок"), .drinks)
        XCTAssertEqual(ProductCategory.inferred(from: "порошок"), .household)
        XCTAssertEqual(ProductCategory.inferred(from: "яблоки"), .produce)
    }

    func testEnglishKeywordsMatchDemoSeed() {
        XCTAssertEqual(ProductCategory.inferred(from: "Milk"), .dairy)
        XCTAssertEqual(ProductCategory.inferred(from: "Cheese"), .dairy)
        XCTAssertEqual(ProductCategory.inferred(from: "Coffee"), .drinks)
        XCTAssertEqual(ProductCategory.inferred(from: "Orange juice"), .drinks)
        XCTAssertEqual(ProductCategory.inferred(from: "Tomatoes"), .produce)
        XCTAssertEqual(ProductCategory.inferred(from: "Apples"), .produce)
        XCTAssertEqual(ProductCategory.inferred(from: "Laundry detergent"), .household)
        XCTAssertEqual(ProductCategory.inferred(from: "Bread"), .other)
    }

    func testUnknownFallsBackToOther() {
        XCTAssertEqual(ProductCategory.inferred(from: "xyz"), .other)
        XCTAssertEqual(ProductCategory.inferred(from: ""), .other)
    }
}
