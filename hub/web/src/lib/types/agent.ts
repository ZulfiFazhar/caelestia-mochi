/**
 * Agent & Mochi type definitions for Mochi Hub PWA.
 * Ported and aligned with src/modules/dashboard/agent/MochiBot.qml and mochi_daemon.
 */

export type MochiState =
  | 'idle'
  | 'working'
  | 'thinking'
  | 'searching'
  | 'approval'
  | 'question'
  | 'error'
  | 'finished'
  | 'done'
  | 'sleeping'
  | 'dizzy'
  | 'ratelimit'

export type EyeShape = 'pill' | 'wide' | 'happy' | 'closed' | 'flat' | 'dizzy'

export interface AgentInfo {
  name: string
  command?: string
  pid?: number | null
  status?: string
  cpu?: number
  memory?: number
  details?: Record<string, unknown>
}

export interface ApprovalRequest {
  approval_id: string
  session_id?: string
  command?: string
  prompt?: string
  matched_text?: string
  timestamp?: number
  approved?: boolean
  resolved?: boolean
  reason?: string
}

export interface SystemState {
  timestamp: number
  agents: AgentInfo[]
  active_agent?: AgentInfo | null
  mochi_state: MochiState
}

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'reconnecting'

export interface TimelineEntry {
  id: string
  timestamp: number
  type: 'system' | 'agent' | 'user' | 'terminal' | 'approval'
  text: string
  sender?: string
  status?: string
}

/**
 * Maps raw agent status string to valid MochiState.
 */
export function statusToMochiState(status?: string): MochiState {
  if (!status) return 'idle'
  const s = status.toLowerCase()
  if (['working', 'busy', 'run', 'running'].includes(s)) return 'working'
  if (['thinking', 'reasoning'].includes(s)) return 'thinking'
  if (['searching', 'grep', 'glob'].includes(s)) return 'searching'
  if (['approval', 'waiting', 'confirm', 'prompt'].includes(s)) return 'approval'
  if (['question', 'ask'].includes(s)) return 'question'
  if (['error', 'failed'].includes(s)) return 'error'
  if (['done', 'finished', 'completed', 'success'].includes(s)) return 'done'
  if (['sleeping', 'stopped', 'inactive'].includes(s)) return 'sleeping'
  if (['dizzy'].includes(s)) return 'dizzy'
  if (['ratelimit', 'throttled'].includes(s)) return 'ratelimit'
  return 'idle'
}

export interface MochiBotProps {
  state?: MochiState
  eyeShape?: EyeShape
  size?: number
  interactive?: boolean
  accentColor?: string
  active?: boolean
  class?: string
}

export interface MiniMochiProps {
  state?: MochiState
  eyeShape?: EyeShape
  size?: number
  accentColor?: string
  active?: boolean
  class?: string
}

/**
 * Official glow colors per state from MochiBot.qml.
 */
export function getGlowColor(state: MochiState, accentColor = '#4ADE80'): string {
  switch (state) {
    case 'working':
      return '#3B9EFF'
    case 'thinking':
      return '#A78BFA'
    case 'searching':
      return '#6366F1'
    case 'approval':
      return '#F5A524'
    case 'question':
      return '#22D3EE'
    case 'error':
      return '#F4505E'
    case 'finished':
    case 'done':
      return '#34D399'
    case 'ratelimit':
      return '#F59E0B'
    case 'sleeping':
      return '#94A3B8'
    case 'dizzy':
      return '#EC4899'
    default:
      return accentColor
  }
}

/**
 * Eye shape mapping ported from MochiBot.qml:
 * finished/done -> happy
 * sleeping -> closed
 * error/ratelimit -> flat
 * approval -> wide
 * thinking -> wide
 * dizzy -> dizzy (or clickCount >= 3)
 * default/idle/working/searching/question -> pill
 */
export function getEyeShape(state: MochiState, clickCount = 0): EyeShape {
  if (clickCount >= 3) return 'dizzy'
  switch (state) {
    case 'finished':
    case 'done':
      return 'happy'
    case 'sleeping':
      return 'closed'
    case 'error':
    case 'ratelimit':
      return 'flat'
    case 'approval':
    case 'thinking':
      return 'wide'
    case 'dizzy':
      return 'dizzy'
    default:
      return 'pill'
  }
}

/**
 * Convert hex color string to rgba CSS string with given alpha.
 */
export function hexToRgba(hex: string, alpha: number): string {
  const clean = hex.replace('#', '')
  if (clean.length === 3) {
    const r = parseInt(clean[0] + clean[0], 16)
    const g = parseInt(clean[1] + clean[1], 16)
    const b = parseInt(clean[2] + clean[2], 16)
    return `rgba(${r}, ${g}, ${b}, ${alpha})`
  }
  if (clean.length === 6) {
    const r = parseInt(clean.substring(0, 2), 16)
    const g = parseInt(clean.substring(2, 4), 16)
    const b = parseInt(clean.substring(4, 6), 16)
    return `rgba(${r}, ${g}, ${b}, ${alpha})`
  }
  return hex
}
