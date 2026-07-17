import { CheckCircle2, ShoppingBasket, UsersRound } from 'lucide-react'

export interface OnboardingPage {
  title: string
  description: string
}

interface OnboardingScreenProps {
  page: number
  pages: OnboardingPage[]
  continueLabel: string
  startLabel: string
  stepLabel: (current: number, total: number) => string
  onPageChange: (page: number) => void
  onContinue: () => void
}

const pageIcons = [ShoppingBasket, UsersRound, CheckCircle2]

export function OnboardingScreen({
  page,
  pages,
  continueLabel,
  startLabel,
  stepLabel,
  onPageChange,
  onContinue,
}: OnboardingScreenProps) {
  const activePage = pages[page] ?? pages[0]
  const Icon = pageIcons[page] ?? ShoppingBasket
  const isLast = page === pages.length - 1

  return (
    <main className="onboarding-screen">
      <section className="onboarding-screen__content" aria-live="polite">
        <div className="onboarding-screen__visual" aria-hidden="true">
          <Icon size={62} strokeWidth={1.65} />
        </div>
        <div className="onboarding-screen__copy">
          <h1>{activePage.title}</h1>
          <p>{activePage.description}</p>
        </div>
      </section>

      <footer className="onboarding-screen__footer">
        <div className="page-dots" role="group" aria-label={stepLabel(page + 1, pages.length)}>
          {pages.map((item, index) => (
            <button
              key={item.title}
              type="button"
              className="page-dot"
              aria-label={stepLabel(index + 1, pages.length)}
              aria-current={index === page ? 'step' : undefined}
              onClick={() => onPageChange(index)}
            />
          ))}
        </div>
        <button type="button" className="primary-button button--full" onClick={onContinue}>
          {isLast ? startLabel : continueLabel}
        </button>
      </footer>
    </main>
  )
}

