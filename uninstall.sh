#!/usr/bin/env bash
set -e

# ==============================================================================
# Caelestia Mochi Agent Uninstaller
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}:: Uninstalling Caelestia Mochi Agent...${RESET}"

TARGET_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"

if [ ! -d "$TARGET_CONFIG" ]; then
    echo -e "${YELLOW}Warning: $TARGET_CONFIG not found. Nothing to remove.${RESET}"
    exit 0
fi

# 1. Restore or clean Content.qml
CONTENT_QML="$TARGET_CONFIG/modules/dashboard/Content.qml"
if [ -f "$CONTENT_QML" ]; then
    if [ -f "$CONTENT_QML.bak" ]; then
        echo -e "${GREEN}:: Restoring original Content.qml from backup...${RESET}"
        cp "$CONTENT_QML.bak" "$CONTENT_QML"
        rm -f "$CONTENT_QML.bak"
    else
        echo -e "${CYAN}:: Removing Agent tab registration from Content.qml...${RESET}"
        python3 - << EOF
import re

path = "$CONTENT_QML"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# Remove agentComponent from dashboardTabs
content = re.sub(r'\s*\{\s*component:\s*agentComponent,[^}]+\},?', '', content)
# Remove agentComponent Component block
content = re.sub(r'\s*Component\s*\{\s*id:\s*agentComponent[\s\S]*?AgentTab[\s\S]*?\}\s*\}', '', content)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
EOF
    fi
fi

# 2. Remove installed files
echo -e "${CYAN}:: Removing installed agent modules and scripts...${RESET}"
rm -f "$TARGET_CONFIG/modules/dashboard/AgentTab.qml"
rm -f "$TARGET_CONFIG/modules/dashboard/agent/MiniMochi.qml"
rm -f "$TARGET_CONFIG/modules/dashboard/agent/MochiBot.qml"
rm -f "$TARGET_CONFIG/utils/scripts/agent_monitor.py"
rm -f "$TARGET_CONFIG/utils/scripts/test_agent_monitor.py"
rm -f "/tmp/caelestia_agent_ticks.json"

# Remove directory if empty
rmdir "$TARGET_CONFIG/modules/dashboard/agent" 2>/dev/null || true

# 3. Reload Caelestia Shell
if command -v caelestia >/dev/null 2>&1; then
    echo -e "${CYAN}:: Reloading Caelestia Shell...${RESET}"
    killall -9 quickshell qs 2>/dev/null || true
    sleep 1
    nohup caelestia shell -d >/dev/null 2>&1 &
    sleep 1
    echo -e "${GREEN}:: Caelestia Shell reloaded!${RESET}"
fi

echo -e "\n${BOLD}${GREEN}✔ Uninstallation complete.${RESET}\n"
