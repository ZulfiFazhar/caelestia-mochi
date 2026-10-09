<script lang="ts">
  import type { AgentInfo } from '../types/agent'
  import { statusToMochiState } from '../types/agent'
  import MiniMochi from './MiniMochi.svelte'

  interface Props {
    agents?: AgentInfo[]
    activeAgent?: AgentInfo | null
    onSelect?: (agent: AgentInfo) => void
    class?: string
  }

  let {
    agents = [],
    activeAgent = null,
    onSelect,
    class: className = '',
  }: Props = $props()

  let filter = $state<'all' | 'running'>('all')

  const runningAgents = $derived(
    agents.filter((a) => {
      const isRunningDetail = Boolean(a.details?.running)
      const isRunningStatus = a.status && !['sleeping', 'idle', 'stopped'].includes(a.status.toLowerCase())
      return isRunningDetail || isRunningStatus || (a.cpu && a.cpu > 0)
    })
  )

  const displayedAgents = $derived(
    filter === 'running' ? runningAgents : agents
  )

  function getStatusBadgeStyle(status?: string): { bg: string; text: string; border: string } {
    const s = (status ?? 'idle').toLowerCase()
    switch (s) {
      case 'working':
      case 'busy':
        return { bg: 'rgba(59, 158, 255, 0.15)', text: '#3b9eff', border: 'rgba(59, 158, 255, 0.4)' }
      case 'thinking':
        return { bg: 'rgba(167, 139, 250, 0.15)', text: '#a78bfa', border: 'rgba(167, 139, 250, 0.4)' }
      case 'searching':
        return { bg: 'rgba(99, 102, 241, 0.15)', text: '#6366f1', border: 'rgba(99, 102, 241, 0.4)' }
      case 'approval':
        return { bg: 'rgba(245, 165, 36, 0.15)', text: '#f5a524', border: 'rgba(245, 165, 36, 0.4)' }
      case 'done':
      case 'finished':
        return { bg: 'rgba(52, 211, 153, 0.15)', text: '#34d399', border: 'rgba(52, 211, 153, 0.4)' }
      case 'error':
        return { bg: 'rgba(244, 80, 94, 0.15)', text: '#f4505e', border: 'rgba(244, 80, 94, 0.4)' }
      case 'sleeping':
      default:
        return { bg: 'rgba(148, 163, 184, 0.12)', text: '#94a3b8', border: 'rgba(148, 163, 184, 0.3)' }
    }
  }
</script>

<div class="agent-roster flex flex-col gap-3 {className}">
  <!-- Filter tabs & summary header -->
  <div class="flex items-center justify-between">
    <div class="flex items-center gap-1.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">
      <span>Agents</span>
      <span class="rounded-full bg-surface-container-high px-2 py-0.5 text-[11px] text-primary">
        {agents.length}
      </span>
    </div>

    <!-- Filter Toggle -->
    <div class="inline-flex rounded-lg bg-surface-container-lowest p-0.5 border border-outline-variant/40 text-[11px]">
      <button
        type="button"
        onclick={() => (filter = 'all')}
        class="rounded-md px-2.5 py-1 font-medium transition cursor-pointer {filter === 'all' ? 'bg-surface-container-high text-primary shadow-xs' : 'text-on-surface-variant hover:text-on-surface'}"
      >
        All ({agents.length})
      </button>
      <button
        type="button"
        onclick={() => (filter = 'running')}
        class="rounded-md px-2.5 py-1 font-medium transition cursor-pointer {filter === 'running' ? 'bg-surface-container-high text-primary shadow-xs' : 'text-on-surface-variant hover:text-on-surface'}"
      >
        Active ({runningAgents.length})
      </button>
    </div>
  </div>

  <!-- Agent Card List -->
  {#if displayedAgents.length === 0}
    <div class="rounded-xl border border-dashed border-outline-variant/50 p-6 text-center text-on-surface-variant">
      <p class="text-xs">No {filter === 'running' ? 'active' : ''} agent harnesses found.</p>
      <p class="text-[11px] opacity-75 mt-1">Use the quick launch bar below to spawn one.</p>
    </div>
  {:else}
    <div class="grid grid-cols-1 gap-2">
      {#each displayedAgents as agent (agent.name)}
        {@const isSelected = activeAgent?.name === agent.name}
        {@const badgeStyle = getStatusBadgeStyle(agent.status)}
        {@const mState = statusToMochiState(agent.status)}

        <button
          type="button"
          onclick={() => onSelect?.(agent)}
          class="group relative flex items-center justify-between gap-3 rounded-xl p-3 text-left transition-all cursor-pointer border {isSelected ? 'bg-surface-container-high border-primary/80 shadow-md ring-1 ring-primary/40' : 'bg-surface-container hover:bg-surface-container-high border-outline-variant/40'}"
        >
          <!-- Left: MiniMochi avatar & Name -->
          <div class="flex items-center gap-3 min-w-0">
            <MiniMochi state={mState} size={28} />
            <div class="truncate">
              <div class="flex items-center gap-2">
                <span class="text-xs sm:text-sm font-semibold text-on-surface truncate">
                  {agent.name}
                </span>
                {#if agent.pid}
                  <span class="text-[10px] font-mono text-on-surface-variant/75">
                    #{agent.pid}
                  </span>
                {/if}
              </div>
              <p class="text-[11px] font-mono text-on-surface-variant truncate max-w-[180px] sm:max-w-xs">
                {agent.command || 'Idle process'}
              </p>
            </div>
          </div>

          <!-- Right: Badges (Status, CPU, Memory) -->
          <div class="flex items-center gap-2 shrink-0">
            <!-- CPU badge -->
            {#if agent.cpu !== undefined}
              <span
                class="hidden sm:inline-flex items-center rounded-md px-1.5 py-0.5 text-[10px] font-mono font-medium"
                style="
                  background-color: {agent.cpu > 20 ? 'rgba(244, 80, 94, 0.15)' : 'rgba(255, 255, 255, 0.05)'};
                  color: {agent.cpu > 20 ? '#f4505e' : 'var(--color-on-surface-variant)'};
                "
              >
                {agent.cpu.toFixed(1)}% CPU
              </span>
            {/if}

            <!-- Memory badge -->
            {#if agent.memory !== undefined}
              <span class="hidden sm:inline-flex items-center rounded-md bg-surface-container-lowest px-1.5 py-0.5 text-[10px] font-mono font-medium text-on-surface-variant">
                {agent.memory.toFixed(1)}% MEM
              </span>
            {/if}

            <!-- Status Pill badge -->
            <span
              class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider"
              style="
                background-color: {badgeStyle.bg};
                color: {badgeStyle.text};
                border: 1px solid {badgeStyle.border};
              "
            >
              <span class="w-1 h-1 rounded-full" style="background-color: {badgeStyle.text};"></span>
              <span>{agent.status || 'idle'}</span>
            </span>
          </div>
        </button>
      {/each}
    </div>
  {/if}
</div>
