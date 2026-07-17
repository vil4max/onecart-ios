import { describe, expect, it } from 'vitest'
import { resolveProductMedia } from './productMedia'

describe('official product media', () => {
  it('matches known products to an official catalog image', () => {
    expect(resolveProductMedia('Бананы', 'АТБ')).toMatchObject({
      sourceLabel: 'АТБ',
      sourceUrl: 'https://www.atbmarket.com/product/banan-1-gat',
    })
    expect(resolveProductMedia('Молоко 2,5%', 'Сільпо')).toMatchObject({
      sourceLabel: 'Сільпо',
    })
    expect(resolveProductMedia('Вода без газа', 'Auchan')).toMatchObject({
      sourceLabel: 'Auchan',
    })
  })

  it('does not show an unrelated image for an unknown product', () => {
    expect(resolveProductMedia('Йогурт с клубникой', 'Сільпо')).toBeNull()
  })
})
