import Foundation

/// SF Symbol names are plain strings, so the app and the widget share them without a UI
/// framework; each target draws them with its own views.
extension ProductCategory {
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
}
