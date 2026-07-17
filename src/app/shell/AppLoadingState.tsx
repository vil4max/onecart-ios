interface AppLoadingStateProps {
  label: string
}

export function AppLoadingState({ label }: AppLoadingStateProps) {
  return (
    <main aria-busy="true" aria-label={label} className="screen app-loading-state" role="status">
      <span className="sr-only">{label}</span>
      <div aria-hidden="true" className="app-loading-state__content">
        <div className="app-loading-state__header">
          <span className="skeleton app-loading-state__line app-loading-state__line--short" />
          <span className="skeleton app-loading-state__line app-loading-state__line--title" />
        </div>
        <span className="skeleton skeleton-card" />
        <div className="app-loading-state__section">
          <span className="skeleton app-loading-state__line app-loading-state__line--section" />
          <span className="skeleton skeleton-card" />
          <span className="skeleton skeleton-card" />
          <span className="skeleton skeleton-card" />
        </div>
      </div>
    </main>
  )
}
