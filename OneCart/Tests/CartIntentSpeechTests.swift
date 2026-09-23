import Foundation
@testable import OneCart
import XCTest

/// What Siri says, resolved in the language of the request (REQ-SIRI-040).
final class CartIntentSpeechTests: XCTestCase {
    func test_REQ_SIRI_040_speaksRussianWithPluralCounts() {
        XCTAssertEqual(spoken(remainingSpeech(count: 1), in: "ru"), "Осталось купить 1 товар: A.")
        XCTAssertEqual(spoken(remainingSpeech(count: 3), in: "ru"), "Осталось купить 3 товара: A, B и C.")
        XCTAssertEqual(spoken(remainingSpeech(count: 5), in: "ru"), "Осталось купить 5 товаров: A, B, C, D и E.")
        XCTAssertEqual(
            spoken(remainingSpeech(count: 6), in: "ru"),
            "Осталось купить 6 товаров: A, B, C, D и E. И ещё 1 товар."
        )
        XCTAssertEqual(
            spoken(remainingSpeech(count: 7), in: "ru"),
            "Осталось купить 7 товаров: A, B, C, D и E. И ещё 2 товара."
        )
        XCTAssertEqual(
            spoken(remainingSpeech(count: 10), in: "ru"),
            "Осталось купить 10 товаров: A, B, C, D и E. И ещё 5 товаров."
        )
        let added = CartIntentAddResult(added: ["Молоко", "хлеб"], alreadyOnCart: ["сыр"], failed: ["чай"])
        XCTAssertEqual(
            spoken(CartIntentSpeech.addResult(added), in: "ru"),
            "Добавлено в корзину: Молоко и хлеб. Уже в корзине: сыр. Не удалось добавить: чай."
        )
    }

    func test_REQ_SIRI_040_speaksUkrainianWithPluralCounts() {
        XCTAssertEqual(spoken(remainingSpeech(count: 1), in: "uk"), "Лишилося купити 1 товар: A.")
        XCTAssertEqual(spoken(remainingSpeech(count: 2), in: "uk"), "Лишилося купити 2 товари: A і B.")
        XCTAssertEqual(
            spoken(remainingSpeech(count: 6), in: "uk"),
            "Лишилося купити 6 товарів: A, B, C, D і E. І ще 1 товар."
        )
        XCTAssertEqual(
            spoken(remainingSpeech(count: 7), in: "uk"),
            "Лишилося купити 7 товарів: A, B, C, D і E. І ще 2 товари."
        )
        XCTAssertEqual(
            spoken(remainingSpeech(count: 10), in: "uk"),
            "Лишилося купити 10 товарів: A, B, C, D і E. І ще 5 товарів."
        )
    }

    func test_REQ_SIRI_040_russianAndUkrainianSpeechUsesTheFormalRegister() {
        let signedOut = CartIntentError.signedOut.localizedStringResource
        let emptyName = CartIntentError.emptyName.localizedStringResource
        XCTAssertEqual(spoken(signedOut, in: "ru"), "Сначала откройте OneCart и войдите.")
        XCTAssertEqual(spoken(emptyName, in: "ru"), "Скажите, что добавить.")
        XCTAssertEqual(spoken(signedOut, in: "uk"), "Спершу відкрийте OneCart і увійдіть.")
        XCTAssertEqual(spoken(emptyName, in: "uk"), "Скажіть, що додати.")
    }
}
