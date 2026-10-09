<script lang="ts">
  import { agentStore } from './lib/stores/agentStore.svelte'
  import type { AgentInfo, MochiState } from './lib/types/agent'
  import MochiBot from './lib/components/MochiBot.svelte'
  import MiniMochi from './lib/components/MiniMochi.svelte'
  import AgentRoster from './lib/components/AgentRoster.svelte'
  import ApprovalCard from './lib/components/ApprovalCard.svelte'
  import ChatTimeline from './lib/components/ChatTimeline.svelte'

  let commandInput = $state('')
  let showRosterDrawer = $state(false)

  // Start realtime connection on mount and teardown cleanly on unmount
  $effect(() => {
    agentStore.connect()
    return () => {
      agentStore.teardown()
    }
  })

  function getCompanionSubtitle(state: MochiState): string {
    switch (state) {
      case 'working':
        return 'Mochi is busy working...'
      case 'thinking':
        return 'Mochi is deep in thought...'
      case 'searching':
        return 'Mochi is searching repository...'
      case 'approval':
        return 'Permission required!'
      case 'question':
        return 'Mochi has a question'
      case 'done':
      case 'finished':
        return 'Task completed successfully!'
      case 'error':
        return 'Something went wrong'
      case 'dizzy':
        return 'Whoa, feeling dizzy!'
      case 'sleeping':
        return 'Mochi is resting (zzz)'
      default:
        return 'Ready for instructions'
    }
  }

  function handleCommandSubmit(e: SubmitEvent) {
    e.preventDefault()
    if (!commandInput.trim()) return
    agentStore.sendCommand(commandInput)
    commandInput = ''
  }

  const QUICK_HARNESSES = [
    { id: 'opencode', name: 'OpenCode' },
    { id: 'claude', name: 'Claude' },
    { id: 'antigravity', name: 'Antigravity' },
    { id: 'codex', name: 'Codex' },
    { id: 'aider', name: 'Aider' },
  ]
</script>

<div class="min-h-screen bg-surface text-on-surface flex flex-col selection:bg-primary selection:text-on-primary">
  <!-- Top Application Bar -->
  <header class="sticky top-0 z-30 bg-surface/90 backdrop-blur-md border-b border-outline-variant/30 px-4 py-2.5 flex items-center justify-between">
    <div class="flex items-center gap-2.5">
      <MiniMochi state={agentStore.mochiState} size={24} />
      <span class="font-bold text-sm sm:text-base tracking-tight text-primary">Mochi Hub</span>
    </div>

    <!-- Connection Status Pill -->
    <div class="flex items-center gap-2">
      <div
        class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-mono border"
        style="
          background-color: {agentStore.connectionStatus === 'connected' ? 'rgba(74, 222, 128, 0.12)' : agentStore.connectionStatus === 'reconnecting' ? 'rgba(245, 165, 36, 0.12)' : 'rgba(244, 80, 94, 0.12)'};
          color: {agentStore.connectionStatus === 'connected' ? '#4ade80' : agentStore.connectionStatus === 'reconnecting' ? '#f5a524' : '#f4505e'};
          border-color: {agentStore.connectionStatus === 'connected' ? 'rgba(74, 222, 128, 0.3)' : agentStore.connectionStatus === 'reconnecting' ? 'rgba(245, 165, 36, 0.3)' : 'rgba(244, 80, 94, 0.3)'};
        "
      >
        <span
          class="w-1.5 h-1.5 rounded-full {agentStore.connectionStatus === 'reconnecting' ? 'animate-ping' : ''}"
          style="background-color: {agentStore.connectionStatus === 'connected' ? '#4ade80' : agentStore.connectionStatus === 'reconnecting' ? '#f5a524' : '#f4505e'};"
        ></span>
        <span class="capitalize">{agentStore.connectionStatus}</span>
      </div>

      {#if agentStore.connectionStatus !== 'connected'}
        <button
          type="button"
          onclick={() => agentStore.connect()}
          title="Retry connection"
          class="rounded-lg p-1 text-on-surface-variant hover:text-on-surface hover:bg-surface-container transition cursor-pointer"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
      {/if}

      <!-- Mobile roster toggle -->
      <button
        type="button"
        onclick={() => (showRosterDrawer = !showRosterDrawer)}
        class="md:hidden rounded-lg p-1.5 text-on-surface-variant hover:text-on-surface hover:bg-surface-container transition cursor-pointer"
        title="Toggle Agents Roster"
      >
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </button>
    </div>
  </header>

  <!-- Interactive Mochi Companion Hero Banner -->
  <section class="flex flex-col items-center justify-center pt-4 pb-2 px-4 shrink-0 bg-gradient-to-b from-surface-container-lowest/50 to-transparent">
    <div class="relative flex flex-col items-center">
      <MochiBot
        state={agentStore.mochiState}
        size={84}
        interactive={true}
        class="drop-shadow-lg"
      />
      <div class="mt-2 text-center">
        <h1 class="text-sm font-semibold text-on-surface">
          {getCompanionSubtitle(agentStore.mochiState)}
        </h1>
        {#if agentStore.activeAgent}
          <p class="text-[11px] font-mono text-primary mt-0.5">
            Target: {agentStore.activeAgent.name}
          </p>
        {/if}
      </div>
    </div>
  </section>

  <!-- Main Content Layout (Mobile first, 2-col on desktop) -->
  <main class="flex-1 max-w-7xl w-full mx-auto p-3 sm:p-4 flex flex-col md:grid md:grid-cols-12 gap-4 pb-28">
    <!-- Left Column: Pending Approvals & Agent Roster -->
    <div class="md:col-span-4 flex flex-col gap-4 {showRosterDrawer ? 'block' : 'hidden md:flex'}">
      <!-- Agent Roster Component -->
      <div class="rounded-2xl bg-surface-container p-4 border border-outline-variant/30 shadow-sm">
        <AgentRoster
          agents={agentStore.agents}
          activeAgent={agentStore.activeAgent}
          onSelect={(agent: AgentInfo) => {
            agentStore.setActiveAgent(agent)
            showRosterDrawer = false
          }}
        />
      </div>
    </div>

    <!-- Right Column: Active Approval Alert & Chat/Terminal Timeline -->
    <div class="md:col-span-8 flex flex-col gap-4 flex-1">
      <!-- Prominent Pending Approval Modal Card (Review Focus 3) -->
      {#if agentStore.activeApproval}
        <div class="animate-in fade-in slide-in-from-top-2 duration-300">
          <ApprovalCard
            approval={agentStore.activeApproval}
            timeoutSeconds={60}
            onAllow={(id) => agentStore.respondApproval(id, true)}
            onDeny={(id, reason) => agentStore.respondApproval(id, false, reason)}
          />
        </div>
      {/if}

      <!-- Agent Switcher Tabs on mobile -->
      {#if agentStore.agents.length > 0}
        <div class="md:hidden flex items-center gap-1.5 overflow-x-auto pb-1 no-scrollbar">
          {#each agentStore.agents as agent (agent.name)}
            {@const isSelected = agentStore.activeAgent?.name === agent.name}
            <button
              type="button"
              onclick={() => agentStore.setActiveAgent(agent)}
              class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium whitespace-nowrap transition cursor-pointer border {isSelected ? 'bg-primary text-on-primary border-primary shadow-xs' : 'bg-surface-container text-on-surface-variant border-outline-variant/40 hover:bg-surface-container-high'}"
            >
              <span>{agent.name}</span>
              {#if agent.cpu && agent.cpu > 0}
                <span class="text-[10px] opacity-75 font-mono">{agent.cpu.toFixed(0)}%</span>
              {/if}
            </button>
          {/each}
        </div>
      {/if}

      <!-- Chat Timeline / Terminal Transcript -->
      <div class="flex-1 min-h-[360px] flex flex-col">
        <ChatTimeline
          entries={agentStore.timeline}
          activeAgent={agentStore.activeAgent}
          onClear={() => agentStore.clearTimeline()}
          class="flex-1"
        />
      </div>
    </div>
  </main>

  <!-- Bottom Input Bar & Harness Launch Quick-Actions (Sticky / Fixed) -->
  <footer class="fixed bottom-0 left-0 right-0 z-20 bg-surface/95 backdrop-blur-lg border-t border-outline-variant/40 p-2 sm:p-3">
    <div class="max-w-4xl mx-auto flex flex-col gap-2">
      <!-- Quick Harness Launch Actions -->
      <div class="flex items-center gap-1.5 overflow-x-auto pb-0.5 no-scrollbar text-xs">
        <span class="text-[10px] font-semibold uppercase tracking-wider text-on-surface-variant/75 shrink-0 pl-1">
          Launch:
        </span>
        {#each QUICK_HARNESSES as h}
          <button
            type="button"
            onclick={() => agentStore.launchHarness(h.id)}
            class="inline-flex items-center gap-1 rounded-lg bg-surface-container-high px-2.5 py-1 text-[11px] font-mono text-on-surface hover:bg-surface-container-highest hover:text-primary transition cursor-pointer border border-outline-variant/30 active:scale-95 shrink-0"
          >
            <span>▶</span>
            <span>{h.name}</span>
          </button>
        {/each}
      </div>

      <!-- Command Input Box -->
      <form onsubmit={handleCommandSubmit} class="flex items-center gap-2">
        <div class="relative flex-1">
          <input
            type="text"
            bind:value={commandInput}
            placeholder={agentStore.activeAgent ? `Message or command to ${agentStore.activeAgent.name}...` : 'Send command to session...'}
            class="w-full rounded-xl bg-surface-container-high px-4 py-2.5 text-xs sm:text-sm text-on-surface placeholder:text-on-surface-variant/60 border border-outline-variant/60 focus:border-primary focus:ring-1 focus:ring-primary focus:outline-hidden font-mono"
          />
        </div>
        <button
          type="submit"
          disabled={!commandInput.trim()}
          class="rounded-xl px-4 py-2.5 bg-primary text-on-primary font-bold text-xs sm:text-sm transition disabled:opacity-40 disabled:cursor-not-allowed hover:brightness-110 active:scale-95 cursor-pointer shadow-sm flex items-center justify-center gap-1"
        >
          <span>Send</span>
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M14 5l7 7m0 0l-7 7m7-7H3" />
          </svg>
        </button>
      </form>
    </div>
  </footer>
</div>
