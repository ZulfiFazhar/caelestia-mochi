import { describe, expect, it } from 'bun:test'

if (typeof (globalThis as any).$state === 'undefined') {
  ;(globalThis as any).$state = (v: any) => v
}

const { AgentStore, createAgentStore } = await import('../src/lib/stores/agentStore.svelte')
import ApprovalCard from '../src/lib/components/ApprovalCard.svelte'
import AgentRoster from '../src/lib/components/AgentRoster.svelte'
import ChatTimeline from '../src/lib/components/ChatTimeline.svelte'
import type { ApprovalRequest, SystemState } from '../src/lib/types/agent'

class MockEventSource {
  public url: string
  public closed = false
  public listeners: Record<string, Set<(e: any) => void>> = {}

  constructor(url: string) {
    this.url = url
  }

  addEventListener(type: string, handler: (e: any) => void) {
    if (!this.listeners[type]) {
      this.listeners[type] = new Set()
    }
    this.listeners[type].add(handler)
  }

  removeEventListener(type: string, handler: (e: any) => void) {
    this.listeners[type]?.delete(handler)
  }

  emit(type: string, data: any) {
    const handlers = this.listeners[type]
    if (handlers) {
      for (const h of handlers) {
        h({ data, type } as any)
      }
    }
  }

  close() {
    this.closed = true
  }

  listenerCount(type: string): number {
    return this.listeners[type]?.size ?? 0
  }
}

describe('AgentStore (Svelte 5 Runes)', () => {
  it('initializes with default empty and disconnected state', () => {
    const store = createAgentStore({ autoConnect: false })
    expect(store.agents).toEqual([])
    expect(store.activeAgent).toBeNull()
    expect(store.mochiState).toBe('sleeping')
    expect(store.activeApproval).toBeNull()
    expect(store.pendingApprovals).toEqual([])
    expect(store.connectionStatus).toBe('disconnected')
    expect(store.reconnectAttempts).toBe(0)
    expect(store.timeline).toEqual([])
  })

  it('fetchAgents() requests /api/agents and populates store state', async () => {
    const mockState: SystemState = {
      timestamp: 1720000000,
      agents: [
        {
          name: 'OpenCode',
          command: 'bun test',
          pid: 101,
          status: 'working',
          cpu: 18.4,
          memory: 42.1,
          details: { running: true },
        },
      ],
      active_agent: {
        name: 'OpenCode',
        status: 'working',
      },
      mochi_state: 'working',
    }

    const mockFetch = async (url: string) => {
      expect(url).toContain('/api/agents')
      return {
        ok: true,
        json: async () => mockState,
      } as any
    }

    const store = createAgentStore({
      baseUrl: 'http://localhost:8799',
      fetchFn: mockFetch as any,
      autoConnect: false,
    })

    const result = await store.fetchAgents()
    expect(result).not.toBeNull()
    expect(store.agents).toHaveLength(1)
    expect(store.agents[0].name).toBe('OpenCode')
    expect(store.activeAgent?.name).toBe('OpenCode')
    expect(store.mochiState).toBe('working')
  })

  it('processes SSE state_update and updates agents reactive state', () => {
    let mockEs: MockEventSource | null = null
    const store = createAgentStore({
      eventSourceFactory: (url) => {
        mockEs = new MockEventSource(url)
        return mockEs as any
      },
      autoConnect: false,
    })

    store.connect('http://localhost:8799/api/events')
    expect(mockEs).not.toBeNull()

    // Simulate open
    mockEs!.emit('open', {})
    expect(store.connectionStatus).toBe('connected')
    expect(store.reconnectAttempts).toBe(0)

    // Simulate state update
    const stateUpdate: SystemState = {
      timestamp: Date.now(),
      agents: [
        { name: 'Claude Code', status: 'thinking', cpu: 12.0 },
        { name: 'Antigravity', status: 'idle', cpu: 0.0 },
      ],
      mochi_state: 'thinking',
    }
    mockEs!.emit('state_update', JSON.stringify(stateUpdate))

    expect(store.agents).toHaveLength(2)
    expect(store.mochiState).toBe('thinking')
    expect(store.activeAgent?.name).toBe('Claude Code')

    store.destroy()
  })

  it('processes SSE approval_request, transitions mochiState to approval, and logs to timeline', () => {
    let mockEs: MockEventSource | null = null
    const store = createAgentStore({
      eventSourceFactory: (url) => {
        mockEs = new MockEventSource(url)
        return mockEs as any
      },
      autoConnect: false,
    })

    store.connect()
    const approvalPayload: ApprovalRequest = {
      approval_id: 'appr-987654',
      session_id: 'ses-1',
      command: 'rm -rf /var/cache/test',
      prompt: 'Execute command? (y/n)',
      timestamp: Date.now(),
      resolved: false,
    }

    mockEs!.emit('approval_request', JSON.stringify(approvalPayload))

    expect(store.activeApproval).not.toBeNull()
    expect(store.activeApproval?.approval_id).toBe('appr-987654')
    expect(store.mochiState).toBe('approval')
    expect(store.pendingApprovals).toHaveLength(1)

    // Timeline must contain approval entry
    const approvalTimeline = store.timeline.find((t) => t.type === 'approval')
    expect(approvalTimeline).toBeDefined()
    expect(approvalTimeline?.text).toContain('rm -rf /var/cache/test')

    store.destroy()
  })

  it('respondApproval() posts decision, prunes pending queue, and reverts mochiState', async () => {
    let postedUrl = ''
    let postedBody: any = null

    const mockFetch = async (url: string, options: any) => {
      postedUrl = url
      postedBody = JSON.parse(options.body)
      return { ok: true, json: async () => ({ status: 'recorded' }) } as any
    }

    const store = createAgentStore({
      baseUrl: 'http://localhost:8799',
      fetchFn: mockFetch as any,
      autoConnect: false,
    })

    store.addApproval({
      approval_id: 'appr-abc-123',
      session_id: 'session-xyz',
      command: 'chmod +x run.sh',
    })

    expect(store.activeApproval?.approval_id).toBe('appr-abc-123')
    expect(store.mochiState).toBe('approval')

    const success = await store.respondApproval('appr-abc-123', true)
    expect(success).toBe(true)
    expect(postedUrl).toBe('http://localhost:8799/api/approvals/appr-abc-123')
    expect(postedBody).toEqual({ approved: true, reason: '' })
    expect(store.activeApproval).toBeNull()
    expect(store.pendingApprovals).toHaveLength(0)
    expect(store.mochiState).not.toBe('approval')

    store.destroy()
  })

  it('calculates exponential backoff delay correctly with cap (Review Focus 2)', () => {
    const store = createAgentStore({
      initialBackoffMs: 1000,
      maxBackoffMs: 16000,
      backoffFactor: 2,
      autoConnect: false,
    })

    // 0 attempts -> 1000
    expect(store.getBackoffDelay()).toBe(1000)

    store.reconnectAttempts = 1
    expect(store.getBackoffDelay()).toBe(2000)

    store.reconnectAttempts = 2
    expect(store.getBackoffDelay()).toBe(4000)

    store.reconnectAttempts = 3
    expect(store.getBackoffDelay()).toBe(8000)

    store.reconnectAttempts = 4
    expect(store.getBackoffDelay()).toBe(16000)

    store.reconnectAttempts = 10
    expect(store.getBackoffDelay()).toBe(16000) // Capped at maxBackoffMs

    store.destroy()
  })

  it('performs clean teardown and removes old listeners before reconnect (Review Focus 2)', () => {
    let mockEs: MockEventSource | null = null

    const store = createAgentStore({
      eventSourceFactory: (url) => {
        mockEs = new MockEventSource(url)
        return mockEs as any
      },
      autoConnect: false,
    })

    store.connect()
    expect(mockEs).not.toBeNull()
    expect(mockEs!.listenerCount('open')).toBe(1)
    expect(mockEs!.listenerCount('error')).toBe(1)
    expect(mockEs!.listenerCount('state_update')).toBe(1)
    expect(mockEs!.listenerCount('approval_request')).toBe(1)
    expect(mockEs!.closed).toBe(false)

    const firstEs = mockEs!

    // Reconnecting or calling teardown must cleanly detach all listeners and close ES
    store.teardown()
    expect(firstEs.closed).toBe(true)
    expect(firstEs.listenerCount('open')).toBe(0)
    expect(firstEs.listenerCount('error')).toBe(0)
    expect(firstEs.listenerCount('state_update')).toBe(0)
    expect(firstEs.listenerCount('approval_request')).toBe(0)

    // Reconnect again: must not duplicate handlers
    store.connect()
    const secondEs = mockEs!
    expect(secondEs).not.toBe(firstEs)
    expect(secondEs.listenerCount('open')).toBe(1)
    expect(secondEs.listenerCount('state_update')).toBe(1)

    store.destroy()
  })

  it('records user command and terminal log into timeline', () => {
    const store = createAgentStore({ autoConnect: false })
    store.sendCommand('bun run build')

    expect(store.timeline).toHaveLength(2)
    expect(store.timeline[0].type).toBe('user')
    expect(store.timeline[0].text).toBe('bun run build')
    expect(store.timeline[1].type).toBe('terminal')
    expect(store.timeline[1].text).toBe('$ bun run build')

    store.launchHarness('opencode')
    expect(store.timeline).toHaveLength(4)
    expect(store.timeline[2].text).toBe('launch opencode')

    store.clearTimeline()
    expect(store.timeline).toHaveLength(0)

    store.destroy()
  })

  it('spawns session and sends input via REST endpoints', async () => {
    let capturedSpawnUrl = ''
    let capturedSpawnBody: any = null
    let capturedInputUrl = ''
    let capturedInputBody: any = null
    let capturedHeaders: any = null

    const mockFetch = async (url: string, opts?: any) => {
      if (url.includes('/api/sessions') && !url.includes('/input')) {
        capturedSpawnUrl = url
        capturedSpawnBody = JSON.parse(opts.body)
        capturedHeaders = opts.headers
        return {
          ok: true,
          json: async () => ({ session_id: 'session-xyz', status: 'spawned' }),
        } as any
      }
      if (url.includes('/input')) {
        capturedInputUrl = url
        capturedInputBody = JSON.parse(opts.body)
        return {
          ok: true,
          json: async () => ({ status: 'ok' }),
        } as any
      }
      return { ok: true, json: async () => ({}) } as any
    }

    const store = createAgentStore({
      baseUrl: 'http://localhost:8799',
      fetchFn: mockFetch as any,
      autoConnect: false,
      authToken: 'test-token-456',
    })

    const sid = await store.spawnSession(['echo', 'hello'])
    expect(sid).toBe('session-xyz')
    expect(capturedSpawnUrl).toBe('http://localhost:8799/api/sessions')
    expect(capturedSpawnBody).toEqual({ command: ['echo', 'hello'] })
    expect(capturedHeaders['Authorization']).toBe('Bearer test-token-456')
    expect(store.timeline.some((t) => t.text.includes('Session spawned: session-xyz'))).toBe(true)

    const inputOk = await store.sendInput('session-xyz', 'test data\n')
    expect(inputOk).toBe(true)
    expect(capturedInputUrl).toBe('http://localhost:8799/api/sessions/session-xyz/input')
    expect(capturedInputBody).toEqual({ data: 'test data\n' })

    store.destroy()
  })

  it('streams session output SSE into timeline', () => {
    let mockEs: MockEventSource | null = null
    const store = createAgentStore({
      baseUrl: 'http://localhost:8799',
      eventSourceFactory: (url) => {
        mockEs = new MockEventSource(url)
        return mockEs as any
      },
      autoConnect: true,
      authToken: 'token123',
    })

    expect(mockEs!.url).toContain('token=token123')

    mockEs!.emit('session_output', JSON.stringify({
      session_id: 'session-abc',
      data: 'Process output line 1\nProcess output line 2',
    }))

    const terminalEntry = store.timeline.find((t) => t.sender === 'session-abc')
    expect(terminalEntry).toBeDefined()
    expect(terminalEntry?.type).toBe('terminal')
    expect(terminalEntry?.text).toBe('Process output line 1\nProcess output line 2')

    store.destroy()
  })

  it('exports valid UI components for the dashboard', () => {
    expect(ApprovalCard).toBeDefined()
    expect(AgentRoster).toBeDefined()
    expect(ChatTimeline).toBeDefined()
  })
})
