import { Minus, Plus } from 'lucide-react'
import { IconButton } from './IconButton'
import { cx } from './utils'

export interface QuantityStepperProps {
  value: number
  onChange: (value: number) => void
  label: string
  decrementLabel: string
  incrementLabel: string
  min?: number
  max?: number
  step?: number
  unitLabel?: string
  disabled?: boolean
  className?: string
  formatValue?: (value: number) => string
}

function normalizePrecision(value: number): number {
  return Number(value.toFixed(6))
}

export function QuantityStepper({
  className,
  decrementLabel,
  disabled = false,
  formatValue,
  incrementLabel,
  label,
  max = Number.POSITIVE_INFINITY,
  min = 0,
  onChange,
  step = 1,
  unitLabel,
  value,
}: QuantityStepperProps) {
  const safeStep = step > 0 ? step : 1
  const displayValue = formatValue ? formatValue(value) : String(value)
  const decrementDisabled = disabled || value <= min
  const incrementDisabled = disabled || value >= max

  return (
    <div aria-label={label} className={cx('ui-quantity-stepper', className)} role="group">
      <IconButton
        disabled={decrementDisabled}
        icon={Minus}
        label={decrementLabel}
        onClick={() => onChange(normalizePrecision(Math.max(min, value - safeStep)))}
      />
      <output aria-live="polite" className="ui-quantity-stepper__value">
        <span>{displayValue}</span>
        {unitLabel ? <span className="ui-quantity-stepper__unit">{unitLabel}</span> : null}
      </output>
      <IconButton
        disabled={incrementDisabled}
        icon={Plus}
        label={incrementLabel}
        onClick={() => onChange(normalizePrecision(Math.min(max, value + safeStep)))}
      />
    </div>
  )
}
