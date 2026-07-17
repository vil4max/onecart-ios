import type { CSSProperties } from 'react'
import { cx } from './utils'

export type StoreMarkSize = 'compact' | 'medium' | 'large'

export interface StoreMarkProps {
  storeId?: string
  name: string
  icon?: string
  color?: string
  size?: StoreMarkSize
  label?: string
  className?: string
}

type StoreMarkVariant =
  | 'atb'
  | 'silpo'
  | 'auchan'
  | 'novus'
  | 'varus'
  | 'fora'
  | 'metro'

interface StoreMarkPalette {
  background: string
  foreground: string
  accent: string
  border: string
}

const STORE_MARK_PALETTES: Record<StoreMarkVariant, StoreMarkPalette> = {
  atb: {
    background: '#0F2F5C',
    foreground: '#E30613',
    accent: '#FFD338',
    border: 'rgba(10, 43, 91, 0.2)',
  },
  silpo: {
    background: '#4B286D',
    foreground: '#F58220',
    accent: '#FFF3E0',
    border: 'rgba(75, 40, 109, 0.24)',
  },
  auchan: {
    background: '#FFFDF8',
    foreground: '#E3000B',
    accent: '#00965A',
    border: 'rgba(227, 0, 11, 0.18)',
  },
  novus: {
    background: '#45B759',
    foreground: '#FFFFFF',
    accent: '#F6D64A',
    border: 'rgba(14, 92, 48, 0.22)',
  },
  varus: {
    background: '#C8E03A',
    foreground: '#FF6000',
    accent: 'rgba(255, 255, 255, 0.28)',
    border: 'rgba(120, 140, 20, 0.24)',
  },
  fora: {
    background: '#1FAF46',
    foreground: '#FFFFFF',
    accent: '#EE4036',
    border: 'rgba(11, 89, 48, 0.24)',
  },
  metro: {
    background: '#013E7F',
    foreground: '#FFF100',
    accent: '#FFF100',
    border: 'rgba(1, 62, 127, 0.22)',
  },
}

function resolveVariant(storeId: string | undefined, name: string): StoreMarkVariant | null {
  const identity = `${storeId ?? ''} ${name}`.toLocaleLowerCase()
  if (identity.includes('atb') || identity.includes('атб')) return 'atb'
  if (identity.includes('silpo') || identity.includes('сільпо') || identity.includes('сильпо')) {
    return 'silpo'
  }
  if (identity.includes('auchan') || identity.includes('ашан')) return 'auchan'
  if (identity.includes('novus') || identity.includes('новус')) return 'novus'
  if (identity.includes('varus') || identity.includes('варус')) return 'varus'
  if (identity.includes('fora') || identity.includes('фора')) return 'fora'
  if (identity.includes('metro') || identity.includes('метро')) return 'metro'
  return null
}

function StoreGlyph({ variant }: { variant: StoreMarkVariant }) {
  switch (variant) {
    case 'atb':
      return (
        <svg aria-hidden="true" viewBox="0 0 48 48">
          <rect fill="#fff" height="34" rx="7" width="36" x="6" y="7" />
          <rect className="ui-store-mark__accent" height="3" rx="1.5" width="28" x="10" y="9.5" />
          <text
            dominantBaseline="middle"
            fill="currentColor"
            fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
            fontSize="16"
            fontWeight="900"
            letterSpacing="-0.5"
            textAnchor="middle"
            x="24"
            y="27"
          >
            АТБ
          </text>
          <circle className="ui-store-mark__accent" cx="38" cy="8" r="2.6" />
          <circle cx="38" cy="8" fill="#0F2F5C" r="1" />
        </svg>
      )
    case 'silpo':
      return (
        <img
          alt=""
          aria-hidden="true"
          src="/store-marks/silpo.svg"
          style={{ width: '100%', height: '100%', objectFit: 'contain', padding: '6%' }}
        />
      )
    case 'auchan':
      return (
        <img
          alt=""
          aria-hidden="true"
          src="/store-marks/auchan.svg"
          style={{ width: '100%', height: '100%', objectFit: 'contain', padding: '10%' }}
        />
      )
    case 'novus':
      return (
        <svg aria-hidden="true" viewBox="0 0 48 48">
          <text
            dominantBaseline="middle"
            fill="currentColor"
            fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
            fontSize="26"
            fontWeight="800"
            textAnchor="middle"
            x="21"
            y="26"
          >
            N
          </text>
          <path
            className="ui-store-mark__accent"
            d="M34 8c3.2 1.2 5.2 4.2 5.2 7.4S37.2 21 34 22.2C30.8 21 28.8 18.6 28.8 15.4S30.8 9.2 34 8Z"
          />
        </svg>
      )
    case 'varus':
      return (
        <img
          alt=""
          aria-hidden="true"
          src="/store-marks/varus.svg"
          style={{ width: '100%', height: '100%', objectFit: 'contain', padding: '12%' }}
        />
      )
    case 'fora':
      return (
        <svg aria-hidden="true" viewBox="0 0 48 48">
          <text
            dominantBaseline="middle"
            fill="currentColor"
            fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
            fontSize="9"
            fontWeight="800"
            letterSpacing="-0.2"
            textAnchor="middle"
            x="24"
            y="12"
          >
            фора
          </text>
          <circle className="ui-store-mark__accent" cx="24" cy="30" r="11" />
          <path d="M16.5 28.5h15l-2.2 10.5h-10.6L16.5 28.5Z" fill="#fff" />
          <path
            d="M20 28.5 24 21.5 28 28.5"
            fill="none"
            stroke="#fff"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="2.2"
          />
          <path d="M20.5 31v5.5M24 31v5.5M27.5 31v5.5" stroke="#EE4036" strokeWidth="1.4" />
        </svg>
      )
    case 'metro':
      return (
        <svg aria-hidden="true" viewBox="0 0 48 48">
          <path className="ui-store-mark__accent" d="M8 8h32v2.4H8zM8 37.6h32V40H8z" />
          <text
            dominantBaseline="middle"
            fill="currentColor"
            fontFamily="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
            fontSize="11"
            fontWeight="900"
            letterSpacing="-0.6"
            textAnchor="middle"
            x="24"
            y="25"
          >
            METRO
          </text>
        </svg>
      )
  }
}

export function StoreMark({
  className,
  color,
  icon,
  label,
  name,
  size = 'medium',
  storeId,
}: StoreMarkProps) {
  const variant = resolveVariant(storeId, name)
  const monogram = (icon?.trim() || name.trim().slice(0, 2)).toLocaleUpperCase()
  const palette = variant ? STORE_MARK_PALETTES[variant] : null
  const style = {
    '--ui-store-mark-background': palette?.background ?? color ?? '#34785B',
    '--ui-store-mark-foreground': palette?.foreground ?? '#FFFFFF',
    '--ui-store-mark-accent': palette?.accent ?? '#FFD166',
    '--ui-store-mark-border': palette?.border ?? 'rgba(255, 255, 255, 0.18)',
  } as CSSProperties

  return (
    <span
      aria-hidden={label ? undefined : true}
      aria-label={label}
      className={cx(
        'ui-store-mark',
        `ui-store-mark--${size}`,
        variant && `ui-store-mark--brand-${variant}`,
        className,
      )}
      role={label ? 'img' : undefined}
      style={style}
    >
      {variant ? <StoreGlyph variant={variant} /> : <span>{monogram}</span>}
    </span>
  )
}
