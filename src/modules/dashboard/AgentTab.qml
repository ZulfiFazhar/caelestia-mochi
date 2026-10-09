pragma ComponentBehavior: Bound

import "agent"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property ScreenState screenState

    implicitWidth: Tokens.sizes.dashboard.mediaTabWidth
    implicitHeight: layout.implicitHeight

    // ponytail: Dynamic agent detection; upgrade path: dynamic hook events over unix socket
    property var agents: []
    property var installedHarnesses: []
    property bool showAddSheet: false

    property int selectedIndex: 0
    readonly property var currentAgent: (root.agents && root.agents.length > root.selectedIndex)
        ? root.agents[root.selectedIndex]
        : (root.agents && root.agents.length > 0 ? root.agents[0] : null)
    readonly property int activeCount: {
        let count = 0;
        if (root.agents) {
            for (let i = 0; i < root.agents.length; i++) {
                if (root.agents[i].running)
                    count++;
            }
        }
        return count;
    }

    Process {
        id: proc

        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/caelestia/utils/scripts/agent_monitor.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    if (parsed && Array.isArray(parsed.agents)) {
                        root.agents = parsed.agents;
                        root.installedHarnesses = parsed.installed_harnesses || [];
                        if (root.selectedIndex >= root.agents.length) {
                            root.selectedIndex = Math.max(0, root.agents.length - 1);
                        }
                    } else if (Array.isArray(parsed)) {
                        root.agents = parsed;
                    }
                } catch (e) {
                    console.warn("Failed to parse agent data: " + e);
                }
            }
        }
    }

    function jumpToWindow(window_address, workspace_id) {
        root.screenState.dashboard = false;
        if (window_address) {
            if (Hypr.usingLua) {
                if (workspace_id)
                    Hypr.dispatch(`hl.dsp.focus({ workspace = "${workspace_id}" })`);
                Hypr.dispatch(`hl.dsp.focus({ window = "address:${window_address}" })`);
            } else {
                if (workspace_id)
                    Hypr.dispatch(`workspace ${workspace_id}`);
                Hypr.dispatch(`focuswindow address:${window_address}`);
            }
        }
    }

    function jumpToAgent(agent) {
        if (!agent)
            return;
        if (agent.window_address) {
            jumpToWindow(agent.window_address, agent.workspace_id);
        } else {
            root.screenState.dashboard = false;
            Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "sh", "-c", `${agent.id}; exec ${Quickshell.env("SHELL") || "bash"}`]);
        }
    }

    Timer {
        id: pollTimer
        interval: 2500
        running: true
        repeat: true
        onTriggered: {
            if (!proc.running) {
                proc.running = true;
            }
        }
    }

    Component.onCompleted: proc.running = true

    RowLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.large

        // ── SISI KIRI: COMPANION CARD (MOCHI MASCOT) ───────────────────────────
        StyledRect {
            Layout.preferredWidth: 230
            Layout.fillHeight: true
            Layout.minimumHeight: rightColumn.implicitHeight

            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainer

            border.color: root.activeCount > 0
                ? Qt.alpha(root.currentAgent?.color ?? Colours.palette.m3primary, 0.45)
                : "transparent"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                Item { Layout.fillHeight: true }

                MochiBot {
                    Layout.alignment: Qt.AlignHCenter
                    active: root.activeCount > 0
                    state: root.currentAgent?.mochi?.state ?? (root.activeCount > 0 ? "working" : "idle")
                    accentColor: root.currentAgent?.mochi?.color ?? (root.currentAgent?.color ?? "#4ADE80")
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Mochi"
                        font: Tokens.font.title.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.activeCount > 0
                            ? (root.activeCount + " " + Tr.tr("agent session active"))
                            : Tr.tr("Watching your agents")
                        font: Tokens.font.body.small
                        color: root.activeCount > 0
                            ? (root.currentAgent?.color ?? Colours.palette.m3primary)
                            : Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledRect {
                    Layout.alignment: Qt.AlignHCenter
                    implicitHeight: 26
                    implicitWidth: statusRow.implicitWidth + Tokens.padding.medium * 2
                    radius: Tokens.rounding.full
                    color: root.activeCount > 0
                        ? Qt.alpha(root.currentAgent?.color ?? Colours.palette.m3primary, 0.16)
                        : Colours.tPalette.m3surfaceContainerHighest

                    RowLayout {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            color: root.activeCount > 0
                                ? (root.currentAgent?.mochi?.color ?? (root.currentAgent?.color ?? Colours.palette.m3primary))
                                : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            text: root.activeCount > 0
                                ? (root.currentAgent?.mochi?.label ? root.currentAgent.mochi.label.toUpperCase() : Tr.tr("ACTIVE"))
                                : Tr.tr("ALL IDLE")
                            font: Tokens.font.label.small
                            color: root.activeCount > 0
                                ? (root.currentAgent?.mochi?.color ?? (root.currentAgent?.color ?? Colours.palette.m3primary))
                                : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ── SISI KANAN: AGENT PILLS + TICKER + METRICS ─────────────────────────
        ColumnLayout {
            id: rightColumn

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            // Header & Refresh
            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: Tr.tr("Coding Agents")
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3onSurface
                }

                Item { Layout.fillWidth: true }

                IconButton {
                    icon: "refresh"
                    type: IconButton.Tonal
                    onClicked: {
                        if (!proc.running)
                            proc.running = true;
                    }
                }
            }

            // Coucou Agent Pills Row + Plus (+) Button
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: ScriptModel {
                        values: root.agents
                    }

                    delegate: StyledRect {
                        id: pill

                        required property int index
                        required property var modelData

                        readonly property bool isSelected: !root.showAddSheet && root.selectedIndex === index
                        readonly property bool isRunning: modelData.running
                        readonly property color pillColor: modelData.color

                        implicitHeight: 34
                        implicitWidth: pillRow.implicitWidth + Tokens.padding.medium * 2
                        radius: Tokens.rounding.full

                        color: isSelected
                            ? Qt.alpha(pillColor, 0.24)
                            : (isRunning ? Qt.alpha(pillColor, 0.12) : Colours.tPalette.m3surfaceContainer)

                        border.color: isSelected
                            ? pillColor
                            : (isRunning ? Qt.alpha(pillColor, 0.5) : "transparent")
                        border.width: isSelected ? 2 : 1

                        RowLayout {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: 7

                            // Status Dot
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: pill.isRunning ? pill.pillColor : Colours.palette.m3outline

                                SequentialAnimation on opacity {
                                    running: pill.isRunning
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.4; duration: 900 }
                                    NumberAnimation { to: 1.0; duration: 900 }
                                }
                            }

                            StyledText {
                                text: pill.modelData.name
                                font: Tokens.font.label.medium
                                color: pill.isSelected
                                    ? Colours.palette.m3onSurface
                                    : (pill.isRunning ? pill.pillColor : Colours.palette.m3onSurfaceVariant)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.showAddSheet = false;
                                root.selectedIndex = pill.index;
                            }
                        }
                    }
                }

                // Plus (+) Button to auto-detect & launch harness
                StyledRect {
                    id: addPillBtn
                    implicitHeight: 34
                    implicitWidth: 34
                    radius: Tokens.rounding.full
                    color: root.showAddSheet
                        ? Colours.palette.m3primary
                        : (addArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainer)
                    border.color: root.showAddSheet ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.2)
                    border.width: 1

                    Behavior on color { CAnim {} }

                    StateLayer {
                        id: addArea
                        radius: Tokens.rounding.full
                        onClicked: root.showAddSheet = !root.showAddSheet
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.showAddSheet ? "close" : "add"
                        fontStyle: Tokens.font.icon.small
                        color: root.showAddSheet ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Selected Agent Detail Card
            StyledRect {
                visible: !root.showAddSheet && (root.agents?.length ?? 0) > 0
                Layout.fillWidth: true
                implicitHeight: detailLayout.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                border.color: root.currentAgent?.running
                    ? Qt.alpha(root.currentAgent?.color ?? Colours.palette.m3primary, 0.35)
                    : "transparent"
                border.width: 1

                ColumnLayout {
                    id: detailLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    // Card Title Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        StyledRect {
                            implicitWidth: 38
                            implicitHeight: 38
                            radius: Tokens.rounding.medium
                            color: root.currentAgent?.running
                                ? Qt.alpha(root.currentAgent?.color ?? Colours.palette.m3primary, 0.22)
                                : Colours.tPalette.m3surfaceContainerHighest

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: root.currentAgent?.icon ?? "smart_toy"
                                color: root.currentAgent?.running
                                    ? (root.currentAgent?.color ?? Colours.palette.m3primary)
                                    : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.medium
                            }
                        }

                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true

                            RowLayout {
                                spacing: 8

                                StyledText {
                                    text: root.currentAgent?.name ?? ""
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3onSurface
                                }

                                StyledRect {
                                    implicitHeight: 18
                                    implicitWidth: detailStatus.implicitWidth + 10
                                    radius: Tokens.rounding.full
                                    color: root.currentAgent?.running
                                        ? Qt.alpha(root.currentAgent?.mochi?.color ?? (root.currentAgent?.color ?? Colours.palette.m3primary), 0.2)
                                        : Colours.tPalette.m3surfaceContainerHighest

                                    StyledText {
                                        id: detailStatus
                                        anchors.centerIn: parent
                                        text: root.currentAgent?.running
                                            ? (root.currentAgent?.mochi?.label ? root.currentAgent.mochi.label.toUpperCase() : Tr.tr("RUNNING"))
                                            : Tr.tr("IDLE")
                                        font: Tokens.font.label.small
                                        color: root.currentAgent?.running
                                            ? (root.currentAgent?.mochi?.color ?? (root.currentAgent?.color ?? Colours.palette.m3primary))
                                            : Colours.palette.m3onSurfaceVariant
                                    }
                                }
                            }

                            StyledText {
                                text: root.currentAgent?.running
                                    ? ("PID " + root.currentAgent.pid + " • " + Tr.tr("Uptime: ") + root.currentAgent.etime)
                                    : Tr.tr("No background process active")
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    // Coucou Live Activity Ticker Box
                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: tickerRow.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.medium
                        color: Colours.tPalette.m3surfaceContainerLowest

                        border.color: Qt.alpha(Colours.palette.m3outline, 0.2)
                        border.width: 1

                        RowLayout {
                            id: tickerRow
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: "code"
                                color: root.currentAgent?.running
                                    ? (root.currentAgent?.color ?? Colours.palette.m3primary)
                                    : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.currentAgent?.running
                                    ? (root.currentAgent.window_title ? root.currentAgent.window_title : root.currentAgent.activity)
                                    : Tr.tr("Standby • Ready to start")
                                font: Tokens.font.body.small
                                color: root.currentAgent?.running
                                    ? Colours.palette.m3onSurface
                                    : Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Metrics Grid (CPU, RAM, Instances)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        // CPU Card
                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: Tokens.rounding.medium
                            color: Colours.tPalette.m3surfaceContainerHigh

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "CPU"
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (root.currentAgent?.running ? root.currentAgent.cpu : "0.0") + "%"
                                    font: Tokens.font.title.small
                                    color: root.currentAgent?.color ?? Colours.palette.m3primary
                                }
                            }
                        }

                        // RAM Card
                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: Tokens.rounding.medium
                            color: Colours.tPalette.m3surfaceContainerHigh

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "RAM"
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (root.currentAgent?.running ? root.currentAgent.mem : "0.0") + "%"
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3secondary
                                }
                            }
                        }

                        // Instances
                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: Tokens.rounding.medium
                            color: Colours.tPalette.m3surfaceContainerHigh

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "PROCS"
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: String(root.currentAgent?.running ? root.currentAgent.count : 0)
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3tertiary
                                }
                            }
                        }
                    }

                    // Multi-terminal sessions list
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small
                        visible: (root.currentAgent?.instances?.length ?? 0) > 1

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: "terminal"
                                fontStyle: Tokens.font.icon.small
                                color: root.currentAgent?.color ?? Colours.palette.m3primary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Tr.tr("Active Terminal Windows") + " (" + (root.currentAgent?.instances?.length ?? 0) + ")"
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        Repeater {
                            model: root.currentAgent?.instances ?? []

                            delegate: StyledRect {
                                id: instRect

                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                implicitHeight: 48
                                radius: Tokens.rounding.medium
                                color: instArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerHigh
                                border.color: instArea.containsMouse ? (root.currentAgent?.color ?? Colours.palette.m3primary) : Qt.alpha(Colours.palette.m3outline, 0.15)
                                border.width: 1

                                Behavior on color { CAnim {} }
                                Behavior on border.color { CAnim {} }

                                StateLayer {
                                    id: instArea
                                    radius: Tokens.rounding.medium
                                    onClicked: root.jumpToWindow(instRect.modelData.window_address, instRect.modelData.workspace_id)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.padding.medium
                                    anchors.rightMargin: Tokens.padding.medium
                                    spacing: Tokens.spacing.small

                                    // Mini Mochi Avatar (Coucou micro bot)
                                    MiniMochi {
                                        implicitWidth: 32
                                        implicitHeight: 28
                                        state: instRect.modelData.mochi?.state ?? "idle"
                                        accentColor: instRect.modelData.mochi?.color ?? (root.currentAgent?.color ?? Colours.palette.m3primary)
                                    }

                                    // Title & process info
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: instRect.modelData.window_title || ("Terminal #" + (instRect.index + 1))
                                                elide: Text.ElideRight
                                                font: Tokens.font.label.large
                                                color: Colours.palette.m3onSurface
                                            }

                                            StyledText {
                                                text: instRect.modelData.mochi?.label ?? ""
                                                font: Tokens.font.label.small
                                                color: instRect.modelData.mochi?.color ?? (root.currentAgent?.color ?? Colours.palette.m3primary)
                                            }
                                        }

                                        StyledText {
                                            text: "PID " + instRect.modelData.pid + (instRect.modelData.workspace_id ? (" • WS " + instRect.modelData.workspace_id) : "") + " • CPU " + instRect.modelData.cpu + "% • RAM " + instRect.modelData.mem + "%"
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurfaceVariant
                                        }
                                    }

                                    MaterialIcon {
                                        text: "open_in_new"
                                        fontStyle: Tokens.font.icon.small
                                        color: instArea.containsMouse ? (root.currentAgent?.color ?? Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                                    }
                                }
                            }
                        }

                        // Option to launch a new terminal instance
                        IconTextButton {
                            Layout.fillWidth: true
                            icon: "add"
                            text: Tr.tr("Launch Another Terminal")
                            type: ButtonBase.Text
                            onClicked: {
                                root.screenState.dashboard = false;
                                Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "sh", "-c", `${root.currentAgent?.id}; exec ${Quickshell.env("SHELL") || "bash"}`]);
                            }
                        }
                    }

                    // Single Jump to Terminal action (when <= 1 terminal instance)
                    IconTextButton {
                        Layout.fillWidth: true
                        visible: (root.currentAgent?.instances?.length ?? 0) <= 1
                        icon: root.currentAgent?.window_address ? "open_in_new" : "terminal"
                        text: root.currentAgent?.window_address
                            ? Tr.tr("Jump to Terminal")
                            : (root.currentAgent?.running ? Tr.tr("Bring Process to Front") : (Tr.tr("Launch ") + (root.currentAgent?.name ?? "Agent")))
                        type: ButtonBase.Tonal
                        onClicked: root.jumpToAgent(root.currentAgent)
                    }
                }
            }

            // Empty State Card (when no agent installed/running and not in Add mode)
            StyledRect {
                visible: !root.showAddSheet && (!root.agents || root.agents.length === 0)
                Layout.fillWidth: true
                implicitHeight: 200
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer
                border.color: Qt.alpha(Colours.palette.m3outline, 0.2)
                border.width: 1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "smart_toy"
                        fontStyle: Tokens.font.icon.large
                        color: Colours.palette.m3outline
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Tr.tr("No Coding Agent Detected")
                            font: Tokens.font.title.small
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Tr.tr("Install OpenCode, Claude Code, etc. or launch via (+)")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    IconTextButton {
                        Layout.alignment: Qt.AlignHCenter
                        icon: "add"
                        text: Tr.tr("Launch Custom Agent (+)")
                        type: ButtonBase.Tonal
                        onClicked: root.showAddSheet = true
                    }
                }
            }

            // Add / Launch Harness Card
            StyledRect {
                id: addHarnessCard
                visible: root.showAddSheet
                Layout.fillWidth: true
                implicitHeight: addLayout.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer
                border.color: Qt.alpha(Colours.palette.m3primary, 0.35)
                border.width: 1

                ColumnLayout {
                    id: addLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    // Card Title Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        StyledRect {
                            implicitWidth: 38
                            implicitHeight: 38
                            radius: Tokens.rounding.medium
                            color: Qt.alpha(Colours.palette.m3primary, 0.2)

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "auto_mode"
                                color: Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.medium
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                text: Tr.tr("Agent Harness Launcher")
                                font: Tokens.font.title.small
                                color: Colours.palette.m3onSurface
                            }

                            StyledText {
                                text: Tr.tr("Auto-detected harnesses in system PATH")
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        IconButton {
                            icon: "close"
                            type: IconButton.Text
                            onClicked: root.showAddSheet = false
                        }
                    }

                    // Section: Installed Harnesses
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: Tr.tr("Detected System Harnesses") + " (" + root.installedHarnesses.length + ")"
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        Repeater {
                            model: ScriptModel {
                                values: root.installedHarnesses
                            }

                            delegate: StyledRect {
                                id: harnessItem
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: Tokens.rounding.medium
                                color: Colours.tPalette.m3surfaceContainerHigh
                                border.color: Qt.alpha(Colours.palette.m3outline, 0.15)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.padding.medium
                                    anchors.rightMargin: Tokens.padding.medium
                                    spacing: Tokens.spacing.small

                                    MaterialIcon {
                                        text: harnessItem.modelData.icon || "terminal"
                                        color: harnessItem.modelData.color || Colours.palette.m3primary
                                        fontStyle: Tokens.font.icon.small
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        RowLayout {
                                            spacing: 6
                                            StyledText {
                                                text: harnessItem.modelData.name
                                                font: Tokens.font.label.large
                                                color: Colours.palette.m3onSurface
                                            }

                                            StyledText {
                                                visible: harnessItem.modelData.running
                                                text: "• " + Tr.tr("RUNNING")
                                                font: Tokens.font.label.small
                                                color: harnessItem.modelData.color || Colours.palette.m3primary
                                            }
                                        }

                                        StyledText {
                                            text: harnessItem.modelData.path
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurfaceVariant
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    IconTextButton {
                                        icon: "terminal"
                                        text: Tr.tr("Launch")
                                        type: ButtonBase.Tonal
                                        onClicked: {
                                            root.showAddSheet = false;
                                            root.screenState.dashboard = false;
                                            Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "sh", "-c", `${harnessItem.modelData.bin}; exec ${Quickshell.env("SHELL") || "bash"}`]);
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: root.installedHarnesses.length === 0
                            text: Tr.tr("No known harnesses found in system PATH.")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    // Section: Custom Command Launcher
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: Tr.tr("Run Custom Agent / Script")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: Tokens.rounding.medium
                            color: Colours.tPalette.m3surfaceContainerHigh
                            border.color: Qt.alpha(Colours.palette.m3outline, 0.2)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.medium
                                anchors.rightMargin: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "terminal"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }

                                TextInput {
                                    id: customCmdInput
                                    Layout.fillWidth: true
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                    clip: true
                                    selectByMouse: true

                                    StyledText {
                                        anchors.fill: parent
                                        text: Tr.tr("Command (e.g. aider, opencode, python agent.py)...")
                                        font: customCmdInput.font
                                        color: Colours.palette.m3outline
                                        visible: !customCmdInput.text && !customCmdInput.activeFocus
                                    }

                                    onAccepted: {
                                        if (customCmdInput.text.trim()) {
                                            const cmd = customCmdInput.text.trim();
                                            root.showAddSheet = false;
                                            root.screenState.dashboard = false;
                                            Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "sh", "-c", `${cmd}; exec ${Quickshell.env("SHELL") || "bash"}`]);
                                        }
                                    }
                                }

                                IconTextButton {
                                    icon: "play_arrow"
                                    text: Tr.tr("Run")
                                    type: ButtonBase.Filled
                                    onClicked: {
                                        if (customCmdInput.text.trim()) {
                                            const cmd = customCmdInput.text.trim();
                                            root.showAddSheet = false;
                                            root.screenState.dashboard = false;
                                            Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "sh", "-c", `${cmd}; exec ${Quickshell.env("SHELL") || "bash"}`]);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
