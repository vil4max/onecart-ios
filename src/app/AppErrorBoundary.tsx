import { Component, type ErrorInfo, type ReactNode } from 'react'
import { CircleAlert, RotateCcw } from 'lucide-react'

interface AppErrorBoundaryProps {
  children: ReactNode
  title: string
  message: string
  retryLabel: string
}

interface AppErrorBoundaryState {
  hasError: boolean
}

export class AppErrorBoundary extends Component<
  AppErrorBoundaryProps,
  AppErrorBoundaryState
> {
  state: AppErrorBoundaryState = { hasError: false }

  static getDerivedStateFromError(): AppErrorBoundaryState {
    return { hasError: true }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    if (import.meta.env.DEV) console.error(error, errorInfo)
  }

  render() {
    if (!this.state.hasError) return this.props.children

    return (
      <main className="app-shell">
        <section className="screen">
          <div className="empty-state card" role="alert">
            <div className="empty-state__inner">
              <span className="empty-state__icon" aria-hidden="true">
                <CircleAlert size={30} />
              </span>
              <h1>{this.props.title}</h1>
              <p>{this.props.message}</p>
              <button
                type="button"
                className="primary-button"
                onClick={() => this.setState({ hasError: false })}
              >
                <RotateCcw size={18} aria-hidden="true" />
                {this.props.retryLabel}
              </button>
            </div>
          </div>
        </section>
      </main>
    )
  }
}
