import { ButtonBase, type ButtonBaseProps } from './ButtonBase'

export type SecondaryButtonProps = ButtonBaseProps

export function SecondaryButton(props: SecondaryButtonProps) {
  return <ButtonBase {...props} variant="secondary" />
}
