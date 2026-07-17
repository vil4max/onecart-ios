import { ButtonBase, type ButtonBaseProps } from './ButtonBase'

export type PrimaryButtonProps = ButtonBaseProps

export function PrimaryButton(props: PrimaryButtonProps) {
  return <ButtonBase {...props} variant="primary" />
}
