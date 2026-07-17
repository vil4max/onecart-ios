export interface ProductMedia {
  imageUrl: string
  sourceUrl: string
  sourceLabel: string
}

interface ProductMediaRule extends ProductMedia {
  keywords: readonly string[]
  storeHints?: readonly string[]
}

const PRODUCT_MEDIA_RULES: readonly ProductMediaRule[] = [
  {
    keywords: ['банан', 'banana'],
    storeHints: ['atb', 'атб'],
    imageUrl:
      'https://src.zakaz.atbmarket.com/cache/photos/18797/catalog_product_gal_mob_18797.jpg',
    sourceUrl: 'https://www.atbmarket.com/product/banan-1-gat',
    sourceLabel: 'АТБ',
  },
  {
    keywords: ['яйц', 'egg'],
    storeHints: ['atb', 'атб'],
    imageUrl:
      'https://src.zakaz.atbmarket.com/cache/photos/31637/catalog_product_gal_mob_31637.jpg',
    sourceUrl:
      'https://www.atbmarket.com/product/ajce-kurace-10-st-asensvit-1-kategorii-fas',
    sourceLabel: 'АТБ',
  },
  {
    keywords: ['молок', 'milk'],
    imageUrl:
      'https://images.silpo.ua/v2/products/744x744/webp/f823d548-8855-41ec-973c-ec846b395477.png',
    sourceUrl:
      'https://silpo.ua/product/moloko-ultrapasteryzovane-na-zdorov-ia-bezlaktozne-2-5-857563',
    sourceLabel: 'Сільпо',
  },
  {
    keywords: ['хлеб', 'хліб', 'bread'],
    imageUrl:
      'https://images.silpo.ua/v2/products/744x744/webp/f48ceed7-015a-415b-a340-d1101d998261.png',
    sourceUrl: 'https://silpo.ua/product/khlib-dobryi-tsilnozernovyi-829906',
    sourceLabel: 'Сільпо',
  },
  {
    keywords: ['сыр', 'сир', 'cheese'],
    imageUrl:
      'https://images.silpo.ua/v2/products/744x744/webp/b750bc2a-fde6-4d89-b703-939588c84c94.png',
    sourceUrl:
      'https://silpo.ua/product/syr-gouda-napivtverdyi-z-korov-iachogo-moloka-narizanyi-skybkamy-48-1009450',
    sourceLabel: 'Сільпо',
  },
  {
    keywords: ['вода', 'water'],
    imageUrl:
      'https://img3.zakaz.ua/89b4d9093f374877b5099687d2bf590f/1756745262-s350x350.jpg',
    sourceUrl:
      'https://auchan.zakaz.ua/uk/products/voda-kozhen-den-6000ml--04823090107840/',
    sourceLabel: 'Auchan',
  },
  {
    keywords: ['салфет', 'сервет', 'napkin', 'tissue'],
    imageUrl:
      'https://images.silpo.ua/v2/products/744x744/webp/09ef1230-22a2-4a90-9b9e-d14bfbcad447.jpg',
    sourceUrl:
      'https://silpo.ua/product/servetky-paperovi-povna-chasha-1-sharovi-33kh33-sm-986808',
    sourceLabel: 'Сільпо',
  },
]

function normalize(value: string): string {
  return value.trim().toLocaleLowerCase()
}

export function resolveProductMedia(
  name: string,
  storeIdentity = '',
): ProductMedia | null {
  const normalizedName = normalize(name)
  const normalizedStore = normalize(storeIdentity)
  const exactStoreRule = PRODUCT_MEDIA_RULES.find(
    (rule) =>
      rule.storeHints?.some((hint) => normalizedStore.includes(hint)) &&
      rule.keywords.some((keyword) => normalizedName.includes(keyword)),
  )
  const keywordRule = PRODUCT_MEDIA_RULES.find((rule) =>
    rule.keywords.some((keyword) => normalizedName.includes(keyword)),
  )
  const rule = exactStoreRule ?? keywordRule

  if (!rule) return null
  return {
    imageUrl: rule.imageUrl,
    sourceUrl: rule.sourceUrl,
    sourceLabel: rule.sourceLabel,
  }
}
