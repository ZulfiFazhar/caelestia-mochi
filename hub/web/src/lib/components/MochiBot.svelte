<script lang="ts">
  import {
    type MochiBotProps,
    getEyeShape,
    getGlowColor,
    hexToRgba,
  } from '../types/agent'

  let {
    state: mochiState = 'idle',
    eyeShape,
    size = 130,
    interactive = true,
    accentColor = '#4ADE80',
    active,
    class: className = '',
  }: MochiBotProps = $props()

  let container: HTMLElement | null = $state(null)
  let lookTargetX = $state(0)
  let lookTargetY = $state(0)
  let isHovered = $state(false)
  let isBlinking = $state(false)
  let isSquished = $state(false)
  let clickCount = $state(0)

  const effectiveActive = $derived(
    active ?? (mochiState !== 'sleeping' && mochiState !== 'idle')
  )
  const glowColor = $derived(getGlowColor(mochiState, accentColor))
  const effectiveEyeShape = $derived(
    clickCount >= 3 ? 'dizzy' : (eyeShape ?? getEyeShape(mochiState, clickCount))
  )

  const activeLookX = $derived(
    isHovered ? lookTargetX : (mochiState === 'thinking' ? 0.55 : 0)
  )
  const activeLookY = $derived(
    isHovered ? lookTargetY : (mochiState === 'thinking' ? -0.45 : 0)
  )

  const bodyScaleX = $derived(
    isSquished ? 1.15 : (mochiState === 'sleeping' ? 1.03 : 1.0)
  )
  const bodyScaleY = $derived(
    isSquished ? 0.85 : (mochiState === 'sleeping' ? 0.96 : 1.0)
  )
  const rotation = $derived(mochiState === 'question' ? 6 : 0)

  // Blinking cycle: random 2.8s-4.8s, lasts 130ms. Suppressed when sleeping or closed eyes.
  $effect(() => {
    if (mochiState === 'sleeping' || effectiveEyeShape === 'closed') {
      isBlinking = false
      return
    }

    let blinkTimeout: ReturnType<typeof setTimeout>
    let resetTimeout: ReturnType<typeof setTimeout>
    let cancelled = false

    const scheduleBlink = () => {
      const delay = 2800 + Math.random() * 2000
      blinkTimeout = setTimeout(() => {
        if (cancelled) return
        isBlinking = true
        resetTimeout = setTimeout(() => {
          if (cancelled) return
          isBlinking = false
          scheduleBlink()
        }, 130)
      }, delay)
    }

    scheduleBlink()

    return () => {
      cancelled = true
      clearTimeout(blinkTimeout)
      clearTimeout(resetTimeout)
      isBlinking = false
    }
  })

  // Pointer and Tap interactions
  let clickResetTimer: ReturnType<typeof setTimeout> | undefined
  let squishResetTimer: ReturnType<typeof setTimeout> | undefined
  let lastTapTimestamp = 0

  function handleTap() {
    if (!interactive) return
    const now = Date.now()
    if (now - lastTapTimestamp < 60) return
    lastTapTimestamp = now

    clickCount++
    clearTimeout(clickResetTimer)
    clickResetTimer = setTimeout(() => {
      clickCount = 0
    }, 1500)

    isSquished = true
    clearTimeout(squishResetTimer)
    squishResetTimer = setTimeout(() => {
      isSquished = false
    }, 220)
  }

  function updateGaze(clientX: number, clientY: number) {
    if (!container || !interactive) return
    const rect = container.getBoundingClientRect()
    const centerX = rect.left + rect.width / 2
    const centerY = rect.top + rect.height / 2
    const halfW = rect.width / 2 || 1
    const halfH = rect.height / 2 || 1
    lookTargetX = Math.max(-1.0, Math.min(1.0, (clientX - centerX) / halfW))
    lookTargetY = Math.max(-1.0, Math.min(1.0, (clientY - centerY) / halfH))
    isHovered = true
  }

  function resetGaze() {
    isHovered = false
    lookTargetX = 0
    lookTargetY = 0
  }

  // Mobile passive touch events (does not lock page scrolling)
  $effect(() => {
    const el = container
    if (!el || !interactive) return

    const onTouchStart = (e: TouchEvent) => {
      if (e.touches.length > 0) {
        updateGaze(e.touches[0].clientX, e.touches[0].clientY)
        handleTap()
      }
    }

    const onTouchMove = (e: TouchEvent) => {
      if (e.touches.length > 0) {
        updateGaze(e.touches[0].clientX, e.touches[0].clientY)
      }
    }

    const onTouchEnd = () => {
      resetGaze()
    }

    el.addEventListener('touchstart', onTouchStart, { passive: true })
    el.addEventListener('touchmove', onTouchMove, { passive: true })
    el.addEventListener('touchend', onTouchEnd, { passive: true })
    el.addEventListener('touchcancel', onTouchEnd, { passive: true })

    return () => {
      el.removeEventListener('touchstart', onTouchStart)
      el.removeEventListener('touchmove', onTouchMove)
      el.removeEventListener('touchend', onTouchEnd)
      el.removeEventListener('touchcancel', onTouchEnd)
      clearTimeout(clickResetTimer)
      clearTimeout(squishResetTimer)
    }
  })
</script>

{#snippet stage()}
  <div
    class="mochi-stage relative w-[130px] h-[130px] flex items-center justify-center shrink-0 pointer-events-none"
    style="transform: scale({size / 130}); transform-origin: center;"
  >
    <!-- 1. Aura glow behind body -->
    <div
      class="mochi-aura absolute rounded-full transition-colors duration-400 {effectiveActive && mochiState !== 'sleeping' ? 'animate-mochi-aura' : ''}"
      style="
        width: 104px;
        height: 104px;
        background-color: {effectiveActive ? hexToRgba(glowColor, 0.32) : 'rgba(228, 225, 231, 0.08)'};
      "
    ></div>

    <!-- 2. Body wrapper (handles bounce & shiver animations) -->
    <div
      class="mochi-body-wrapper relative {mochiState === 'approval' ? 'animate-mochi-bounce' : ''} {mochiState === 'error' ? 'animate-mochi-shiver' : ''}"
    >
      <!-- Head Badges -->
      {#if effectiveActive && (mochiState === 'working' || mochiState === 'idle')}
        <!-- Active 3 dots badge -->
        <div
          class="absolute -top-2 left-1/2 -translate-x-1/2 flex items-center gap-[3px] z-20 pointer-events-none"
        >
          <div
            class="w-[5px] h-[5px] rounded-full animate-mochi-dot"
            style="background-color: {glowColor}; animation-delay: 0ms;"
          ></div>
          <div
            class="w-[5px] h-[5px] rounded-full animate-mochi-dot"
            style="background-color: {glowColor}; animation-delay: 180ms;"
          ></div>
          <div
            class="w-[5px] h-[5px] rounded-full animate-mochi-dot"
            style="background-color: {glowColor}; animation-delay: 360ms;"
          ></div>
        </div>
      {:else if mochiState === 'approval'}
        <!-- Bang '!' badge -->
        <div
          class="absolute -top-[10px] left-1/2 -translate-x-1/2 w-[14px] h-[14px] rounded-full bg-[#F5A524] flex items-center justify-center z-20 pointer-events-none shadow-sm"
        >
          <span class="text-[10px] font-bold text-white leading-none">!</span>
        </div>
      {:else if mochiState === 'question'}
        <!-- Question '?' badge -->
        <div
          class="absolute -top-[10px] left-1/2 -translate-x-1/2 w-[14px] h-[14px] rounded-full bg-[#22D3EE] flex items-center justify-center z-20 pointer-events-none shadow-sm"
        >
          <span class="text-[10px] font-bold text-white leading-none">?</span>
        </div>
      {:else if mochiState === 'finished' || mochiState === 'done'}
        <!-- Sparkle badge dot -->
        <div
          class="absolute -top-[7px] left-1/2 -translate-x-1/2 w-[8px] h-[8px] rounded-full bg-[#34D399] z-20 pointer-events-none shadow-sm"
        ></div>
      {/if}

      <!-- Body squircle -->
      <div
        class="mochi-body relative overflow-hidden"
        style="
          width: 92px;
          height: 82px;
          border-radius: 38px;
          transform: scale({bodyScaleX}, {bodyScaleY}) rotate({rotation}deg);
          transform-origin: center;
          transition: transform 180ms cubic-bezier(0.34, 1.56, 0.64, 1), border-color 300ms ease;
          background: linear-gradient(180deg, {effectiveActive ? '#FFFFFF' : '#F7F5F0'} 0%, {effectiveActive ? '#E2E8F0' : '#D8D0C5'} 100%);
          border: {effectiveActive ? 2 : 1}px solid {effectiveActive ? glowColor : 'rgba(144, 144, 154, 0.2)'};
        "
      >
        <!-- Top shine highlight -->
        <div
          class="absolute top-1 left-1/2 -translate-x-1/2 pointer-events-none"
          style="
            width: 60px;
            height: 14px;
            border-radius: 7px;
            background-color: rgba(255, 255, 255, 0.45);
          "
        ></div>

        <!-- Rosy Cheeks -->
        <div
          class="absolute pointer-events-none transition-transform duration-150 ease-out"
          style="
            left: 12px;
            top: 44px;
            width: 12px;
            height: 7px;
            border-radius: 4px;
            background-color: rgba(255, 107, 139, {effectiveActive ? 0.65 : 0.35});
            transform: translate({activeLookX * 2}px, {activeLookY * 2}px);
          "
        ></div>
        <div
          class="absolute pointer-events-none transition-transform duration-150 ease-out"
          style="
            left: 68px;
            top: 44px;
            width: 12px;
            height: 7px;
            border-radius: 4px;
            background-color: rgba(255, 107, 139, {effectiveActive ? 0.65 : 0.35});
            transform: translate({activeLookX * 2}px, {activeLookY * 2}px);
          "
        ></div>

        <!-- Left Eye Slot -->
        <div
          class="absolute pointer-events-none w-[12px] h-[14px] flex items-center justify-center {mochiState === 'searching' && !isHovered ? 'animate-mochi-scan' : 'transition-transform duration-120 ease-out'}"
          style="
            left: 27px;
            top: 33px;
            transform: {mochiState === 'searching' && !isHovered ? 'none' : `translate(${activeLookX * 6}px, ${activeLookY * 5}px)`};
          "
        >
          {#if effectiveEyeShape === 'pill'}
            <!-- 1. Pill Eye -->
            <div
              class="bg-[#181412] rounded-[4px] relative transition-[height] duration-75 flex items-start justify-start"
              style="width: 8px; height: {isBlinking ? '2px' : '13px'};"
            >
              {#if !isBlinking}
                <div
                  class="absolute bg-white rounded-full"
                  style="left: 2px; top: 2px; width: 3px; height: 3px;"
                ></div>
              {/if}
            </div>
          {:else if effectiveEyeShape === 'wide'}
            <!-- 2. Wide Eye -->
            <div
              class="bg-[#181412] rounded-[5px] relative transition-[height] duration-75 flex items-start justify-start"
              style="width: 10px; height: {isBlinking ? '2px' : '15px'};"
            >
              {#if !isBlinking}
                <div
                  class="absolute bg-white rounded-full"
                  style="left: 2px; top: 2px; width: 4px; height: 4px;"
                ></div>
              {/if}
            </div>
          {:else if effectiveEyeShape === 'flat'}
            <!-- 3. Flat Eye -->
            <div
              class="bg-[#181412] rounded-[1.5px]"
              style="width: 12px; height: 3px;"
            ></div>
          {:else if effectiveEyeShape === 'happy'}
            <!-- 4. Happy Eye Arc (smile arc ^) -->
            <svg
              class="w-[11px] h-[7px] overflow-visible"
              viewBox="0 0 11 7"
              fill="none"
            >
              <path
                d="M 0.5 5.5 A 5.5 5.5 0 0 1 10.5 5.5"
                stroke="#181412"
                stroke-width="2.4"
                stroke-linecap="round"
              />
            </svg>
          {:else if effectiveEyeShape === 'closed'}
            <!-- 5. Closed Eye (sleeping arc v) -->
            <svg
              class="w-[11px] h-[7px] overflow-visible"
              viewBox="0 0 11 7"
              fill="none"
            >
              <path
                d="M 0.5 1.5 A 5.5 5.5 0 0 0 10.5 1.5"
                stroke="#64748B"
                stroke-width="2.2"
                stroke-linecap="round"
              />
            </svg>
          {:else if effectiveEyeShape === 'dizzy'}
            <!-- 6. Dizzy Eye (×) -->
            <span
              class="text-[#181412] font-bold select-none leading-none"
              style="font-size: 15px;"
            >
              ×
            </span>
          {/if}
        </div>

        <!-- Right Eye Slot -->
        <div
          class="absolute pointer-events-none w-[12px] h-[14px] flex items-center justify-center {mochiState === 'searching' && !isHovered ? 'animate-mochi-scan' : 'transition-transform duration-120 ease-out'}"
          style="
            left: 55px;
            top: 33px;
            transform: {mochiState === 'searching' && !isHovered ? 'none' : `translate(${activeLookX * 6}px, ${activeLookY * 5}px)`};
          "
        >
          {#if effectiveEyeShape === 'pill'}
            <!-- 1. Pill Eye -->
            <div
              class="bg-[#181412] rounded-[4px] relative transition-[height] duration-75 flex items-start justify-start"
              style="width: 8px; height: {isBlinking ? '2px' : '13px'};"
            >
              {#if !isBlinking}
                <div
                  class="absolute bg-white rounded-full"
                  style="left: 2px; top: 2px; width: 3px; height: 3px;"
                ></div>
              {/if}
            </div>
          {:else if effectiveEyeShape === 'wide'}
            <!-- 2. Wide Eye -->
            <div
              class="bg-[#181412] rounded-[5px] relative transition-[height] duration-75 flex items-start justify-start"
              style="width: 10px; height: {isBlinking ? '2px' : '15px'};"
            >
              {#if !isBlinking}
                <div
                  class="absolute bg-white rounded-full"
                  style="left: 2px; top: 2px; width: 4px; height: 4px;"
                ></div>
              {/if}
            </div>
          {:else if effectiveEyeShape === 'flat'}
            <!-- 3. Flat Eye -->
            <div
              class="bg-[#181412] rounded-[1.5px]"
              style="width: 12px; height: 3px;"
            ></div>
          {:else if effectiveEyeShape === 'happy'}
            <!-- 4. Happy Eye Arc (smile arc ^) -->
            <svg
              class="w-[11px] h-[7px] overflow-visible"
              viewBox="0 0 11 7"
              fill="none"
            >
              <path
                d="M 0.5 5.5 A 5.5 5.5 0 0 1 10.5 5.5"
                stroke="#181412"
                stroke-width="2.4"
                stroke-linecap="round"
              />
            </svg>
          {:else if effectiveEyeShape === 'closed'}
            <!-- 5. Closed Eye (sleeping arc v) -->
            <svg
              class="w-[11px] h-[7px] overflow-visible"
              viewBox="0 0 11 7"
              fill="none"
            >
              <path
                d="M 0.5 1.5 A 5.5 5.5 0 0 0 10.5 1.5"
                stroke="#64748B"
                stroke-width="2.2"
                stroke-linecap="round"
              />
            </svg>
          {:else if effectiveEyeShape === 'dizzy'}
            <!-- 6. Dizzy Eye (×) -->
            <span
              class="text-[#181412] font-bold select-none leading-none"
              style="font-size: 15px;"
            >
              ×
            </span>
          {/if}
        </div>
      </div>
    </div>
  </div>
{/snippet}

{#if interactive}
  <button
    bind:this={container}
    type="button"
    aria-label="Mochi Companion ({mochiState})"
    class="mochi-bot-root relative select-none inline-flex items-center justify-center p-0 border-0 bg-transparent cursor-pointer {className}"
    style="
      width: {size}px;
      height: {size}px;
      touch-action: pan-y;
    "
    onpointerenter={(e) => {
      if (e.pointerType === 'mouse') updateGaze(e.clientX, e.clientY)
    }}
    onpointermove={(e) => {
      if (e.pointerType === 'mouse') updateGaze(e.clientX, e.clientY)
    }}
    onpointerleave={(e) => {
      if (e.pointerType === 'mouse') resetGaze()
    }}
    onclick={handleTap}
  >
    {@render stage()}
  </button>
{:else}
  <div
    bind:this={container}
    role="img"
    aria-label="Mochi Companion ({mochiState})"
    class="mochi-bot-root relative select-none inline-flex items-center justify-center cursor-default {className}"
    style="
      width: {size}px;
      height: {size}px;
    "
  >
    {@render stage()}
  </div>
{/if}

<style>
  @keyframes mochi-aura-pulse {
    0%,
    100% {
      transform: scale(0.96);
    }
    50% {
      transform: scale(1.14);
    }
  }

  .animate-mochi-aura {
    animation: mochi-aura-pulse 3.2s ease-in-out infinite;
  }

  @keyframes mochi-bounce {
    0% {
      transform: translateY(0);
      animation-timing-function: cubic-bezier(0, 0, 0.2, 1);
    }
    26% {
      transform: translateY(-6px);
      animation-timing-function: cubic-bezier(0.4, 0, 1, 1);
    }
    60% {
      transform: translateY(0);
    }
    100% {
      transform: translateY(0);
    }
  }

  .animate-mochi-bounce {
    animation: mochi-bounce 760ms infinite;
  }

  @keyframes mochi-shiver {
    0%,
    100% {
      transform: translateX(0);
    }
    8% {
      transform: translateX(-2px);
    }
    16% {
      transform: translateX(2px);
    }
    24% {
      transform: translateX(0);
    }
  }

  .animate-mochi-shiver {
    animation: mochi-shiver 780ms infinite;
  }

  @keyframes mochi-scan {
    0% {
      transform: translateX(-4.8px);
    }
    100% {
      transform: translateX(4.8px);
    }
  }

  .animate-mochi-scan {
    animation: mochi-scan 550ms ease-in-out infinite alternate;
  }

  @keyframes mochi-dot-bounce {
    0%,
    100% {
      transform: translateY(0);
    }
    30% {
      transform: translateY(-4px);
    }
    60% {
      transform: translateY(0);
    }
  }

  .animate-mochi-dot {
    animation: mochi-dot-bounce 960ms infinite;
  }
</style>
