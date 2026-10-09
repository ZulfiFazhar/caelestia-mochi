pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property string state: "idle" // idle, working, thinking, searching, approval, question, error, finished, sleeping, dizzy, ratelimit
    property color accentColor: Colours.palette.m3primary
    property bool active: state !== "sleeping" && state !== "idle"

    implicitWidth: 32
    implicitHeight: 28

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

    // Scanning animation for searching state
    property real scanOffset: 0
    SequentialAnimation on scanOffset {
        running: root.state === "searching"
        loops: Animation.Infinite
        NumberAnimation { to: 1.6; duration: 450; easing.type: Easing.InOutSine }
        NumberAnimation { to: -1.6; duration: 450; easing.type: Easing.InOutSine }
    }

    // Gentle bounce for approval / working
    property real bounceY: 0
    SequentialAnimation on bounceY {
        running: root.state === "approval"
        loops: Animation.Infinite
        NumberAnimation { to: -2; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0; duration: 220; easing.type: Easing.InQuad }
        PauseAnimation { duration: 200 }
    }

    // Shiver animation for error state
    property real shiverX: 0
    SequentialAnimation on shiverX {
        running: root.state === "error"
        loops: Animation.Infinite
        NumberAnimation { to: -1; duration: 60 }
        NumberAnimation { to: 1; duration: 60 }
        NumberAnimation { to: 0; duration: 60 }
        PauseAnimation { duration: 500 }
    }

    // Soft Aura Glow behind mini body
    Rectangle {
        anchors.centerIn: body
        width: 28
        height: 24
        radius: 12
        color: Qt.alpha(root.glowColor, root.active ? 0.35 : 0.12)

        Behavior on color { ColorAnimation { duration: 300 } }
    }

    // Mini Mochi Body (Squircle)
    Rectangle {
        id: body
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.round(1 + root.bounceY)
        anchors.horizontalCenterOffset: Math.round(root.shiverX)

        width: 26
        height: 22
        radius: 10

        // Coucou soft body gradient
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.active ? "#FFFFFF" : "#F7F5F0" }
            GradientStop { position: 1.0; color: root.active ? "#E2E8F0" : "#D8D0C5" }
        }

        border.color: root.active ? root.glowColor : Qt.alpha(Colours.palette.m3outline, 0.25)
        border.width: 1

        Behavior on border.color { ColorAnimation { duration: 300 } }

        // Top shine
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.6
            height: 4
            radius: 2
            color: Qt.alpha("#FFFFFF", 0.5)
        }

        // Rosy Cheeks
        Rectangle {
            x: 3
            y: 11
            width: 3.5
            height: 2
            radius: 1
            color: Qt.alpha("#FF6B8B", root.active ? 0.65 : 0.3)
        }

        Rectangle {
            x: body.width - 6.5
            y: 11
            width: 3.5
            height: 2
            radius: 1
            color: Qt.alpha("#FF6B8B", root.active ? 0.65 : 0.3)
        }

        // ── Eye Expressions ──────────────────────────────────────────────────
        Item {
            id: eyeContainer
            anchors.fill: parent

            readonly property real lookX: {
                if (root.state === "thinking") return 1.4;
                if (root.state === "searching") return root.scanOffset;
                return 0;
            }
            readonly property real lookY: {
                if (root.state === "thinking") return -1.2;
                return 0;
            }

            // Left Eye Container
            Item {
                id: leftEyeSlot
                x: Math.round(7 + eyeContainer.lookX)
                y: Math.round(8 + eyeContainer.lookY)
                width: 5
                height: 6

                // 1. Pill Eye (idle / working / searching / thinking)
                Rectangle {
                    visible: root.eyeType === "pill"
                    anchors.centerIn: parent
                    width: 2.6
                    height: 5.2
                    radius: 1.3
                    color: "#181412"

                    Rectangle {
                        x: 0.5
                        y: 0.6
                        width: 1.2
                        height: 1.2
                        radius: 0.6
                        color: "#FFFFFF"
                    }
                }

                // 2. Wide Eye (approval)
                Rectangle {
                    visible: root.eyeType === "wide"
                    anchors.centerIn: parent
                    width: 3.8
                    height: 5.8
                    radius: 1.9
                    color: "#181412"

                    Rectangle {
                        x: 0.6
                        y: 0.6
                        width: 1.6
                        height: 1.6
                        radius: 0.8
                        color: "#FFFFFF"
                    }
                }

                // 3. Flat Eye (error / ratelimit)
                Rectangle {
                    visible: root.eyeType === "flat"
                    anchors.centerIn: parent
                    width: 5
                    height: 1.8
                    radius: 0.9
                    color: "#181412"
                }

                // 4. Happy Eye Arc (finished)
                Shape {
                    visible: root.eyeType === "happy"
                    anchors.centerIn: parent
                    width: 5
                    height: 3
                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        strokeColor: "#181412"
                        strokeWidth: 1.4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 0
                        startY: 3

                        PathArc {
                            x: 5
                            y: 3
                            radiusX: 2.8
                            radiusY: 2.8
                            direction: PathArc.Counterclockwise
                        }
                    }
                }

                // 5. Closed Eye (sleeping)
                Shape {
                    visible: root.eyeType === "closed"
                    anchors.centerIn: parent
                    width: 5
                    height: 3
                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        strokeColor: "#64748B"
                        strokeWidth: 1.4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 0
                        startY: 1

                        PathArc {
                            x: 5
                            y: 1
                            radiusX: 2.8
                            radiusY: 2.8
                            direction: PathArc.Clockwise
                        }
                    }
                }

                // 6. Dizzy Eye (spiral / x)
                Text {
                    visible: root.eyeType === "dizzy"
                    anchors.centerIn: parent
                    text: "×"
                    font.pixelSize: 8
                    font.bold: true
                    color: "#181412"
                }
            }

            // Right Eye Container
            Item {
                id: rightEyeSlot
                x: Math.round(14 + eyeContainer.lookX)
                y: Math.round(8 + eyeContainer.lookY)
                width: 5
                height: 6

                // 1. Pill Eye
                Rectangle {
                    visible: root.eyeType === "pill"
                    anchors.centerIn: parent
                    width: 2.6
                    height: 5.2
                    radius: 1.3
                    color: "#181412"

                    Rectangle {
                        x: 0.5
                        y: 0.6
                        width: 1.2
                        height: 1.2
                        radius: 0.6
                        color: "#FFFFFF"
                    }
                }

                // 2. Wide Eye
                Rectangle {
                    visible: root.eyeType === "wide"
                    anchors.centerIn: parent
                    width: 3.8
                    height: 5.8
                    radius: 1.9
                    color: "#181412"

                    Rectangle {
                        x: 0.6
                        y: 0.6
                        width: 1.6
                        height: 1.6
                        radius: 0.8
                        color: "#FFFFFF"
                    }
                }

                // 3. Flat Eye
                Rectangle {
                    visible: root.eyeType === "flat"
                    anchors.centerIn: parent
                    width: 5
                    height: 1.8
                    radius: 0.9
                    color: "#181412"
                }

                // 4. Happy Eye Arc
                Shape {
                    visible: root.eyeType === "happy"
                    anchors.centerIn: parent
                    width: 5
                    height: 3
                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        strokeColor: "#181412"
                        strokeWidth: 1.4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 0
                        startY: 3

                        PathArc {
                            x: 5
                            y: 3
                            radiusX: 2.8
                            radiusY: 2.8
                            direction: PathArc.Counterclockwise
                        }
                    }
                }

                // 5. Closed Eye
                Shape {
                    visible: root.eyeType === "closed"
                    anchors.centerIn: parent
                    width: 5
                    height: 3
                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        strokeColor: "#64748B"
                        strokeWidth: 1.4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 0
                        startY: 1

                        PathArc {
                            x: 5
                            y: 1
                            radiusX: 2.8
                            radiusY: 2.8
                            direction: PathArc.Clockwise
                        }
                    }
                }

                // 6. Dizzy Eye
                Text {
                    visible: root.eyeType === "dizzy"
                    anchors.centerIn: parent
                    text: "×"
                    font.pixelSize: 8
                    font.bold: true
                    color: "#181412"
                }
            }
        }

        // ── Badges on top ────────────────────────────────────────────────────
        // 1. Working: Animated bouncing dots
        Row {
            visible: root.state === "working"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -5
            spacing: 2

            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    width: 2.5
                    height: 2.5
                    radius: 1.25
                    color: root.glowColor

                    SequentialAnimation on y {
                        running: root.state === "working"
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 120 }
                        NumberAnimation { to: -2; duration: 160; easing.type: Easing.OutQuad }
                        NumberAnimation { to: 0; duration: 160; easing.type: Easing.InQuad }
                        PauseAnimation { duration: (2 - index) * 120 + 200 }
                    }
                }
            }
        }

        // 2. Approval: Bang "!" badge
        Rectangle {
            visible: root.state === "approval"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -6
            width: 7
            height: 7
            radius: 3.5
            color: "#F5A524"

            Text {
                anchors.centerIn: parent
                text: "!"
                font.pixelSize: 6
                font.bold: true
                color: "#FFFFFF"
            }
        }

        // 3. Question: "?" badge
        Rectangle {
            visible: root.state === "question"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -6
            width: 7
            height: 7
            radius: 3.5
            color: "#22D3EE"

            Text {
                anchors.centerIn: parent
                text: "?"
                font.pixelSize: 6
                font.bold: true
                color: "#FFFFFF"
            }
        }

        // 4. Finished: Sparkle dot
        Rectangle {
            visible: root.state === "finished"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -4
            width: 4
            height: 4
            radius: 2
            color: "#34D399"
        }
    }
}
