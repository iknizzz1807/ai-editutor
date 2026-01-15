# LLM Payload Snapshots

This directory contains documentation of what gets sent to the LLM for different code scenarios.

## Purpose

Each snapshot file documents the complete flow:

```
INPUT                           OUTPUT
─────                           ──────
Source file                 →   System prompt
Q: comment location         →   User prompt
Related files               →   Context extracted
Cursor position             →   Expected response location
```

## Snapshot Files

| File | Language | Scenario |
|------|----------|----------|
| [typescript-useauth.md](typescript-useauth.md) | TypeScript | React hook with async cleanup question |
| [python-serializer.md](python-serializer.md) | Python | Django serializer with race condition question |
| [go-repository.md](go-repository.md) | Go | GORM repository with pagination question |

## Snapshot Format

Each markdown file contains:

### 1. Input Section
- Source file path and filetype
- Line number of Q: comment
- Related files in the project

### 2. Context Extraction Section
- Imports detected
- Current function (if applicable)
- Code context (±50 lines around question)
- `>>>` marker shows the question line

### 3. LLM Payload Section
- **System Prompt**: Instructions for the AI mentor
- **User Prompt**: Context + question sent to LLM

### 4. Expected Response Section
- Where the response will be inserted
- Example of formatted response as inline comment

## Validation

Run the snapshot tests to verify actual output matches documentation:

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/snapshot_spec.lua"
```

## Generating New Snapshots

Use the generator script to create snapshot data:

```bash
nvim --headless -u tests/minimal_init.lua -c "luafile tests/generate_snapshots.lua" -c "q"
```

Then create a new markdown file following the existing format.

## Why Snapshots?

1. **Documentation**: Clear record of what LLM receives
2. **Testing**: Validate context extraction works correctly
3. **Debugging**: When responses are wrong, check if context is correct
4. **Onboarding**: New contributors understand the data flow
