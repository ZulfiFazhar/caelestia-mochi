pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property bool active: false
    property string state: "idle" // idle, working, thinking, searching, approval, question, error, finished, sleeping, dizzy, ratelimit
    property color accentColor: "#4ADE80"
    property real lookTargetX: 0
    property real lookTargetY: 0
    property bool isHovered: false

    property bool blinking: false
    property bool squished: false
    property int clickCount: 0

    implicitWidth: 130
    implicitHeight: 130

    // Coucou official glow colors per state
    readonly property color glowColor: {
        switch (root.state) {
        case "working": return "#3B9EFF";
        case "thinking": return "#A78BFA";
        case "searching": return "#6366F1";
        case "approval": return "#F5A524";
        case "question": return "#22D3EE";
        case "error": return "#F4505E";
        case "finished": return "#34D399";
        case "ratelimit": return "#F59E0B";
        case "sleeping": return "#94A3B8";
        case "dizzy": return "#EC4899";
        default: return root.accentColor;
        }
    }

    readonly property string eyeType: {
        if (root.clickCount >= 3) return "dizzy";
        switch (root.state) {
        case "finished": return "happy";
        case "sleeping": return "closed";
        case "error": return "flat";
        case "approval": return "wide";
        case "ratelimit": return "flat";
        case "dizzy": return "dizzy";
        default: return "pill";
        }
    }

    readonly property real activeLookX: {
        if (root.isHovered) return root.lookTargetX;
        if (root.state === "thinking") return 0.55;
        if (root.state === "searching") return root.scanOffset;
        return root.lookTargetX;
    }

    readonly property real activeLookY: {
        if (root.isHovered) return root.lookTargetY;
        if (root.state === "thinking") return -0.45;
        return root.lookTargetY;
    }

    // Scanning animation for searching state
    property real scanOffset: 0
    SequentialAnimation on scanOffset {
        running: root.state === "searching" && !root.isHovered
        loops: Animation.Infinite
        NumberAnimation { to: 0.8; duration: 550; easing.type: Easing.InOutSine }
        NumberAnimation { to: -0.8; duration: 550; easing.type: Easing.InOutSine }
    }

    // Bounce for approval
    property real bounceY: 0
    SequentialAnimation on bounceY {
        running: root.state === "approval"
        loops: Animation.Infinite
        NumberAnimation { to: -6; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0; duration: 260; easing.type: Easing.InQuad }
        PauseAnimation { duration: 300 }
    }

    // Shiver for error
    property real shiverX: 0
    SequentialAnimation on shiverX {
        running: root.state === "error"
        loops: Animation.Infinite
        NumberAnimation { to: -2; duration: 60 }
        NumberAnimation { to: 2; duration: 60 }
        NumberAnimation { to: 0; duration: 60 }
        PauseAnimation { duration: 600 }
    }

    // Blink timer (suppressed during sleeping or closed eyes)
    Timer {
        interval: 2800 + Math.random() * 2000
        running: root.state !== "sleeping" && root.eyeType !== "closed"
        repeat: true
        onTriggered: {
            root.blinking = true;
            blinkReset.restart();
        }
    }

    Timer {
        id: blinkReset
        interval: 130
        onTriggered: root.blinking = false
    }

    Timer {
        id: clickResetTimer
        interval: 1500
        onTriggered: root.clickCount = 0
    }

    Timer {
        id: squishResetTimer
        interval: 220
        onTriggered: root.squished = false
    }

    // Aura glow behind body
    Rectangle {
        id: aura
        anchors.centerIn: parent
        width: 104
        height: 104
        radius: 52
        color: root.active ? Qt.alpha(root.glowColor, 0.32) : Qt.alpha(Colours.palette.m3onSurface, 0.08)

        Behavior on color {
            ColorAnimation { duration: 400 }
        }

        SequentialAnimation on scale {
            running: root.active && root.state !== "sleeping"
            loops: Animation.Infinite
            NumberAnimation { to: 1.14; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.96; duration: 1600; easing.type: Easing.InOutSine }
        }
    }

    // Mochi Body (Squircle)
    Rectangle {
        id: body

        property real scaleX: root.squished ? 1.15 : (root.state === "sleeping" ? 1.03 : 1.0)
        property real scaleY: root.squished ? 0.85 : (root.state === "sleeping" ? 0.96 : 1.0)

        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.round(root.bounceY)
        anchors.horizontalCenterOffset: Math.round(root.shiverX)

        width: 92 * scaleX
        height: 82 * scaleY
        radius: 38
        rotation: root.state === "question" ? 6 : 0

        Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

        // Coucou soft body gradient: #FFFAF5 to #DDCCBF
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.active ? "#FFFFFF" : "#F7F5F0" }
            GradientStop { position: 1.0; color: root.active ? "#E2E8F0" : "#D8D0C5" }
        }

        border.color: root.active ? root.glowColor : Qt.alpha(Colours.palette.m3outline, 0.2)
        border.width: root.active ? 2 : 1

        Behavior on scaleX { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on scaleY { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        // Subtle top highlight
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.65
            height: 14
            radius: 7
            color: Qt.alpha("#FFFFFF", 0.45)
        }

        // Rosy Cheeks
        Rectangle {
            id: leftCheek
            x: 12 + root.activeLookX * 2
            y: 44 + root.activeLookY * 2
            width: 12
            height: 7
            radius: 4
            color: Qt.alpha("#FF6B8B", root.active ? 0.65 : 0.35)

            Behavior on x { NumberAnimation { duration: 150 } }
            Behavior on y { NumberAnimation { duration: 150 } }
        }

        Rectangle {
            id: rightCheek
            x: body.width - 24 + root.activeLookX * 2
            y: 44 + root.activeLookY * 2
            width: 12
            height: 7
            radius: 4
            color: Qt.alpha("#FF6B8B", root.active ? 0.65 : 0.35)

            Behavior on x { NumberAnimation { duration: 150 } }
            Behavior on y { NumberAnimation { duration: 150 } }
        }

        // ── Eye Expressions ──────────────────────────────────────────────────
        // Left Eye Slot
        Item {
            id: leftEye
            x: Math.round(27 + root.activeLookX * 6)
            y: Math.round(33 + root.activeLookY * 5)
            width: 12
            height: 14

            Behavior on x { NumberAnimation { duration: 120 } }
            Behavior on y { NumberAnimation { duration: 120 } }

            // 1. Pill Eye
            Rectangle {
                visible: root.eyeType === "pill"
                anchors.centerIn: parent
                width: 8
                height: root.blinking ? 2 : 13
                radius: 4
                color: "#181412"

                Rectangle {
                    visible: !root.blinking
                    x: 2
                    y: 2
                    width: 3
                    height: 3
                    radius: 1.5
                    color: "#FFFFFF"
                }
            }

            // 2. Wide Eye (approval)
            Rectangle {
                visible: root.eyeType === "wide"
                anchors.centerIn: parent
                width: 10
                height: root.blinking ? 2 : 15
                radius: 5
                color: "#181412"

                Rectangle {
                    visible: !root.blinking
                    x: 2
                    y: 2
                    width: 4
                    height: 4
                    radius: 2
                    color: "#FFFFFF"
                }
            }

            // 3. Flat Eye (error / ratelimit)
            Rectangle {
                visible: root.eyeType === "flat"
                anchors.centerIn: parent
                width: 12
                height: 3
                radius: 1.5
                color: "#181412"
            }

            // 4. Happy Eye Arc (finished)
            Shape {
                visible: root.eyeType === "happy"
                anchors.centerIn: parent
                width: 11
                height: 7
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    strokeColor: "#181412"
                    strokeWidth: 2.4
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 0
                    startY: 6

                    PathArc {
                        x: 11
                        y: 6
                        radiusX: 6
                        radiusY: 6
                        direction: PathArc.Counterclockwise
                    }
                }
            }

            // 5. Closed Eye (sleeping)
            Shape {
                visible: root.eyeType === "closed"
                anchors.centerIn: parent
                width: 11
                height: 7
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    strokeColor: "#64748B"
                    strokeWidth: 2.2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 0
                    startY: 2

                    PathArc {
                        x: 11
                        y: 2
                        radiusX: 6
                        radiusY: 6
                        direction: PathArc.Clockwise
                    }
                }
            }

            // 6. Dizzy Eye (spiral / x)
            Text {
                visible: root.eyeType === "dizzy"
                anchors.centerIn: parent
                text: "×"
                font.pixelSize: 15
                font.bold: true
                color: "#181412"
            }
        }

        // Right Eye Slot
        Item {
            id: rightEye
            x: Math.round(55 + root.activeLookX * 6)
            y: Math.round(33 + root.activeLookY * 5)
            width: 12
            height: 14

            Behavior on x { NumberAnimation { duration: 120 } }
            Behavior on y { NumberAnimation { duration: 120 } }

            // 1. Pill Eye
            Rectangle {
                visible: root.eyeType === "pill"
                anchors.centerIn: parent
                width: 8
                height: root.blinking ? 2 : 13
                radius: 4
                color: "#181412"

                Rectangle {
                    visible: !root.blinking
                    x: 2
                    y: 2
                    width: 3
                    height: 3
                    radius: 1.5
                    color: "#FFFFFF"
                }
            }

            // 2. Wide Eye
            Rectangle {
                visible: root.eyeType === "wide"
                anchors.centerIn: parent
                width: 10
                height: root.blinking ? 2 : 15
                radius: 5
                color: "#181412"

                Rectangle {
                    visible: !root.blinking
                    x: 2
                    y: 2
                    width: 4
                    height: 4
                    radius: 2
                    color: "#FFFFFF"
                }
            }

            // 3. Flat Eye
            Rectangle {
                visible: root.eyeType === "flat"
                anchors.centerIn: parent
                width: 12
                height: 3
                radius: 1.5
                color: "#181412"
            }

            // 4. Happy Eye Arc
            Shape {
                visible: root.eyeType === "happy"
                anchors.centerIn: parent
                width: 11
                height: 7
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    strokeColor: "#181412"
                    strokeWidth: 2.4
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 0
                    startY: 6

                    PathArc {
                        x: 11
                        y: 6
                        radiusX: 6
                        radiusY: 6
                        direction: PathArc.Counterclockwise
                    }
                }
            }

            // 5. Closed Eye
            Shape {
                visible: root.eyeType === "closed"
                anchors.centerIn: parent
                width: 11
                height: 7
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    strokeColor: "#64748B"
                    strokeWidth: 2.2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 0
                    startY: 2

                    PathArc {
                        x: 11
                        y: 2
                        radiusX: 6
                        radiusY: 6
                        direction: PathArc.Clockwise
                    }
                }
            }

            // 6. Dizzy Eye
            Text {
                visible: root.eyeType === "dizzy"
                anchors.centerIn: parent
                text: "×"
                font.pixelSize: 15
                font.bold: true
                color: "#181412"
            }
        }

        // ── Badges on head ───────────────────────────────────────────────────
        // 1. Animated dots badge when active ("•••")
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -8
            spacing: 3
            visible: root.active && (root.state === "working" || root.state === "idle")

            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    width: 5
                    height: 5
                    radius: 2.5
                    color: root.glowColor

                    SequentialAnimation on y {
                        running: root.active
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 180 }
                        NumberAnimation { to: -4; duration: 240; easing.type: Easing.OutQuad }
                        NumberAnimation { to: 0; duration: 240; easing.type: Easing.InQuad }
                        PauseAnimation { duration: (2 - index) * 180 + 300 }
                    }
                }
            }
        }

        // 2. Bang "!" badge for approval
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -10
            width: 14
            height: 14
            radius: 7
            color: "#F5A524"
            visible: root.state === "approval"

            Text {
                anchors.centerIn: parent
                text: "!"
                font.pixelSize: 10
                font.bold: true
                color: "#FFFFFF"
            }
        }

        // 3. Question "?" badge for question
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -10
            width: 14
            height: 14
            radius: 7
            color: "#22D3EE"
            visible: root.state === "question"

            Text {
                anchors.centerIn: parent
                text: "?"
                font.pixelSize: 10
                font.bold: true
                color: "#FFFFFF"
            }
        }

        // 4. Sparkle for finished
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -7
            width: 8
            height: 8
            radius: 4
            color: "#34D399"
            visible: root.state === "finished"
        }
    }

    // Interactive Click Area (Squish Mochi on tap!)
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        onEntered: root.isHovered = true

        onPositionChanged: (mouse) => {
            root.lookTargetX = Math.max(-1.0, Math.min(1.0, (mouse.x - width / 2) / (width / 2)));
            root.lookTargetY = Math.max(-1.0, Math.min(1.0, (mouse.y - height / 2) / (height / 2)));
        }

        onExited: {
            root.isHovered = false;
            root.lookTargetX = 0;
            root.lookTargetY = 0;
        }

        onClicked: {
            root.clickCount++;
            clickResetTimer.restart();
            root.squished = true;
            squishResetTimer.restart();
        }
    }
}
