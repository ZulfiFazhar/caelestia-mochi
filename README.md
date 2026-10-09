# Caelestia Mochi Agent

Real-time coding agent dashboard monitor and animated **Coucou Mochi** companion for [Caelestia Hyprland](https://github.com/caelestia-dots/caelestia).

Built with native **Quickshell** (QML) and follows Caelestia's dynamic Material Design 3 theme system (`scheme.json`).

---

## ✨ Features

- 🍙 **Interactive Mochi Mascot:** Squishable companion mascot with cursor gaze tracking, eyelid blink cycles, and dynamic facial expressions (`pill`, `wide`, `happy arc`, `closed arc`, `flat line`, `dizzy X`).
- ⚡ **Real-Time Agent State Detection:** Instantaneous CPU tick deltas via `/proc/{pid}/stat` + direct SQLite inspection (`opencode.db`) for immediate status updates without lifetime CPU averaging lag.
  - ⚡ **Working:** Process active / running tools.
  - 🤔 **Thinking:** Model reasoning or streaming tokens.
  - 🔍 **Searching:** Code grep, glob, or web queries.
  - ⏳ **Approval:** Waiting for user confirmation or permissions.
  - ❓ **Question:** Prompt or user question active.
  - ✨ **Done:** Succeeded outcome (active for 15s).
  - 🍙 **Idle:** Agent idle and waiting for input.
  - 💤 **Sleeping:** No active agent running.
- 🛠 **Multi-Harness Discovery:** Automatic detection for 11+ coding agent harnesses:
  - OpenCode (`opencode`)
  - Claude Code (`claude`, `claude-code`)
  - Antigravity (`antigravity`, `agy`)
  - Codex (`codex`)
  - Aider (`aider`)
  - Cursor (`cursor`, `cursor-agent`)
  - Windsurf (`windsurf`)
  - Goose AI (`goose`, `goose-ai`)
  - Plandex (`plandex`)
  - Cline (`cline`)
  - Continue (`continue`)
- 🖥️ **Hyprland Terminal Focus:** Multi-instance selector per agent with one-click window focusing via native Hyprland Lua dispatchers (`hl.dsp.focus`).
- ➕ **Harness Launcher:** Plus (+) launcher sheet to spawn any installed agent harness or custom command in a new terminal window.
- 🎨 **Coucou State Badging:** Replaces generic badges with micro `MiniMochi` avatars reflecting each terminal session's real-time state.
- 🛡 **Clean & Non-destructive:** Automatic backup of `Content.qml`, idempotent installation, and clean uninstaller.

---

## ⚡ Quick Install

### Method 1: One-liner (Curl)

```bash
curl -fsSL https://raw.githubusercontent.com/ZulfiFazhar/caelestia-mochi/main/install.sh | bash
```

### Method 2: Git Clone

```bash
git clone https://github.com/ZulfiFazhar/caelestia-mochi.git
cd caelestia-mochi
./install.sh
```

---

## ⌨️ Usage

1. Open the Caelestia Dashboard drawer (default: click launcher icon or press your dashboard hotkey).
2. Switch to the **Agent** tab (smart toy icon 🤖).
3. **Interact with Mochi:** Click Mochi to squish, triple click for dizzy eyes, or move the cursor to direct Mochi's gaze.
4. **Switch Workspaces:** Click any terminal session card to focus its Hyprland window.
5. **Launch Harness:** Click the `+` button in the agent pills row to launch a detected harness or run custom CLI commands.

---

## 🗑️ Uninstall

```bash
./uninstall.sh
```

Or run directly via curl:

```bash
curl -fsSL https://raw.githubusercontent.com/ZulfiFazhar/caelestia-mochi/main/uninstall.sh | bash
```

---

## 📦 Requirements

- [Hyprland](https://hyprland.org)
- [Quickshell](https://quickshell.outfoxxed.me/) (`quickshell-git` / `qs`)
- `caelestia-shell` or Caelestia dotfiles (`~/.config/quickshell/caelestia`)
- `python3` (with standard library `sqlite3`, `json`, `subprocess`)

---

## 📄 License

[MIT](LICENSE) © 2026 Zulfi Fadilah Azhar
