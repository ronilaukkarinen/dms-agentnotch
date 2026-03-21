import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "ClaudeParser.js" as Parser

PluginComponent {
    id: root

    // Session state
    property var sessionState: Parser.createSessionState()
    property bool isActive: false
    property string currentSessionFile: ""

    // Settings from plugin data
    property bool showTokens: pluginData.showTokens !== undefined ? pluginData.showTokens : true
    property bool showCost: pluginData.showCost !== undefined ? pluginData.showCost : false
    property bool showToolName: pluginData.showToolName !== undefined ? pluginData.showToolName : true
    property int pollInterval: pluginData.pollInterval || 3

    // Source color: orange for Claude Code
    property color sourceColor: "#E5650A"

    // Track file position for incremental reads
    property int lastFileSize: 0

    Component.onCompleted: {
        sessionState = Parser.createSessionState()
        scanTimer.start()
    }

    // Scan for active Claude Code sessions periodically
    Timer {
        id: scanTimer
        interval: root.pollInterval * 1000
        repeat: true
        running: true
        onTriggered: {
            sessionScanner.running = true
        }
    }

    // Idle detection: mark session as done if no new tools for 10s
    Timer {
        id: idleTimer
        interval: 10000
        repeat: false
        running: false
        onTriggered: {
            if (root.sessionState.activeTools.length === 0 && !root.sessionState.isThinking) {
                root.isActive = false
            }
        }
    }

    // Permission check: if a tool runs > 2.5s without result
    Timer {
        id: permissionTimer
        interval: 2500
        repeat: true
        running: root.sessionState.activeTools.length > 0
        onTriggered: {
            var now = Date.now()
            var needsPermission = false
            var pendingTool = ""

            for (var i = 0; i < root.sessionState.activeTools.length; i++) {
                var tool = root.sessionState.activeTools[i]
                if (Parser.isPermissionEligible(tool.toolName)) {
                    var elapsed = now - tool.startTime
                    if (elapsed >= 2500) {
                        needsPermission = true
                        pendingTool = tool.toolName
                        break
                    }
                }
            }

            if (needsPermission !== root.sessionState.needsPermission) {
                root.sessionState.needsPermission = needsPermission
                root.sessionState.pendingPermissionTool = pendingTool
                root.sessionStateChanged()

                if (needsPermission) {
                    // Send notification with a fixed replace ID
                    permissionNotifier.command = ["notify-send", "-a", "Agent Notch", "-i", "dialog-password", "-u", "critical", "-h", "string:x-dunst-stack-tag:agentnotch-permission", "-h", "string:x-canonical-private-synchronous:agentnotch-permission", "✳ Claude Code needs permission", pendingTool + " is waiting for approval"]
                    permissionNotifier.running = true
                } else {
                    // Dismiss the notification when permission is no longer needed
                    permissionDismisser.command = ["notify-send", "-a", "Agent Notch", "-h", "string:x-dunst-stack-tag:agentnotch-permission", "-h", "string:x-canonical-private-synchronous:agentnotch-permission", "-t", "1", ""]
                    permissionDismisser.running = true
                }
            }
        }
    }

    // Notification sender - uses replace ID so we can dismiss it
    Process {
        id: permissionNotifier
        command: ["echo"]
        running: false
    }

    // Notification dismisser
    Process {
        id: permissionDismisser
        command: ["echo"]
        running: false
    }

    // Scan for active Claude sessions
    Process {
        id: sessionScanner
        command: ["sh", "-c", "newest=$(find \"$HOME/.claude/projects\" -name '*.jsonl' ! -name 'agent-*' -type f -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -1 | cut -f2); if [ -n \"$newest\" ]; then echo \"$newest\"; stat -c '%s' \"$newest\"; else echo ''; echo '0'; fi"]
        running: false

        stdout: SplitParser {
            id: scannerOutput
            property string filePath: ""
            property int lineCount: 0

            onRead: data => {
                if (lineCount === 0) {
                    filePath = data.trim()
                } else if (lineCount === 1) {
                    var fileSize = parseInt(data.trim()) || 0

                    if (filePath && filePath.length > 0) {
                        if (filePath !== root.currentSessionFile) {
                            root.currentSessionFile = filePath
                            root.lastFileSize = 0
                            root.sessionState = Parser.createSessionState()
                            root.isActive = true

                            historyReader.command = ["sh", "-c", "tail -c 51200 '" + filePath + "' | tail -50"]
                            historyReader.running = true
                        }

                        if (fileSize > root.lastFileSize && root.lastFileSize > 0) {
                            var bytesToRead = fileSize - root.lastFileSize
                            newDataReader.command = ["sh", "-c", "tail -c " + bytesToRead + " '" + filePath + "'"]
                            newDataReader.running = true
                            root.isActive = true
                        }

                        root.lastFileSize = fileSize
                    } else {
                        root.isActive = false
                    }
                }
                lineCount++
            }
        }

        onExited: (exitCode, exitStatus) => {
            scannerOutput.lineCount = 0
            scannerOutput.filePath = ""
        }
    }

    // Read recent history when switching sessions
    Process {
        id: historyReader
        command: ["sh", "-c", "echo"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                var line = data.trim()
                if (line.length > 0) {
                    root.sessionState = Parser.parseJSONLLine(line, root.sessionState)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.sessionState.activeTools = []
            root.sessionState.isThinking = false
            root.sessionState.needsPermission = false
            root.sessionStateChanged()
        }
    }

    // Read new data incrementally
    Process {
        id: newDataReader
        command: ["sh", "-c", "echo"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                var line = data.trim()
                if (line.length > 0) {
                    root.sessionState = Parser.parseJSONLLine(line, root.sessionState)
                    root.sessionStateChanged()
                    idleTimer.restart()
                }
            }
        }
    }

    function getStatusText() {
        if (!isActive) return "Idle"

        if (sessionState.needsPermission) return "Permission"
        if (sessionState.activeTools.length > 0) {
            var tool = sessionState.activeTools[sessionState.activeTools.length - 1]
            if (showToolName) return Parser.getToolDisplayName(tool.toolName)
            return "Working"
        }
        if (sessionState.isThinking) return "Thinking"
        if (sessionState.lastStopReason === "end_turn") return "Done"
        if (sessionState.lastStopReason === "interrupted") return "Stopped"
        return "Idle"
    }

    function getStatusIcon() {
        if (sessionState.needsPermission) return "lock"
        if (sessionState.activeTools.length > 0) return "build"
        if (sessionState.isThinking) return "psychology"
        if (sessionState.lastStopReason === "end_turn") return "check_circle"
        return "smart_toy"
    }

    function isWorking() {
        return isActive && (sessionState.isThinking || sessionState.activeTools.length > 0)
    }

    // Horizontal bar pill
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: root.getStatusIcon()
                size: Theme.barIconSize(root.barThickness)
                color: root.isWorking() ? root.sourceColor : Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.getStatusText()
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig ? root.barConfig.fontScale : undefined)
                color: root.isWorking() ? root.sourceColor : Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }

        }
    }

    // Vertical bar pill
    verticalBarPill: Component {
        Column {
            spacing: 2

            DankIcon {
                name: root.getStatusIcon()
                size: Theme.barIconSize(root.barThickness)
                color: root.isWorking() ? root.sourceColor : Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Popout content
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Agent Notch"
            detailsText: {
                var parts = []
                if (root.sessionState.model) parts.push(root.sessionState.model)
                if (root.sessionState.gitBranch) parts.push(root.sessionState.gitBranch)
                return parts.join(" \u2022 ")
            }
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Status
                StyledRect {
                    width: parent.width
                    height: statusRow.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: statusRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        Rectangle {
                            width: 12
                            height: 12
                            radius: 6
                            color: root.isWorking() ? root.sourceColor : Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                text: root.getStatusText()
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: root.isWorking() ? root.sourceColor : Theme.surfaceText
                            }

                            StyledText {
                                text: {
                                    if (root.sessionState.cwd) {
                                        var parts = root.sessionState.cwd.split("/")
                                        return parts[parts.length - 1] || root.sessionState.cwd
                                    }
                                    return "No active session"
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }

                // Token usage
                StyledRect {
                    width: parent.width
                    height: tokenColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: Parser.getTotalTokens(root.sessionState.tokenUsage) > 0

                    Column {
                        id: tokenColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Token usage"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Row {
                            id: tokenRow
                            width: parent.width
                            spacing: 0

                            property int visibleCount: {
                                var c = 2
                                if (root.sessionState.tokenUsage.cacheReadInputTokens > 0) c++
                                if (root.sessionState.tokenUsage.cacheCreationInputTokens > 0) c++
                                return c
                            }

                            Column {
                                width: tokenRow.width / tokenRow.visibleCount
                                spacing: 2
                                StyledText {
                                    text: Parser.formatTokenCount(root.sessionState.tokenUsage.inputTokens)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    text: "Input"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }

                            Column {
                                width: tokenRow.width / tokenRow.visibleCount
                                spacing: 2
                                StyledText {
                                    text: Parser.formatTokenCount(root.sessionState.tokenUsage.outputTokens)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    text: "Output"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }

                            Column {
                                width: tokenRow.width / tokenRow.visibleCount
                                spacing: 2
                                visible: root.sessionState.tokenUsage.cacheReadInputTokens > 0
                                StyledText {
                                    text: Parser.formatTokenCount(root.sessionState.tokenUsage.cacheReadInputTokens)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: "#4CAF50"
                                }
                                StyledText {
                                    text: "Cache read"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }

                            Column {
                                width: tokenRow.width / tokenRow.visibleCount
                                spacing: 2
                                visible: root.sessionState.tokenUsage.cacheCreationInputTokens > 0
                                StyledText {
                                    text: Parser.formatTokenCount(root.sessionState.tokenUsage.cacheCreationInputTokens)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: "#FFC107"
                                }
                                StyledText {
                                    text: "Cache write"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }

                        StyledText {
                            text: {
                                var cost = Parser.estimateCost(root.sessionState.tokenUsage)
                                return "Estimated cost: " + Parser.formatCost(cost)
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            visible: root.showCost
                        }
                    }
                }

                // Recent tools
                StyledRect {
                    width: parent.width
                    height: recentToolsColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.sessionState.recentTools.length > 0

                    Column {
                        id: recentToolsColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Recent tools"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Repeater {
                            model: root.sessionState.recentTools

                            Item {
                                width: recentToolsColumn.width
                                height: toolNameText.implicitHeight

                                DankIcon {
                                    id: toolIcon
                                    name: Parser.getToolIcon(modelData.toolName)
                                    size: Theme.iconSize - 6
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                }

                                StyledText {
                                    id: toolNameText
                                    text: Parser.getToolDisplayName(modelData.toolName)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: toolIcon.right
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.right: toolElapsed.left
                                    anchors.rightMargin: Theme.spacingS
                                }

                                StyledText {
                                    id: toolElapsed
                                    text: {
                                        if (modelData.endTime && modelData.startTime) {
                                            var ms = modelData.endTime - modelData.startTime
                                            if (ms < 1000) return ms + "ms"
                                            return (ms / 1000).toFixed(1) + "s"
                                        }
                                        return ""
                                    }
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                }
                            }
                        }
                    }
                }

                // Footer
                Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    Row {
                        spacing: Theme.spacingXS
                        visible: root.sessionState.gitBranch.length > 0

                        DankIcon {
                            name: "commit"
                            size: Theme.iconSize - 8
                            color: "#9C27B0"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: root.sessionState.gitBranch
                            font.pixelSize: Theme.fontSizeSmall
                            color: "#9C27B0"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        spacing: Theme.spacingXS
                        visible: Parser.getTotalTokens(root.sessionState.tokenUsage) > 0

                        DankIcon {
                            name: "token"
                            size: Theme.iconSize - 8
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: Parser.formatTokenCount(Parser.getTotalTokens(root.sessionState.tokenUsage))
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}
