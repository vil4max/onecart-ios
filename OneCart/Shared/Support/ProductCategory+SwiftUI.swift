import SwiftUI

/// App-only: the widget draws categories by symbol and never shows their titles.
extension ProductCategory {
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
}
