import { CloudOff, TriangleAlert } from 'lucide-react'

interface AppStatusProps {
  offline: boolean
  offlineMessage: string
  error?: string | null
}

export function AppStatus({ offline, offlineMessage, error }: AppStatusProps) {
  if (error) {
    return (
      <div className="status-banner status-banner--error" role="alert">
        <TriangleAlert size={18} aria-hidden="true" />
        <span>{error}</span>
      </div>
    )
  }

  if (!offline) return null

  return (
    <div className="offline-banner" role="status">
      <CloudOff size={18} aria-hidden="true" />
      <span>{offlineMessage}</span>
    </div>
  )
}
