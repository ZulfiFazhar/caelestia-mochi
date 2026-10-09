<script lang="ts">
  import type { ApprovalRequest } from '../types/agent'
  import MiniMochi from './MiniMochi.svelte'

  interface Props {
    approval: ApprovalRequest
    timeoutSeconds?: number
    onAllow?: (approvalId: string) => unknown | Promise<unknown>
    onDeny?: (approvalId: string, reason?: string) => unknown | Promise<unknown>
    class?: string
  }

  let {
    approval,
    timeoutSeconds = 60,
    onAllow,
    onDeny,
    class: className = '',
  }: Props = $props()

  let isSubmitting = $state(false)
  let showReasonField = $state(false)
  let denialReason = $state('')
  let timedOut = $state(false)
  let timeoutHandled = $state(false)

  // Calculate initial remaining seconds from timestamp if present
  const getInitialRemaining = () => {
    if (!approval.timestamp) return timeoutSeconds
    const tsMs = approval.timestamp > 1e11 ? approval.timestamp : approval.timestamp * 1000
    const elapsed = Math.floor((Date.now() - tsMs) / 1000)
    return Math.max(0, timeoutSeconds - elapsed)
  }

  let remaining = $state(getInitialRemaining())

  async function triggerTimeout() {
    if (timeoutHandled) return
    timeoutHandled = true
    timedOut = true
    await handleDeny('Request timed out')
  }

  // Countdown timer with clean interval teardown
  $effect(() => {
    remaining = getInitialRemaining()
    if (remaining <= 0) {
      triggerTimeout()
      return
    }

    const interval = setInterval(() => {
      if (remaining > 0) {
        remaining -= 1
        if (remaining <= 0) {
          clearInterval(interval)
          triggerTimeout()
        }
      } else {
        clearInterval(interval)
      }
    }, 1000)

    return () => clearInterval(interval)
  })

  const progressPercent = $derived(
    Math.max(0, Math.min(100, Math.round((remaining / timeoutSeconds) * 100)))
  )

  const progressColor = $derived(
    remaining <= 10
      ? 'var(--color-error, #f4505e)'
      : remaining <= 25
        ? 'var(--color-warning, #f5a524)'
        : 'var(--color-success, #4ade80)'
  )

  const commandToDisplay = $derived(
    approval.command || approval.matched_text || approval.prompt || 'Permission request'
  )

  async function handleAllow() {
    if (isSubmitting || remaining <= 0 || timedOut) return
    isSubmitting = true
    try {
      await onAllow?.(approval.approval_id)
    } finally {
      isSubmitting = false
    }
  }

  async function handleDeny(reason?: string) {
    if (isSubmitting) return
    isSubmitting = true
    try {
      await onDeny?.(approval.approval_id, reason ?? denialReason.trim())
    } finally {
      isSubmitting = false
    }
  }
</script>

<div
  role="alert"
  aria-live="assertive"
  class="approval-card relative w-full overflow-hidden rounded-2xl bg-surface-container-high border-2 border-warning/80 shadow-2xl backdrop-blur-md transition-all duration-300 {className}"
>
  <!-- Ambient glow backdrop -->
  <div
    class="pointer-events-none absolute -inset-1 opacity-20 blur-xl"
    style="background: radial-gradient(circle at 50% 0%, #f5a524 0%, transparent 70%);"
  ></div>

  <!-- Progress bar countdown indicator (Review Focus 3) -->
  <div class="relative h-1.5 w-full bg-surface-container-highest">
    <div
      class="h-full transition-all duration-1000 ease-linear"
      style="width: {progressPercent}%; background-color: {progressColor};"
    ></div>
  </div>

  <div class="relative p-4 sm:p-5 flex flex-col gap-3.5">
    <!-- Header -->
    <div class="flex items-start justify-between gap-3">
      <div class="flex items-center gap-2.5">
        <MiniMochi state="approval" size={32} />
        <div>
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-bold tracking-wide text-warning uppercase">
              Action Requires Approval
            </h2>
            {#if approval.session_id}
              <span
                class="rounded-full bg-surface-container px-2 py-0.5 text-[10px] font-mono text-on-surface-variant border border-outline-variant"
              >
                {approval.session_id}
              </span>
            {/if}
          </div>
          <p class="text-xs text-on-surface-variant">
            Security guard intercepted sensitive action
          </p>
        </div>
      </div>

      <!-- Live countdown badge -->
      <div
        class="flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-mono font-semibold"
        style="
          background-color: {remaining <= 10 ? 'rgba(244, 80, 94, 0.15)' : 'rgba(245, 165, 36, 0.15)'};
          color: {progressColor};
          border: 1px solid {progressColor};
        "
      >
        <span class="inline-block w-1.5 h-1.5 rounded-full {remaining <= 10 ? 'animate-ping' : ''}" style="background-color: {progressColor};"></span>
        <span>{remaining}s</span>
      </div>
    </div>

    <!-- Command / Prompt Preview Box -->
    <div class="rounded-xl bg-surface-container-lowest p-3 border border-outline-variant/60">
      <div class="flex items-center justify-between pb-1.5 mb-1.5 border-b border-outline-variant/30 text-[10px] font-mono uppercase tracking-wider text-on-surface-variant">
        <span>Prompt / Command</span>
        <span class="text-warning">ID: {approval.approval_id}</span>
      </div>
      <pre class="font-mono text-xs text-on-surface whitespace-pre-wrap break-all max-h-32 overflow-y-auto leading-relaxed select-all"><code>{commandToDisplay}</code></pre>
    </div>

    <!-- Optional denial reason input toggle -->
    {#if showReasonField}
      <div class="flex flex-col gap-1">
        <label for="deny-reason-{approval.approval_id}" class="text-[11px] font-medium text-on-surface-variant">
          Denial reason (optional)
        </label>
        <input
          id="deny-reason-{approval.approval_id}"
          type="text"
          placeholder="e.g., destructive command, unauthorized file"
          bind:value={denialReason}
          class="w-full rounded-lg bg-surface-container px-3 py-1.5 text-xs text-on-surface border border-outline-variant focus:border-error focus:outline-hidden"
        />
      </div>
    {/if}

    <!-- Timeout Notification Banner -->
    {#if timedOut}
      <div
        class="rounded-xl bg-error/15 border border-error/40 px-3.5 py-2.5 text-xs text-error font-medium flex items-center gap-2"
        role="alert"
      >
        <svg class="w-4 h-4 shrink-0 text-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
        <span>Request timed out and was automatically denied.</span>
      </div>
    {/if}

    <!-- Action Buttons (Review Focus 3: Green Allow, Red Deny) -->
    <div class="flex items-center gap-2.5 pt-1">
      <!-- Green Allow Button -->
      <button
        type="button"
        disabled={isSubmitting || remaining <= 0 || timedOut}
        onclick={handleAllow}
        class="flex-1 inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2.5 text-xs sm:text-sm font-bold text-black transition-all shadow-md cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed hover:brightness-110 active:scale-98"
        style="background-color: var(--color-success, #4ade80);"
      >
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
        </svg>
        <span>Allow</span>
      </button>

      <!-- Red Deny Button -->
      <button
        type="button"
        disabled={isSubmitting || timedOut}
        onclick={() => handleDeny()}
        class="flex-1 inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2.5 text-xs sm:text-sm font-bold text-white transition-all shadow-md cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed hover:brightness-110 active:scale-98"
        style="background-color: var(--color-error-container, #93000a); border: 1px solid var(--color-error, #ffb4ab);"
      >
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
        <span>Deny</span>
      </button>

      <!-- Reason toggle icon button -->
      <button
        type="button"
        title="Add reason for rejection"
        onclick={() => (showReasonField = !showReasonField)}
        class="rounded-xl p-2.5 bg-surface-container text-on-surface-variant hover:text-on-surface border border-outline-variant/60 cursor-pointer transition"
      >
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
        </svg>
      </button>
    </div>
  </div>
</div>
