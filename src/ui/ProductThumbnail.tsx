import { useEffect, useState } from 'react'
import { PackageOpen } from 'lucide-react'
import { cx } from './utils'

export type ProductThumbnailSize = 'row' | 'detail'

export interface ProductThumbnailProps {
  src?: string | null
  alt: string
  size?: ProductThumbnailSize
  className?: string
}

export function ProductThumbnail({
  alt,
  className,
  size = 'row',
  src,
}: ProductThumbnailProps) {
  const [failed, setFailed] = useState(false)

  useEffect(() => setFailed(false), [src])

  return (
    <span
      aria-label={!src || failed ? alt : undefined}
      className={cx('ui-product-thumbnail', `ui-product-thumbnail--${size}`, className)}
      role={!src || failed ? 'img' : undefined}
    >
      {src && !failed ? (
        <img
          alt={alt}
          decoding="async"
          loading="lazy"
          onError={() => setFailed(true)}
          referrerPolicy="no-referrer"
          src={src}
        />
      ) : (
        <PackageOpen aria-hidden="true" size={size === 'detail' ? 38 : 22} />
      )}
    </span>
  )
}
