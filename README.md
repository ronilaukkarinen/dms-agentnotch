<h1 align="center">Agent Notch</h1>

<p align="center">
  <strong>Real-time AI coding assistant telemetry for DankMaterialShell</strong>
</p>

<p align="center">
  <a href="#features">Features</a> &bull;
  <a href="#installation">Installation</a> &bull;
  <a href="#configuration">Configuration</a> &bull;
  <a href="#how-it-works">How it works</a>
</p>

---

<img width="1201" height="459" alt="image" src="https://github.com/user-attachments/assets/0253cf84-c37c-4a34-8a38-45ed5ffa36fa" />

## What is Agent Notch?

Agent Notch is a DankMaterialShell plugin that brings real-time AI coding assistant telemetry to your DankBar. It monitors **Claude Code** sessions and displays what your AI assistant is doing at any moment &mdash; thinking, reading files, editing code, running commands &mdash; all without leaving your editor.

Ported from [AgentNotch](https://github.com/AppGram/agentnotch) (macOS) to the DMS plugin ecosystem.

## Features

### Real-time tool tracking

See every tool call as it happens &mdash; file reads, code edits, shell commands, web searches, and more. The bar pill shows the current tool name and an animated status indicator.

### Token and cost monitoring

Track input/output tokens, cache read/write tokens, and estimated session cost in real time. The popout shows a full breakdown with cache savings highlighted in green.

### Context progress bar

Visual progress bar showing how much of the context window has been used. Color-coded: green (&lt;50%), yellow (50-70%), orange (70-90%), red (&gt;90%).

### Permission detection

Automatically detects when Claude Code is waiting for permission approval (tools running &gt;2.5 seconds without completion). The indicator changes to a lock icon so you know to switch back to your terminal.

### Task tracking

Displays Claude Code's internal task list with pending/in-progress/completed status, so you can see what your AI assistant is planning.

### Lightweight and native

Runs as a standard DMS plugin &mdash; no background daemons, no OTLP server, no additional dependencies. Reads Claude Code's JSONL session files directly.

## Installation

### From DMS settings

Browse the plugin registry in DMS Settings and search for "Agent Notch".

### CLI

```bash
dms plugins install agentNotch
```

### Manual

Clone this repository into your DMS plugins directory:

```bash
git clone https://github.com/ronilaukkarinen/dms-agentnotch.git \
  ~/.config/DankMaterialShell/plugins/agentNotch
```

## Configuration

All settings are accessible from DMS Settings after installing the plugin.

| Setting | Default | Description |
|---------|---------|-------------|
| Show tool name | On | Display the current tool name in the bar pill |
| Show token count | On | Show total token count in the bar pill |
| Show estimated cost | Off | Show estimated cost in the bar pill |
| Show context progress | On | Show context window progress bar in popout |
| Poll interval | 3s | How often to check for new JSONL data |
| Context token limit | 200000 | Context window size for the progress bar |

## How it works

Agent Notch reads Claude Code's JSONL session files located in `~/.claude/projects/`. Every few seconds, it checks for new data appended to the most recently modified session file and parses the JSONL lines to extract:

- **Tool calls**: `tool_use` content blocks with tool name, arguments, and timing
- **Tool results**: `tool_result` messages that mark tool completion
- **Thinking state**: Detected from `role`, `content.type`, and `stop_reason` fields
- **Token usage**: From `message.usage` with input, output, cache read, and cache write tokens
- **Todos**: From `TodoWrite` tool calls
- **Session metadata**: Session ID, working directory, git branch, model name

No additional setup is required &mdash; if Claude Code is running, Agent Notch will find and monitor its sessions automatically.

## Bar pill states

| State | Icon | Color | Meaning |
|-------|------|-------|---------|
| Thinking | Psychology | Orange (pulsing) | Claude is processing/thinking |
| Tool running | Build | Orange (pulsing) | A tool is actively executing |
| Permission needed | Lock | Yellow | Claude is waiting for approval |
| Done | Check circle | Blue | Session completed normally |
| Interrupted | Cancel | Grey | Session was interrupted |
| Idle | Smart toy | Grey | No active session |

## Requirements

- DankMaterialShell
- Claude Code (the CLI tool from Anthropic)

## Privacy

Agent Notch runs 100% locally. It reads only local JSONL files on your machine and sends no data anywhere.

## Credits

Ported from [AgentNotch](https://github.com/AppGram/agentnotch) by AppGram, originally a macOS Swift app for the Mac notch area.

