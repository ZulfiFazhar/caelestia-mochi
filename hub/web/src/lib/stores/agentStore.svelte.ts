import type {
  AgentInfo,
  ApprovalRequest,
  ConnectionStatus,
  MochiState,
  SystemState,
  TimelineEntry,
} from '../types/agent'
import { statusToMochiState } from '../types/agent'

export interface AgentStoreOptions {
  baseUrl?: string
  initialBackoffMs?: number
  maxBackoffMs?: number
  backoffFactor?: number
  fetchFn?: typeof fetch
  eventSourceFactory?: (url: string) => EventSource
  autoConnect?: boolean
  authToken?: string
}

export class AgentStore {
  agents = $state<AgentInfo[]>([])
  activeAgent = $state<AgentInfo | null>(null)
  mochiState = $state<MochiState>('sleeping')
  activeApproval = $state<ApprovalRequest | null>(null)
  pendingApprovals = $state<ApprovalRequest[]>([])
  connectionStatus = $state<ConnectionStatus>('disconnected')
  lastUpdated = $state<number>(0)
  timeline = $state<TimelineEntry[]>([])
  errorMessage = $state<string | null>(null)
  reconnectAttempts = $state<number>(0)
  authToken: string | null = null
  activeSessionId = $state<string | null>(null)

  private baseUrl: string
  private initialBackoffMs: number
  private maxBackoffMs: number
  private backoffFactor: number
  private fetchFn: typeof fetch
  private eventSourceFactory?: (url: string) => EventSource
  private eventSource: EventSource | null = null
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private isDestroyed = false

  // Bound listeners to ensure exact references for teardown
  private readonly onOpenListener = () => this.handleOpen()
  private readonly onErrorListener = (_e: Event) => this.handleError()
  private readonly onStateUpdateListener = (e: MessageEvent) => this.handleStateUpdate(e)
  private readonly onApprovalRequestListener = (e: MessageEvent) => this.handleApprovalRequest(e)
  private readonly onSessionOutputListener = (e: MessageEvent) => this.handleSessionOutput(e)

  constructor(options: AgentStoreOptions = {}) {
    this.baseUrl = options.baseUrl ?? ''
    this.initialBackoffMs = options.initialBackoffMs ?? 1000
    this.maxBackoffMs = options.maxBackoffMs ?? 16000
    this.backoffFactor = options.backoffFactor ?? 2
    this.fetchFn = options.fetchFn ?? (typeof fetch !== 'undefined' ? fetch.bind(globalThis) : (null as any))
    this.eventSourceFactory = options.eventSourceFactory
    this.authToken = options.authToken ?? ((globalThis as any).process?.env?.MOCHI_AUTH_TOKEN ?? null)

    if (options.autoConnect) {
      this.connect()
    }
  }

  /**
   * Calculate backoff duration for current reconnection attempt.
   */
  public getBackoffDelay(): number {
    return Math.min(
      this.maxBackoffMs,
      this.initialBackoffMs * Math.pow(this.backoffFactor, this.reconnectAttempts)
    )
  }

  /**
   * Full teardown of existing EventSource connection and listeners.
   * Prevents memory leaks and duplicate message handlers upon reconnect.
   */
  public teardown(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }

    if (this.eventSource) {
      this.eventSource.removeEventListener('open', this.onOpenListener)
      this.eventSource.removeEventListener('error', this.onErrorListener)
      this.eventSource.removeEventListener('state_update', this.onStateUpdateListener)
      this.eventSource.removeEventListener('approval_request', this.onApprovalRequestListener)
      this.eventSource.removeEventListener('session_output', this.onSessionOutputListener)
      this.eventSource.close()
      this.eventSource = null
    }
  }

  /**
   * Schedule reconnection with exponential backoff.
   */
  public scheduleReconnect(): void {
    if (this.isDestroyed) return

    // Teardown first to remove existing event listeners
    this.teardown()

    this.connectionStatus = 'reconnecting'
    const delay = this.getBackoffDelay()
    this.reconnectAttempts++
    this.errorMessage = `Reconnecting in ${(delay / 1000).toFixed(1)}s (attempt ${this.reconnectAttempts})...`

    this.reconnectTimer = setTimeout(() => {
      if (!this.isDestroyed) {
        this.connect()
      }
    }, delay)
  }

  /**
   * Establish connection to SSE stream and initiate initial REST state sync.
   */
  public connect(customUrl?: string): void {
    if (this.isDestroyed) return

    this.teardown()
    this.connectionStatus = this.reconnectAttempts > 0 ? 'reconnecting' : 'connecting'

    // Initial REST state fetch
    this.fetchAgents().catch(() => {})

    const sseEndpoint =
      customUrl ??
      (this.authToken
        ? `${this.baseUrl}/api/events?token=${encodeURIComponent(this.authToken)}`
        : `${this.baseUrl}/api/events`)

    try {
      let es: EventSource
      if (this.eventSourceFactory) {
        es = this.eventSourceFactory(sseEndpoint)
      } else if (typeof EventSource !== 'undefined') {
        es = new EventSource(sseEndpoint)
      } else {
        // Non-browser or mock environment without EventSource
        return
      }

      this.eventSource = es
      es.addEventListener('open', this.onOpenListener)
      es.addEventListener('error', this.onErrorListener)
      es.addEventListener('state_update', this.onStateUpdateListener)
      es.addEventListener('approval_request', this.onApprovalRequestListener)
      es.addEventListener('session_output', this.onSessionOutputListener)
    } catch {
      this.scheduleReconnect()
    }
  }

  /**
   * Disconnect manually.
   */
  public disconnect(): void {
    this.teardown()
    this.connectionStatus = 'disconnected'
    this.reconnectAttempts = 0
  }

  /**
   * Cleanup and destroy store permanently.
   */
  public destroy(): void {
    this.isDestroyed = true
    this.disconnect()
  }

  /**
   * Handle SSE stream open event.
   */
  private handleOpen(): void {
    this.connectionStatus = 'connected'
    this.reconnectAttempts = 0
    this.errorMessage = null
    this.addTimelineEntry({
      type: 'system',
      text: 'Connected to Mochi Hub realtime stream',
    })
  }

  /**
   * Handle SSE stream error event.
   */
  private handleError(): void {
    if (this.isDestroyed) return
    this.scheduleReconnect()
  }

  /**
   * Handle state_update SSE event.
   */
  private handleStateUpdate(e: MessageEvent): void {
    try {
      const parsed: SystemState = typeof e.data === 'string' ? JSON.parse(e.data) : e.data
      this.applySystemState(parsed)
    } catch (err) {
      console.warn('Failed to parse state_update event:', err)
    }
  }

  /**
   * Handle approval_request SSE event.
   */
  private handleApprovalRequest(e: MessageEvent): void {
    try {
      const parsed: ApprovalRequest = typeof e.data === 'string' ? JSON.parse(e.data) : e.data
      this.addApproval(parsed)
    } catch (err) {
      console.warn('Failed to parse approval_request event:', err)
    }
  }

  /**
   * Handle session_output SSE event.
   */
  private handleSessionOutput(e: MessageEvent): void {
    try {
      const parsed = typeof e.data === 'string' ? JSON.parse(e.data) : e.data
      const sessionId = parsed.session_id ?? this.activeSessionId ?? 'Session'
      const outputText = typeof parsed.data === 'string' ? parsed.data : JSON.stringify(parsed.data)
      if (outputText) {
        this.addTimelineEntry({
          type: 'terminal',
          text: outputText,
          sender: sessionId,
        })
      }
    } catch (err) {
      console.warn('Failed to parse session_output event:', err)
    }
  }

  private getRequestHeaders(): Record<string, string> {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' }
    if (this.authToken) {
      headers['Authorization'] = `Bearer ${this.authToken}`
    }
    return headers
  }

  /**
   * Initial or periodic REST fetch of system agents state.
   */
  public async fetchAgents(): Promise<SystemState | null> {
    if (!this.fetchFn) return null
    try {
      const headers: Record<string, string> = {}
      if (this.authToken) {
        headers['Authorization'] = `Bearer ${this.authToken}`
      }
      const res = await this.fetchFn(`${this.baseUrl}/api/agents`, { headers })
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`)
      }
      const data: SystemState = await res.json()
      this.applySystemState(data)
      return data
    } catch (err) {
      if (this.connectionStatus === 'disconnected') {
        this.errorMessage = 'Unable to reach Mochi daemon'
      }
      return null
    }
  }

  /**
   * Apply incoming system state into store.
   */
  public applySystemState(data: SystemState): void {
    this.agents = data.agents ?? []
    this.lastUpdated = data.timestamp ? (data.timestamp > 1e11 ? data.timestamp : data.timestamp * 1000) : Date.now()

    // Active approval overrides general mochi state
    if (!this.activeApproval) {
      this.mochiState = data.mochi_state ?? 'sleeping'
    }

    if (data.active_agent) {
      this.activeAgent = data.active_agent
    } else if (this.agents.length > 0) {
      const currentExists = this.activeAgent ? this.agents.find((a) => a.name === this.activeAgent?.name) : null
      if (currentExists) {
        this.activeAgent = currentExists
      } else {
        const running = this.agents.find((a) => a.details?.running)
        this.activeAgent = running ?? this.agents[0]
      }
    } else {
      this.activeAgent = null
    }
  }

  /**
   * Push a pending approval request.
   */
  public addApproval(approval: ApprovalRequest): void {
    const exists = this.pendingApprovals.some((a) => a.approval_id === approval.approval_id)
    if (!exists) {
      this.pendingApprovals = [...this.pendingApprovals, approval]
    }

    this.activeApproval = approval
    this.mochiState = 'approval'

    const targetDesc = approval.command || approval.prompt || approval.matched_text || 'System Action'
    this.addTimelineEntry({
      type: 'approval',
      text: `Approval requested: ${targetDesc}`,
      sender: approval.session_id ?? 'Daemon',
      status: 'pending',
    })
  }

  /**
   * Submit an approval decision (allow/deny) via REST endpoint.
   */
  public async respondApproval(approvalId: string, approved: boolean, reason = ''): Promise<boolean> {
    if (!this.fetchFn) return false
    try {
      const res = await this.fetchFn(`${this.baseUrl}/api/approvals/${approvalId}`, {
        method: 'POST',
        headers: this.getRequestHeaders(),
        body: JSON.stringify({ approved, reason }),
      })

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`)
      }

      // Remove resolved approval from pending list
      this.pendingApprovals = this.pendingApprovals.filter((a) => a.approval_id !== approvalId)
      if (this.activeApproval?.approval_id === approvalId) {
        this.activeApproval = this.pendingApprovals[0] ?? null
      }

      // Revert state from 'approval' if no more pending
      if (!this.activeApproval) {
        if (this.activeAgent?.status) {
          this.mochiState = statusToMochiState(this.activeAgent.status)
        } else {
          this.mochiState = 'working'
        }
      }

      this.addTimelineEntry({
        type: 'system',
        text: `${approved ? 'Allowed' : 'Denied'} approval [${approvalId}]${reason ? `: ${reason}` : ''}`,
      })

      return true
    } catch (err) {
      console.error('Failed to submit approval response:', err)
      return false
    }
  }

  /**
   * Set active agent explicitly.
   */
  public setActiveAgent(agent: AgentInfo): void {
    this.activeAgent = agent
    if (!this.activeApproval) {
      this.mochiState = statusToMochiState(agent.status)
    }
    this.addTimelineEntry({
      type: 'system',
      text: `Switched view to agent: ${agent.name}`,
    })
  }

  /**
   * Add a new timeline or transcript item.
   */
  public addTimelineEntry(entry: Partial<TimelineEntry> & { text: string; type: TimelineEntry['type'] }): TimelineEntry {
    const fullEntry: TimelineEntry = {
      id: `entry-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      timestamp: Date.now(),
      sender: this.activeAgent?.name ?? 'System',
      ...entry,
    }

    // ponytail: cap timeline at 200 items; upgrade path: virtualized windowed scroller when timeline exceeds 10k items
    if (this.timeline.length >= 200) {
      this.timeline = [...this.timeline.slice(-199), fullEntry]
    } else {
      this.timeline = [...this.timeline, fullEntry]
    }

    return fullEntry
  }

  /**
   * Clear timeline transcript.
   */
  public clearTimeline(): void {
    this.timeline = []
  }

  /**
   * Send command input from UI to current active agent or session.
   */
  public sendCommand(commandText: string): void {
    const trimmed = commandText.trim()
    if (!trimmed) return

    this.addTimelineEntry({
      type: 'user',
      text: trimmed,
      sender: 'User',
    })

    const agentName = this.activeAgent?.name ?? 'Mochi'
    this.addTimelineEntry({
      type: 'terminal',
      text: `$ ${trimmed}`,
      sender: agentName,
    })

    if (this.mochiState === 'sleeping' || this.mochiState === 'idle') {
      this.mochiState = 'working'
    }
  }

  /**
   * Launch harness quick action.
   */
  public launchHarness(harnessId: string): void {
    this.sendCommand(`launch ${harnessId}`)
  }

  /**
   * Spawn a PTY session via POST /api/sessions.
   */
  public async spawnSession(command: string[]): Promise<string | null> {
    if (!this.fetchFn) return null
    try {
      const res = await this.fetchFn(`${this.baseUrl}/api/sessions`, {
        method: 'POST',
        headers: this.getRequestHeaders(),
        body: JSON.stringify({ command }),
      })
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`)
      }
      const data = await res.json()
      const sessionId: string = data.session_id
      this.activeSessionId = sessionId
      this.mochiState = 'working'
      this.addTimelineEntry({
        type: 'system',
        text: `Session spawned: ${sessionId} (${command.join(' ')})`,
      })
      return sessionId
    } catch (err) {
      console.error('Failed to spawn session:', err)
      this.addTimelineEntry({
        type: 'system',
        text: `Failed to spawn session: ${command.join(' ')}`,
      })
      return null
    }
  }

  /**
   * Send text input to an active session via POST /api/sessions/{session_id}/input.
   */
  public async sendInput(sessionId: string, input: string): Promise<boolean> {
    if (!this.fetchFn) return false
    try {
      const res = await this.fetchFn(`${this.baseUrl}/api/sessions/${sessionId}/input`, {
        method: 'POST',
        headers: this.getRequestHeaders(),
        body: JSON.stringify({ data: input }),
      })
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`)
      }
      return true
    } catch (err) {
      console.error('Failed to send input to session:', err)
      return false
    }
  }
}

/**
 * Factory function for creating an AgentStore instance.
 */
export function createAgentStore(options: AgentStoreOptions = {}): AgentStore {
  return new AgentStore(options)
}

/**
 * Shared singleton store instance for the application.
 */
export const agentStore = createAgentStore()
