import { Clock3, Home, Plus, Store, UserRound } from 'lucide-react'

export type MainDestination = 'home' | 'stores' | 'history' | 'profile'

interface BottomNavigationLabels {
  main: string
  home: string
  stores: string
  add: string
  history: string
  profile: string
}

interface BottomNavigationProps {
  active: MainDestination | null
  labels: BottomNavigationLabels
  onNavigate: (destination: MainDestination) => void
  onAdd: () => void
}

export function BottomNavigation({ active, labels, onNavigate, onAdd }: BottomNavigationProps) {
  return (
    <nav className="bottom-nav" aria-label={labels.main}>
      <NavItem
        icon={Home}
        label={labels.home}
        active={active === 'home'}
        onClick={() => onNavigate('home')}
      />
      <NavItem
        icon={Store}
        label={labels.stores}
        active={active === 'stores'}
        onClick={() => onNavigate('stores')}
      />
      <button type="button" className="bottom-nav__item bottom-nav__add" onClick={onAdd}>
        <span className="bottom-nav__add-circle" aria-hidden="true">
          <Plus size={25} strokeWidth={2.25} />
        </span>
        <span>{labels.add}</span>
      </button>
      <NavItem
        icon={Clock3}
        label={labels.history}
        active={active === 'history'}
        onClick={() => onNavigate('history')}
      />
      <NavItem
        icon={UserRound}
        label={labels.profile}
        active={active === 'profile'}
        onClick={() => onNavigate('profile')}
      />
    </nav>
  )
}

interface NavItemProps {
  icon: typeof Home
  label: string
  active: boolean
  onClick: () => void
}

function NavItem({ icon: Icon, label, active, onClick }: NavItemProps) {
  return (
    <button
      type="button"
      className="bottom-nav__item"
      aria-current={active ? 'page' : undefined}
      onClick={onClick}
    >
      <Icon size={22} strokeWidth={1.9} aria-hidden="true" />
      <span>{label}</span>
    </button>
  )
}
