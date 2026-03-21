// ClaudeParser.js - JSONL parsing logic for Claude Code sessions
// Ported from AgentNotch (macOS Swift) to JavaScript for DankMaterialShell

// State object for a Claude Code session
function createSessionState() {
    return {
        sessionId: "",
        cwd: "",
        gitBranch: "",
        model: "",
        isThinking: false,
        isConnected: false,
        lastStopReason: null,
        needsPermission: false,
        pendingPermissionTool: null,
        activeTools: [],
        recentTools: [],
        todos: [],
        tokenUsage: {
            inputTokens: 0,
            outputTokens: 0,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0
        },
        lastUpdateTime: 0,
        lastMessage: "",
        lastMessageTime: 0
    };
}

// Tools that typically require permission approval
var permissionEligibleTools = [
    "Bash", "Edit", "Write", "NotebookEdit",
    "mcp__", "computer"
];

function isPermissionEligible(toolName) {
    for (var i = 0; i < permissionEligibleTools.length; i++) {
        if (toolName.indexOf(permissionEligibleTools[i]) === 0) {
            return true;
        }
    }
    return false;
}

// Parse a single JSONL line and update session state
// Returns the updated state object
function parseJSONLLine(line, state) {
    if (!line || line.trim().length === 0) {
        return state;
    }

    var json;
    try {
        json = JSON.parse(line);
    } catch (e) {
        return state;
    }

    // Extract top-level session metadata
    if (json.sessionId) {
        state.sessionId = json.sessionId;
    }
    if (json.cwd) {
        state.cwd = json.cwd;
    }
    if (json.gitBranch) {
        state.gitBranch = json.gitBranch;
    }

    // Check for interruption in toolUseResult
    if (json.toolUseResult !== undefined) {
        var resultStr = String(json.toolUseResult);
        if (resultStr.indexOf("interrupted by user") !== -1 || resultStr.indexOf("Request interrupted") !== -1) {
            state.isThinking = false;
            state.lastStopReason = "interrupted";
            state.activeTools = [];
            state.needsPermission = false;
            state.pendingPermissionTool = null;
        }
    }

    // Check top-level type for user messages (rejections)
    if (json.type === "user" && json.message && json.message.content) {
        var content = json.message.content;
        if (Array.isArray(content)) {
            for (var ci = 0; ci < content.length; ci++) {
                var item = content[ci];
                if (item.type === "tool_result" && typeof item.content === "string") {
                    if (item.content.indexOf("interrupted") !== -1 || item.content.indexOf("rejected") !== -1) {
                        state.isThinking = false;
                        state.lastStopReason = "interrupted";
                        state.activeTools = [];
                    }
                }
            }
        }
    }

    // Parse todos from top-level
    if (json.todos && Array.isArray(json.todos)) {
        state.todos = parseTodos(json.todos);
    }

    // Parse message
    if (json.message) {
        parseMessage(json.message, state);
    }

    state.lastUpdateTime = Date.now();
    return state;
}

function parseMessage(message, state) {
    if (message.model) {
        state.model = message.model;
    }

    // Track stop_reason for session completion
    if (message.stop_reason) {
        state.lastStopReason = message.stop_reason;
        if (message.stop_reason === "end_turn") {
            state.isThinking = false;
        }
    }

    // Role detection
    if (message.role === "user" || message.role === "assistant") {
        state.isThinking = true;
        state.lastStopReason = null;
    }

    // Parse usage for token tracking
    if (message.usage) {
        var usage = message.usage;
        if (usage.input_tokens !== undefined) {
            state.tokenUsage.inputTokens = usage.input_tokens;
        }
        if (usage.output_tokens !== undefined) {
            state.tokenUsage.outputTokens = usage.output_tokens;
        }
        if (usage.cache_read_input_tokens !== undefined) {
            state.tokenUsage.cacheReadInputTokens = usage.cache_read_input_tokens;
        }
        if (usage.cache_creation_input_tokens !== undefined) {
            state.tokenUsage.cacheCreationInputTokens = usage.cache_creation_input_tokens;
        }
    }

    // Parse content array
    if (message.content && Array.isArray(message.content)) {
        for (var i = 0; i < message.content.length; i++) {
            var item = message.content[i];
            if (!item.type) continue;

            switch (item.type) {
            case "thinking":
                // Post-tool thinking = completing, not actively thinking
                if (state.activeTools.length === 0 && state.recentTools.length > 0) {
                    state.isThinking = false;
                } else {
                    state.isThinking = true;
                }
                break;

            case "text":
                // Text after tools = final response
                if (state.activeTools.length === 0 && state.recentTools.length > 0) {
                    state.isThinking = false;
                }
                if (item.text) {
                    // Store last message preview
                    var lines = item.text.split("\n");
                    state.lastMessage = (lines[0] || item.text).substring(0, 100);
                    state.lastMessageTime = Date.now();

                    // Detect interruption
                    if (item.text.indexOf("[Request interrupted by user") !== -1) {
                        state.isThinking = false;
                        state.lastStopReason = "interrupted";
                        state.activeTools = [];
                        state.needsPermission = false;
                        state.pendingPermissionTool = null;
                    }
                }
                break;

            case "tool_use":
                // Tool use = thinking done, now acting
                state.isThinking = false;

                if (item.id && item.name) {
                    var toolDescription = null;
                    var toolTimeout = null;

                    if (item.input) {
                        toolDescription = item.input.description || null;
                        toolTimeout = item.input.timeout || null;
                    }

                    // Parse TodoWrite tool
                    if (item.name === "TodoWrite" && item.input && item.input.todos) {
                        state.todos = parseTodos(item.input.todos);
                    }

                    // Check if tool already tracked
                    var alreadyTracked = false;
                    for (var t = 0; t < state.activeTools.length; t++) {
                        if (state.activeTools[t].id === item.id) {
                            alreadyTracked = true;
                            break;
                        }
                    }

                    if (!alreadyTracked) {
                        state.activeTools.push({
                            id: item.id,
                            toolName: item.name,
                            argument: extractToolArgument(item.input),
                            description: toolDescription,
                            timeout: toolTimeout,
                            startTime: Date.now(),
                            endTime: null,
                            inputTokens: null,
                            outputTokens: null,
                            cacheReadTokens: null,
                            cacheWriteTokens: null
                        });
                    }
                }
                break;
            }
        }
    }

    // Handle tool_result in user messages
    if (message.role === "user" && message.content && Array.isArray(message.content)) {
        for (var j = 0; j < message.content.length; j++) {
            var resultItem = message.content[j];
            if (resultItem.type === "tool_result" && resultItem.tool_use_id) {
                var toolId = resultItem.tool_use_id;

                // Move tool from active to recent
                for (var k = state.activeTools.length - 1; k >= 0; k--) {
                    if (state.activeTools[k].id === toolId) {
                        var completedTool = state.activeTools.splice(k, 1)[0];
                        completedTool.endTime = Date.now();
                        completedTool.inputTokens = state.tokenUsage.inputTokens;
                        completedTool.outputTokens = state.tokenUsage.outputTokens;
                        completedTool.cacheReadTokens = state.tokenUsage.cacheReadInputTokens;
                        completedTool.cacheWriteTokens = state.tokenUsage.cacheCreationInputTokens;

                        state.recentTools.unshift(completedTool);
                        if (state.recentTools.length > 15) {
                            state.recentTools.pop();
                        }
                        break;
                    }
                }

                state.isThinking = true;
            }
        }
    }
}

function parseTodos(todosArray) {
    var result = [];
    for (var i = 0; i < todosArray.length; i++) {
        var todo = todosArray[i];
        if (todo.content && todo.status) {
            result.push({
                content: todo.content,
                status: todo.status
            });
        }
    }
    return result;
}

function extractToolArgument(input) {
    if (!input) return "";

    // For common tools, extract the most relevant argument
    if (input.command) return input.command;
    if (input.file_path) return input.file_path;
    if (input.pattern) return input.pattern;
    if (input.query) return input.query;
    if (input.url) return input.url;
    if (input.prompt) return String(input.prompt).substring(0, 80);
    if (input.description) return input.description;

    // Fallback: stringify first key
    var keys = Object.keys(input);
    if (keys.length > 0) {
        var val = input[keys[0]];
        if (typeof val === "string") return val.substring(0, 80);
    }
    return "";
}

// Format token count with K/M suffix
function formatTokenCount(count) {
    if (count >= 1000000) {
        return (count / 1000000).toFixed(1) + "M";
    }
    if (count >= 1000) {
        return (count / 1000).toFixed(1) + "K";
    }
    return String(count);
}

// Calculate estimated cost based on Claude model pricing
function estimateCost(usage) {
    // Claude Sonnet 4 pricing (per 1M tokens)
    var inputPricePer1M = 3.0;
    var outputPricePer1M = 15.0;
    var cacheReadPricePer1M = 0.30;
    var cacheWritePricePer1M = 3.75;

    var inputCost = (usage.inputTokens / 1000000) * inputPricePer1M;
    var outputCost = (usage.outputTokens / 1000000) * outputPricePer1M;
    var cacheReadCost = (usage.cacheReadInputTokens / 1000000) * cacheReadPricePer1M;
    var cacheWriteCost = (usage.cacheCreationInputTokens / 1000000) * cacheWritePricePer1M;

    return inputCost + outputCost + cacheReadCost + cacheWriteCost;
}

// Format cost as dollar string
function formatCost(cost) {
    if (cost < 0.01) {
        return "$" + cost.toFixed(4);
    }
    if (cost < 1.0) {
        return "$" + cost.toFixed(3);
    }
    return "$" + cost.toFixed(2);
}

// Format elapsed time
function formatElapsed(startTimeMs) {
    if (!startTimeMs) return "";
    var elapsed = Math.floor((Date.now() - startTimeMs) / 1000);
    if (elapsed < 60) return elapsed + "s";
    var mins = Math.floor(elapsed / 60);
    var secs = elapsed % 60;
    if (mins < 60) return mins + "m " + secs + "s";
    var hours = Math.floor(mins / 60);
    mins = mins % 60;
    return hours + "h " + mins + "m";
}

// Get a short display name for a tool
function getToolDisplayName(toolName) {
    // Strip common prefixes
    if (toolName.indexOf("mcp__") === 0) {
        var parts = toolName.split("__");
        return parts[parts.length - 1] || toolName;
    }
    return toolName;
}

// Get icon name for a tool type
function getToolIcon(toolName) {
    switch (toolName) {
    case "Read": return "description";
    case "Edit": return "edit";
    case "Write": return "edit_note";
    case "Bash": return "terminal";
    case "Glob": return "search";
    case "Grep": return "manage_search";
    case "WebFetch": return "language";
    case "WebSearch": return "travel_explore";
    case "Agent": return "smart_toy";
    case "TodoWrite": return "checklist";
    case "NotebookEdit": return "code";
    case "AskUser": return "help";
    default:
        if (toolName.indexOf("mcp__") === 0) return "extension";
        return "build";
    }
}

// Determine the project key from a path (same logic as AgentNotch)
// /home/user/project -> -home-user-project
function pathToProjectKey(path) {
    return path.replace(/\//g, "-");
}

// Get total tokens
function getTotalTokens(usage) {
    return usage.inputTokens + usage.outputTokens;
}

// Get context usage percentage
function getContextPercentage(usage, limit) {
    if (limit <= 0) return 0;
    var total = usage.inputTokens + usage.cacheReadInputTokens + usage.cacheCreationInputTokens;
    return Math.min(100, Math.round((total / limit) * 100));
}

// Get context bar color based on percentage
function getContextColor(percentage) {
    if (percentage < 50) return "#4CAF50";       // green
    if (percentage < 70) return "#FFC107";       // yellow
    if (percentage < 90) return "#FF9800";       // orange
    return "#F44336";                             // red
}
