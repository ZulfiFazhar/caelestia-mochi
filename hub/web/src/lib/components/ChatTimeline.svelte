<script lang="ts">
  import type { AgentInfo, TimelineEntry } from '../types/agent'
  import { statusToMochiState } from '../types/agent'
  import MiniMochi from './MiniMochi.svelte'

  interface Props {
    entries?: TimelineEntry[]
    activeAgent?: AgentInfo | null
    onClear?: () => void
    class?: string
  }

  let {
    entries = [],
    activeAgent = null,
    onClear,
    class: className = '',
  }: Props = $props()

  let scrollContainer: HTMLDivElement | null = $state(null)
  let copiedId = $state<string | null>(null)

  // Auto-scroll to bottom on new timeline entries
  $effect(() => {
    // track entries length
    const _len = entries.length
    if (scrollContainer) {
      scrollContainer.scrollTop = scrollContainer.scrollHeight
    }
  })

  function formatTime(timestamp: number): string {
    const d = new Date(timestamp)
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
  }

  async function copyToClipboard(text: string, id: string) {
    try {
      await navigator.clipboard.writeText(text)
      copiedId = id
      setTimeout(() => {
        if (copiedId === id) copiedId = null
      }, 1500)
    } catch {
      // fallback
    }
  }
</script>

<div class="chat-timeline flex flex-col h-full rounded-2xl bg-surface-container border border-outline-variant/40 overflow-hidden shadow-sm {className}">
  <!-- Timeline Toolbar -->
  <div class="flex items-center justify-between px-4 py-2.5 bg-surface-container-high border-b border-outline-variant/40 shrink-0">
    <div class="flex items-center gap-2">
      <div class="w-2.5 h-2.5 rounded-full bg-success animate-pulse"></div>
      <span class="text-xs font-semibold text-on-surface">
        {activeAgent ? activeAgent.name : 'Terminal Transcript'}
      </span>
      {#if activeAgent}
        <span class="rounded-full bg-surface-container px-2 py-0.5 text-[10px] font-mono text-on-surface-variant">
          {activeAgent.status || 'idle'}
        </span>
      {/if}
    </div>

    <div class="flex items-center gap-1">
      {#if onClear && entries.length > 0}
        <button
          type="button"
          onclick={onClear}
          title="Clear transcript"
          class="rounded-lg p-1.5 text-on-surface-variant hover:text-on-surface hover:bg-surface-container text-xs cursor-pointer transition"
        >
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      {/if}
    </div>
  </div>

  <!-- Scrollable Messages Container -->
  <div
    bind:this={scrollContainer}
    class="flex-1 overflow-y-auto p-4 space-y-3 min-h-[200px]"
  >
    {#if entries.length === 0}
      <div class="h-full flex flex-col items-center justify-center text-center p-6 text-on-surface-variant/70">
        <MiniMochi state={activeAgent ? statusToMochiState(activeAgent.status) : 'idle'} size={36} class="mb-2 opacity-60" />
        <p class="text-xs font-medium">Session transcript is empty</p>
        <p class="text-[11px] opacity-75 mt-0.5">Dispatched commands and agent events will stream here live</p>
      </div>
    {:else}
      {#each entries as entry (entry.id)}
        {#if entry.type === 'system'}
          <!-- System Status Pill -->
          <div class="flex justify-center my-1">
            <span class="inline-flex items-center gap-1.5 rounded-full bg-surface-container-high/60 px-3 py-0.5 text-[10px] text-on-surface-variant border border-outline-variant/30">
              <span class="font-mono opacity-60">{formatTime(entry.timestamp)}</span>
              <span>{entry.text}</span>
            </span>
          </div>

        {:else if entry.type === 'user'}
          <!-- User Command / Message -->
          <div class="flex justify-end">
            <div class="max-w-[85%] rounded-2xl rounded-tr-xs bg-primary text-on-primary px-3.5 py-2 shadow-xs">
              <div class="flex items-center justify-between gap-2 mb-0.5 text-[9px] font-medium opacity-75">
                <span>You</span>
                <span>{formatTime(entry.timestamp)}</span>
              </div>
              <p class="font-mono text-xs whitespace-pre-wrap break-all">{entry.text}</p>
            </div>
          </div>

        {:else if entry.type === 'terminal'}
          <!-- Raw Terminal Output Chunk -->
          <div class="group relative rounded-xl bg-surface-container-lowest p-3 border border-outline-variant/50 font-mono text-xs">
            <div class="flex items-center justify-between mb-1.5 pb-1 border-b border-outline-variant/20 text-[10px] text-on-surface-variant">
              <span class="text-primary">{entry.sender || 'stdout'}</span>
              <div class="flex items-center gap-2">
                <span>{formatTime(entry.timestamp)}</span>
                <button
                  type="button"
                  onclick={() => copyToClipboard(entry.text, entry.id)}
                  title="Copy line"
                  class="opacity-0 group-hover:opacity-100 transition p-0.5 text-on-surface-variant hover:text-on-surface cursor-pointer"
                >
                  {#if copiedId === entry.id}
                    <span class="text-success text-[10px]">Copied</span>
                  {:else}
                    <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                    </svg>
                  {/if}
                </button>
              </div>
            </div>
            <pre class="whitespace-pre-wrap break-all text-on-surface leading-relaxed text-[11px] select-all font-mono"><code>{entry.text}</code></pre>
          </div>

        {:else if entry.type === 'approval'}
          <!-- Approval Alert Card in Stream -->
          <div class="rounded-xl bg-warning/10 border border-warning/50 p-3 text-xs">
            <div class="flex items-center justify-between text-[10px] font-semibold uppercase tracking-wider text-warning mb-1">
              <span>Security Intercept</span>
              <span>{formatTime(entry.timestamp)}</span>
            </div>
            <p class="font-mono text-on-surface break-all">{entry.text}</p>
          </div>

        {:else}
          <!-- Agent Chat Message -->
          <div class="flex items-start gap-2.5">
            <MiniMochi state={activeAgent ? statusToMochiState(activeAgent.status) : 'working'} size={24} class="mt-1" />
            <div class="max-w-[85%] rounded-2xl rounded-tl-xs bg-surface-container-high px-3.5 py-2 border border-outline-variant/40 shadow-xs">
              <div class="flex items-center justify-between gap-2 mb-0.5 text-[10px] font-semibold text-primary">
                <span>{entry.sender || 'Agent'}</span>
                <span class="font-normal text-on-surface-variant/75 text-[9px]">{formatTime(entry.timestamp)}</span>
              </div>
              <p class="text-xs text-on-surface whitespace-pre-wrap break-words">{entry.text}</p>
            </div>
          </div>
        {/if}
      {/each}
    {/if}
  </div>
</div>
