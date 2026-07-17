import { ListPlus, Mic, PackagePlus, Store } from 'lucide-react'
import { BottomSheet } from '../../ui'

interface QuickActionsLabels {
  title: string
  close: string
  product: string
  productDescription: string
  list: string
  listDescription: string
  store: string
  storeDescription: string
  voice: string
  voiceDescription: string
}

interface QuickActionsSheetProps {
  isOpen: boolean
  labels: QuickActionsLabels
  onClose: () => void
  onAddProduct: () => void
  onCreateList: () => void
  onAddStore: () => void
  onAddVoice: () => void
}

export function QuickActionsSheet({
  isOpen,
  labels,
  onAddProduct,
  onAddStore,
  onAddVoice,
  onClose,
  onCreateList,
}: QuickActionsSheetProps) {
  const actions = [
    {
      label: labels.product,
      description: labels.productDescription,
      icon: PackagePlus,
      onClick: onAddProduct,
    },
    {
      label: labels.list,
      description: labels.listDescription,
      icon: ListPlus,
      onClick: onCreateList,
    },
    {
      label: labels.store,
      description: labels.storeDescription,
      icon: Store,
      onClick: onAddStore,
    },
    {
      label: labels.voice,
      description: labels.voiceDescription,
      icon: Mic,
      onClick: onAddVoice,
    },
  ]

  return (
    <BottomSheet isOpen={isOpen} title={labels.title} closeLabel={labels.close} onClose={onClose}>
      <div className="action-list">
        {actions.map(({ description, icon: Icon, label, onClick }) => (
          <button key={label} type="button" className="action-list__item" onClick={onClick}>
            <span className="action-list__icon" aria-hidden="true">
              <Icon size={21} />
            </span>
            <span className="action-list__copy">
              <strong>{label}</strong>
              <span>{description}</span>
            </span>
          </button>
        ))}
      </div>
    </BottomSheet>
  )
}
