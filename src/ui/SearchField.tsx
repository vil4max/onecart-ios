import { useId } from 'react'
import type { InputHTMLAttributes } from 'react'
import { Search, X } from 'lucide-react'
import { IconButton } from './IconButton'
import { cx } from './utils'

export interface SearchFieldProps
  extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type' | 'value' | 'onChange' | 'size'> {
  label: string
  value: string
  onValueChange: (value: string) => void
  clearLabel: string
  labelHidden?: boolean
  statusMessage?: string
}

export function SearchField({
  className,
  clearLabel,
  disabled,
  id,
  label,
  labelHidden = false,
  onValueChange,
  statusMessage,
  value,
  ...inputProps
}: SearchFieldProps) {
  const generatedId = useId()
  const inputId = id ?? generatedId
  const statusId = statusMessage ? `${inputId}-status` : undefined

  return (
    <div className={cx('ui-search-field', className)}>
      <label className={cx('ui-search-field__label', labelHidden && 'ui-visually-hidden')} htmlFor={inputId}>
        {label}
      </label>
      <div className="ui-search-field__control">
        <Search aria-hidden="true" className="ui-search-field__icon" size={20} />
        <input
          {...inputProps}
          aria-describedby={statusId}
          className="ui-search-field__input"
          disabled={disabled}
          id={inputId}
          onChange={(event) => onValueChange(event.currentTarget.value)}
          type="search"
          value={value}
        />
        {value && !disabled ? (
          <IconButton icon={X} label={clearLabel} onClick={() => onValueChange('')} />
        ) : null}
      </div>
      {statusMessage ? (
        <p aria-live="polite" className="ui-search-field__status" id={statusId}>
          {statusMessage}
        </p>
      ) : null}
    </div>
  )
}
