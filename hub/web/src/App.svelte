<script lang="ts">
  let count = $state(0)
  let doubled = $derived(count * 2)

  $effect(() => {
    // ponytail: initial state logger; upgrade path: connect to daemon event stream in Task 6
    console.debug('Mochi Hub initialized, count:', count)
  })
</script>

<main class="min-h-screen bg-surface text-on-surface p-6 flex flex-col items-center justify-center">
  <div class="max-w-md w-full bg-surface-container rounded-2xl p-6 border border-outline-variant shadow-lg text-center space-y-4">
    <h1 class="text-2xl font-bold text-primary">Mochi Hub</h1>
    <p class="text-sm text-on-surface-variant">Svelte 5 + Bun + Tailwind CSS</p>
    <div class="flex items-center justify-center gap-3">
      <button
        type="button"
        class="px-4 py-2 rounded-xl bg-primary text-on-primary font-medium transition hover:opacity-90 active:scale-95 cursor-pointer"
        onclick={() => count++}
      >
        Count: {count}
      </button>
      <span class="text-xs text-on-surface-variant">Doubled: {doubled}</span>
    </div>
  </div>
</main>
