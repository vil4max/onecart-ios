export type FeatureFeedbackTone = 'success' | 'error' | 'info'

export interface FeatureFeedback {
  message: string
  tone?: FeatureFeedbackTone
  actionLabel?: string
  onAction?: () => void
}

export interface ProductEditorContext {
  listId: string
  storeId: string | null
}

