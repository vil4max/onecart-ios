import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useReducer,
  type Dispatch,
  type ReactNode,
} from 'react'
import { loadAppState, saveAppState, type StorageAdapter } from '../data/storage'
import {
  appReducer,
  createInitialAppState,
  type AppAction,
  type AppState,
} from './appReducer'

const AppStateContext = createContext<AppState | null>(null)
const AppDispatchContext = createContext<Dispatch<AppAction> | null>(null)

export interface AppStateProviderProps {
  children: ReactNode
  initialState?: AppState
  persistence?: boolean
  storage?: StorageAdapter | null
}

interface InitializerInput {
  initialState?: AppState
  persistence: boolean
  storage?: StorageAdapter | null
}

function initializeProviderState(input: InitializerInput): AppState {
  if (input.initialState) {
    return input.initialState
  }
  const fallback = createInitialAppState()
  return input.persistence ? loadAppState(fallback, input.storage) : fallback
}

export function AppStateProvider({
  children,
  initialState,
  persistence = true,
  storage,
}: AppStateProviderProps) {
  const [state, dispatch] = useReducer(
    appReducer,
    { initialState, persistence, storage },
    initializeProviderState,
  )

  useEffect(() => {
    if (persistence) {
      saveAppState(state, storage)
    }
  }, [persistence, state, storage])

  return (
    <AppStateContext.Provider value={state}>
      <AppDispatchContext.Provider value={dispatch}>{children}</AppDispatchContext.Provider>
    </AppStateContext.Provider>
  )
}

export function useAppState(): AppState {
  const state = useContext(AppStateContext)
  if (!state) {
    throw new Error('useAppState must be used within AppStateProvider')
  }
  return state
}

export function useAppDispatch(): Dispatch<AppAction> {
  const dispatch = useContext(AppDispatchContext)
  if (!dispatch) {
    throw new Error('useAppDispatch must be used within AppStateProvider')
  }
  return dispatch
}

export function useAppStore(): { state: AppState; dispatch: Dispatch<AppAction> } {
  const state = useAppState()
  const dispatch = useAppDispatch()
  return useMemo(() => ({ state, dispatch }), [state, dispatch])
}

export function useAppSelector<Selected>(selector: (state: AppState) => Selected): Selected {
  return selector(useAppState())
}
