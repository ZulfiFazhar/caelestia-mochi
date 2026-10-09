#!/usr/bin/env bash
set -e

# ==============================================================================
# Caelestia Mochi Agent Installer
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}:: Installing Caelestia Mochi Agent...${RESET}"

TARGET_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/ZulfiFazhar/caelestia-mochi/main}"

# 1. Check prerequisites
if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}Error: python3 is required but not installed.${RESET}"
    exit 1
fi

if [ ! -d "$TARGET_CONFIG" ]; then
    echo -e "${RED}Error: Caelestia Shell config not found at $TARGET_CONFIG.${RESET}"
    echo "Please ensure Caelestia Shell is installed."
    exit 1
fi

mkdir -p "$TARGET_CONFIG/modules/dashboard/agent"
mkdir -p "$TARGET_CONFIG/utils/scripts"

# 2. Install files (local copy or remote curl download)
FILES=(
    "modules/dashboard/AgentTab.qml"
    "modules/dashboard/agent/MiniMochi.qml"
    "modules/dashboard/agent/MochiBot.qml"
    "utils/scripts/agent_monitor.py"
    "utils/scripts/test_agent_monitor.py"
)

USE_SYMLINK=false
for arg in "$@"; do
    case "$arg" in
        --link|-l)
            USE_SYMLINK=true
            ;;
    esac
done

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/src/modules/dashboard/AgentTab.qml" ]; then
    if [ "$USE_SYMLINK" = true ]; then
        echo -e "${GREEN}:: Symlinking files from local repository (dev mode)...${RESET}"
        for f in "${FILES[@]}"; do
            mkdir -p "$(dirname "$TARGET_CONFIG/$f")"
            ln -sf "$SCRIPT_DIR/src/$f" "$TARGET_CONFIG/$f"
            echo "   -> Linked $f"
        done
    else
        echo -e "${GREEN}:: Copying files from local repository...${RESET}"
        for f in "${FILES[@]}"; do
            mkdir -p "$(dirname "$TARGET_CONFIG/$f")"
            cp "$SCRIPT_DIR/src/$f" "$TARGET_CONFIG/$f"
            echo "   -> Installed $f"
        done
    fi
else
    echo -e "${GREEN}:: Downloading files from GitHub...${RESET}"
    for f in "${FILES[@]}"; do
        mkdir -p "$(dirname "$TARGET_CONFIG/$f")"
        curl -fsSL "$REPO_RAW_URL/src/$f" -o "$TARGET_CONFIG/$f"
        echo "   -> Downloaded $f"
    done
fi

chmod +x "$TARGET_CONFIG/utils/scripts/agent_monitor.py"

# 3. Patch Content.qml to register Agent tab if not present
CONTENT_QML="$TARGET_CONFIG/modules/dashboard/Content.qml"
if [ -f "$CONTENT_QML" ]; then
    python3 - << EOF
import os, sys, re

path = "$CONTENT_QML"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "agentComponent" in content:
    print(":: Agent tab already registered in Content.qml.")
    sys.exit(0)

# Create backup if not exists
bak_path = path + ".bak"
if not os.path.exists(bak_path):
    with open(bak_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(":: Backup saved to " + bak_path)

tab_entry = """            {
                component: agentComponent,
                iconName: "smart_toy",
                text: Tr.tr("Agent"),
                enabled: true
            }"""

pos_tabs = content.find("];")
if pos_tabs != -1:
    prefix = content[:pos_tabs].rstrip()
    if not prefix.endswith(","):
        prefix += ",\n"
    else:
        prefix += "\n"
    content = prefix + tab_entry + "\n        " + content[pos_tabs:]

comp_entry = """            Component {
                id: agentComponent

                AgentTab {
                    screenState: root.screenState
                }
            }

"""
pos_comp = content.find("Behavior on contentX")
if pos_comp != -1:
    content = content[:pos_comp] + comp_entry + "            " + content[pos_comp:]
else:
    last_brace = content.rfind("}")
    content = content[:last_brace] + comp_entry + content[last_brace:]

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print(":: Successfully registered Agent tab in Content.qml.")
EOF
fi

# 4. Verify monitor script
echo -e "${CYAN}:: Running agent monitor diagnostics...${RESET}"
python3 "$TARGET_CONFIG/utils/scripts/test_agent_monitor.py" >/dev/null 2>&1 && \
    echo -e "${GREEN}:: Agent monitor verification passed!${RESET}" || \
    echo -e "${YELLOW}:: Warning: Test script reported non-critical warnings.${RESET}"

# 5. Reload Caelestia Shell
if command -v caelestia >/dev/null 2>&1; then
    echo -e "${CYAN}:: Reloading Caelestia Shell...${RESET}"
    killall -9 quickshell qs 2>/dev/null || true
    sleep 1
    nohup caelestia shell -d >/dev/null 2>&1 &
    sleep 1
    echo -e "${GREEN}:: Caelestia Shell reloaded successfully!${RESET}"
else
    echo -e "${YELLOW}:: Please reload Quickshell / Caelestia Shell to apply changes.${RESET}"
fi

echo -e "\n${BOLD}${GREEN}✔ Installation complete!${RESET}"
echo -e "Open your Caelestia Dashboard drawer to meet Mochi and monitor your coding agents.\n"
