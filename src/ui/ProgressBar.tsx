import type { HTMLAttributes } from 'react'
import { cx } from './utils'

export interface ProgressBarProps extends Omit<HTMLAttributes<HTMLDivElement>, 'children'> {
  value: number
  min?: number
  max?: number
  label: string
  valueText: string
  showMeta?: boolean
}

export function ProgressBar({
  className,
  label,
  max = 100,
  min = 0,
  showMeta = false,
  value,
  valueText,
  ...containerProps
}: ProgressBarProps) {
  const safeMax = max > min ? max : min + 1
  const boundedValue = Math.min(safeMax, Math.max(min, value))
  const percentage = ((boundedValue - min) / (safeMax - min)) * 100

  return (
    <div {...containerProps} className={cx('ui-progress', className)}>
      {showMeta ? (
        <div className="ui-progress__meta">
          <span>{label}</span>
          <span>{valueText}</span>
        </div>
      ) : null}
      <div
        aria-label={label}
        aria-valuemax={safeMax}
        aria-valuemin={min}
        aria-valuenow={boundedValue}
        aria-valuetext={valueText}
        className="ui-progress__track"
        role="progressbar"
      >
        <span className="ui-progress__fill" style={{ width: `${percentage}%` }} />
      </div>
    </div>
  )
}
