## Commits and code style

- Never use Claude watermark in commits (FORBIDDEN: "Co-Authored-By")
- No emojis in commits or code
- One logical change per commit
- Keep commit messages concise (one line), use sentence case
- Use present tense in commits
- Always commit all files (git add -A)
- Always run `git status` after committing to verify nothing is left uncommitted
- Use sentence case for headings (not Title Case)
- Never use bold text as headings, use proper heading levels instead
- Always add an empty line after headings
- Do not ever use separators like ============================================================ or headings like === Something ===

## QML/JavaScript code style

- Use 4 spaces for indentation in QML and JavaScript
- Keep QML components modular and self-contained
- Use DMS theme variables (Theme.primary, Theme.surfaceText, etc.) instead of hardcoded colors where possible
- Use DMS widget components (DankIcon, StyledText, StyledRect, DankButton, DankToggle, DankTextField) for consistency
- Follow DMS plugin patterns: PluginComponent for widgets, PluginSettings for settings
- Keep JavaScript logic in ClaudeParser.js, QML should focus on UI binding
- Prefer property bindings over imperative updates in QML
- Use Process + SplitParser for shell command execution, never block the UI thread

## Claude Code workflow

- ALWAYS use Helsinki timezone (Europe/Helsinki) for all timestamps
- NEVER add Finnish language in anywhere unless the feature requires it
- NEVER unsolicited clean up, replace, or wipe data/words from files
- NEVER cap with artificial limits or truncate as a "solution"
- Always add tasks to the Claude Code to-do list and keep it up to date
- Review your to-do list and prioritize before starting
- Do not ever guess features, always proof them via looking up official docs, GitHub code, issues, if possible
- NEVER just patch the line you see. Before fixing, trace the full chain
- Prefer DRY code - avoid repeating logic, extract shared patterns

## Project structure

- `plugin.json` - DMS plugin manifest
- `AgentNotchWidget.qml` - Main widget component (bar pill + popout)
- `AgentNotchSettings.qml` - Settings UI
- `ClaudeParser.js` - JSONL parsing logic ported from AgentNotch
- `README.md` - Documentation
