import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "agentNotch"

    StyledText {
        width: parent.width
        text: "Agent Notch"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Real-time AI coding assistant telemetry for your DankBar. Monitors Claude Code JSONL session files and displays tool calls, thinking state, and token usage."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "pollInterval"
        label: "Poll interval"
        description: "How often to check for new session data (seconds)"
        defaultValue: 3
        minimum: 1
        maximum: 15
        unit: "s"
        leftIcon: "schedule"
    }

    ToggleSetting {
        settingKey: "showToolName"
        label: "Show tool name"
        description: "Display the current tool name in the bar"
        defaultValue: true
        leftIcon: "build"
    }

    ToggleSetting {
        settingKey: "showTokens"
        label: "Show token count"
        description: "Display total token count in the bar"
        defaultValue: true
        leftIcon: "token"
    }

    StyledText {
        width: parent.width
        text: "No additional setup needed. Agent Notch automatically detects Claude Code sessions in ~/.claude/projects/."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
