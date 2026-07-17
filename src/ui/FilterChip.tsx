import type { LucideIcon } from 'lucide-react'
import { Check } from 'lucide-react'
import { cx } from './utils'

export interface FilterChipProps {
  label: string
  selected: boolean
  onSelectedChange: (selected: boolean) => void
  icon?: LucideIcon
  count?: number
  disabled?: boolean
  className?: string
}

export function FilterChip({
  className,
  count,
  disabled = false,
  icon: Icon,
  label,
  onSelectedChange,
  selected,
}: FilterChipProps) {
  const LeadingIcon = Icon ?? (selected ? Check : undefined)

  return (
    <button
      aria-pressed={selected}
      className={cx('ui-filter-chip', selected && 'ui-filter-chip--selected', className)}
      disabled={disabled}
      onClick={() => onSelectedChange(!selected)}
      type="button"
    >
      {LeadingIcon ? <LeadingIcon aria-hidden="true" size={16} /> : null}
      <span>{label}</span>
      {count !== undefined ? <span className="ui-filter-chip__count">{count}</span> : null}
    </button>
  )
}
