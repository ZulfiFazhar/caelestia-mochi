<script lang="ts">
  import {
    type MiniMochiProps,
    getEyeShape,
    getGlowColor,
    hexToRgba,
  } from '../types/agent'

  let {
    state: mochiState = 'idle',
    eyeShape,
    size = 28,
    accentColor = '#bac3ff',
    active,
    class: className = '',
  }: MiniMochiProps = $props()

  const effectiveActive = $derived(
    active ?? (mochiState !== 'sleeping' && mochiState !== 'idle')
  )
  const glowColor = $derived(getGlowColor(mochiState, accentColor))
  const effectiveEyeShape = $derived(eyeShape ?? getEyeShape(mochiState))

  const lookX = $derived(mochiState === 'thinking' ? 1.4 : 0)
  const lookY = $derived(mochiState === 'thinking' ? -1.2 : 0)

  const width = $derived(Math.round((size * 32) / 28))
</script>

<div
  role="img"
  aria-label="Mini Mochi ({mochiState})"
  class="mini-mochi-root relative select-none inline-flex items-center justify-center shrink-0 {className}"
  style="
    width: {width}px;
    height: {size}px;
  "
>
  <div
    class="mini-stage relative w-[32px] h-[28px] flex items-center justify-center shrink-0"
    style="transform: scale({size / 28}); transform-origin: center;"
  >
    <!-- 1. Aura glow behind mini body -->
    <div
      class="mini-aura absolute rounded-full transition-colors duration-300"
      style="
        width: 28px;
        height: 24px;
        background-color: {hexToRgba(glowColor, effectiveActive ? 0.35 : 0.12)};
      "
    ></div>

    <!-- 2. Body wrapper (handles bounce & shiver animations) -->
    <div
      class="mini-body-wrapper relative {mochiState === 'approval' ? 'animate-mini-bounce' : ''} {mochiState === 'error' ? 'animate-mini-shiver' : ''}"
      style="margin-top: 1px;"
    >
      <!-- Head Badges -->
      {#if mochiState === 'working'}
        <!-- Animated bouncing dots -->
        <div
          class="absolute -top-[5px] left-1/2 -translate-x-1/2 flex items-center gap-[2px] z-20 pointer-events-none"
        >
          <div
            class="w-[2.5px] h-[2.5px] rounded-full animate-mini-dot"
            style="background-color: {glowColor}; animation-delay: 0ms;"
          ></div>
          <div
            class="w-[2.5px] h-[2.5px] rounded-full animate-mini-dot"
            style="background-color: {glowColor}; animation-delay: 120ms;"
          ></div>
          <div
            class="w-[2.5px] h-[2.5px] rounded-full animate-mini-dot"
            style="background-color: {glowColor}; animation-delay: 240ms;"
          ></div>
        </div>
      {:else if mochiState === 'approval'}
        <!-- Bang '!' badge -->
        <div
          class="absolute -top-[6px] left-1/2 -translate-x-1/2 w-[7px] h-[7px] rounded-full bg-[#F5A524] flex items-center justify-center z-20 pointer-events-none shadow-xs"
        >
          <span class="text-[6px] font-bold text-white leading-none">!</span>
        </div>
      {:else if mochiState === 'question'}
        <!-- Question '?' badge -->
        <div
          class="absolute -top-[6px] left-1/2 -translate-x-1/2 w-[7px] h-[7px] rounded-full bg-[#22D3EE] flex items-center justify-center z-20 pointer-events-none shadow-xs"
        >
          <span class="text-[6px] font-bold text-white leading-none">?</span>
        </div>
      {:else if mochiState === 'finished' || mochiState === 'done'}
        <!-- Sparkle dot -->
        <div
          class="absolute -top-[4px] left-1/2 -translate-x-1/2 w-[4px] h-[4px] rounded-full bg-[#34D399] z-20 pointer-events-none shadow-xs"
        ></div>
      {/if}

      <!-- Mini Mochi Body -->
      <div
        class="mini-body relative overflow-hidden"
        style="
          width: 26px;
          height: 22px;
          border-radius: 10px;
          background: linear-gradient(180deg, {effectiveActive ? '#FFFFFF' : '#F7F5F0'} 0%, {effectiveActive ? '#E2E8F0' : '#D8D0C5'} 100%);
          border: 1px solid {effectiveActive ? glowColor : 'rgba(144, 144, 154, 0.25)'};
          transition: border-color 300ms ease;
        "
      >
        <!-- Top shine highlight -->
        <div
          class="absolute top-[2px] left-1/2 -translate-x-1/2 pointer-events-none"
          style="
            width: 15.6px;
            height: 4px;
            border-radius: 2px;
            background-color: rgba(255, 255, 255, 0.5);
          "
        ></div>

        <!-- Rosy Cheeks -->
        <div
          class="absolute pointer-events-none"
          style="
            left: 3px;
            top: 11px;
            width: 3.5px;
            height: 2px;
            border-radius: 1px;
            background-color: rgba(255, 107, 139, {effectiveActive ? 0.65 : 0.3});
          "
        ></div>
        <div
          class="absolute pointer-events-none"
          style="
            left: 19.5px;
            top: 11px;
            width: 3.5px;
            height: 2px;
            border-radius: 1px;
            background-color: rgba(255, 107, 139, {effectiveActive ? 0.65 : 0.3});
          "
        ></div>

        <!-- Left Eye Slot -->
        <div
          class="absolute pointer-events-none w-[5px] h-[6px] flex items-center justify-center {mochiState === 'searching' ? 'animate-mini-scan' : ''}"
          style="
            left: 7px;
            top: 8px;
            transform: {mochiState === 'searching' ? 'none' : `translate(${lookX}px, ${lookY}px)`};
          "
        >
          {#if effectiveEyeShape === 'pill'}
            <!-- 1. Pill Eye -->
            <div
              class="bg-[#181412] relative flex items-start justify-start"
              style="width: 2.6px; height: 5.2px; border-radius: 1.3px;"
            >
              <div
                class="absolute bg-white rounded-full"
                style="left: 0.5px; top: 0.6px; width: 1.2px; height: 1.2px;"
              ></div>
            </div>
          {:else if effectiveEyeShape === 'wide'}
            <!-- 2. Wide Eye -->
            <div
              class="bg-[#181412] relative flex items-start justify-start"
              style="width: 3.8px; height: 5.8px; border-radius: 1.9px;"
            >
              <div
                class="absolute bg-white rounded-full"
                style="left: 0.6px; top: 0.6px; width: 1.6px; height: 1.6px;"
              ></div>
            </div>
          {:else if effectiveEyeShape === 'flat'}
            <!-- 3. Flat Eye -->
            <div
              class="bg-[#181412]"
              style="width: 5px; height: 1.8px; border-radius: 0.9px;"
            ></div>
          {:else if effectiveEyeShape === 'happy'}
            <!-- 4. Happy Eye Arc (smile arc ^) -->
            <svg
              class="w-[5px] h-[3px] overflow-visible"
              viewBox="0 0 5 3"
              fill="none"
            >
              <path
                d="M 0.5 2.5 A 2.2 2.2 0 0 1 4.5 2.5"
                stroke="#181412"
                stroke-width="1.4"
                stroke-linecap="round"
              />
            </svg>
          {:else if effectiveEyeShape === 'closed'}
            <!-- 5. Closed Eye (sleeping arc v) -->
            <svg
              class="w-[5px] h-[3px] overflow-visible"
              viewBox="0 0 5 3"
              fill="none"
            >
              <path
                d="M 0.5 0.8 A 2.2 2.2 0 0 0 4.5 0.8"
                stroke="#64748B"
                stroke-width="1.4"
                stroke-linecap="round"
              />
            </svg>
          {:else if effectiveEyeShape === 'dizzy'}
            <!-- 6. Dizzy Eye (×) -->
            <span
              class="text-[#181412] font-bold select-none leading-none"
              style="font-size: 8px;"
            >
              ×
            </span>
          {/if}
        </div>

        <!-- Right Eye Slot -->
        <div
          class="absolute pointer-events-none w-[5px] h-[6px] flex items-center justify-center {mochiState === 'searching' ? 'animate-mini-scan' : ''}"
          style="
            left: 14px;
            top: 8px;
            transform: {mochiState === 'searching' ? 'none' : `translate(${lookX}px, ${lookY}px)`};
          "
        >
          {#if effectiveEyeShape === 'pill'}
            <!-- 1. Pill Eye -->
            <div
              class="bg-[#181412] relative flex items-start justify-start"
              style="width: 2.6px; height: 5.2px; border-radius: 1.3px;"
            >
              <div
                class="absolute bg-white rounded-full"
                style="left: 0.5px; top: 0.6px; width: 1.2px; height: 1.2px;"
              ></div>
            </div>
          {:else if effectiveEyeShape === 'wide'}
            <!-- 2. Wide Eye -->
            <div
              class="bg-[#181412] relative flex items-start justify-start"
              style="width: 3.8px; height: 5.8px; border-radius: 1.9px;"
            >
              <div
                class="absolute bg-white rounded-full"
                style="left: 0.6px; top: 0.6px; width: 1.6px; height: 1.6px;"
              ></div>
            </div>
          {:else if effectiveEyeShape === 'flat'}
            <!-- 3. Flat Eye -->
            <div
              class="bg-[#181412]"
              style="width: 5px; height: 1.8px; border-radius: 0.9px;"
            ></div>
          {:else if effectiveEyeShape === 'happy'}
            <!-- 4. Happy Eye Arc (smile arc ^) -->
            <svg
              class="w-[5px] h-[3px] overflow-visible"
              viewBox="0 0 5 3"
              fill="none"
            >
              <path
                d="M 0.5 2.5 A 2.2 2.2 0 0 1 4.5 2.5"
                stroke="#181412"
                stroke-width="1.4"
                stroke-linecap="round"
              />
            </svg>
          {:else if effectiveEyeShape === 'closed'}
            <!-- 5. Closed Eye (sleeping arc v) -->
            <svg
              class="w-[5px] h-[3px] overflow-visible"
              viewBox="0 0 5 3"
              fill="none"
            >
              <path
                d="M 0.5 0.8 A 2.2 2.2 0 0 0 4.5 0.8"
                stroke="#64748B"
                stroke-width="1.4"
                stroke-linecap="round"
              />
            </svg>
          {:else if effectiveEyeShape === 'dizzy'}
            <!-- 6. Dizzy Eye (×) -->
            <span
              class="text-[#181412] font-bold select-none leading-none"
              style="font-size: 8px;"
            >
              ×
            </span>
          {/if}
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  @keyframes mini-bounce {
    0% {
      transform: translateY(0);
      animation-timing-function: cubic-bezier(0, 0, 0.2, 1);
    }
    30% {
      transform: translateY(-2px);
      animation-timing-function: cubic-bezier(0.4, 0, 1, 1);
    }
    60% {
      transform: translateY(0);
    }
    100% {
      transform: translateY(0);
    }
  }

  .animate-mini-bounce {
    animation: mini-bounce 600ms infinite;
  }

  @keyframes mini-shiver {
    0%,
    100% {
      transform: translateX(0);
    }
    10% {
      transform: translateX(-1px);
    }
    20% {
      transform: translateX(1px);
    }
    30% {
      transform: translateX(0);
    }
  }

  .animate-mini-shiver {
    animation: mini-shiver 680ms infinite;
  }

  @keyframes mini-scan {
    0% {
      transform: translateX(-1.6px);
    }
    100% {
      transform: translateX(1.6px);
    }
  }

  .animate-mini-scan {
    animation: mini-scan 450ms ease-in-out infinite alternate;
  }

  @keyframes mini-dot-bounce {
    0%,
    100% {
      transform: translateY(0);
    }
    35% {
      transform: translateY(-2px);
    }
    70% {
      transform: translateY(0);
    }
  }

  .animate-mini-dot {
    animation: mini-dot-bounce 680ms infinite;
  }
</style>
