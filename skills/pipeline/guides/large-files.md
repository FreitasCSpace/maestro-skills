# Handling Large Files

The Read tool has a **10,000 token limit** (hardcoded in Claude Code).
Large CSS, config, and data files WILL fail with "File content exceeds
maximum allowed tokens". **DO NOT give up or skip the file.**

## Preferred: Serena MCP tools (if available)

Search your tools for "serena". If available:

- **`get_symbols_overview`** — all symbols in a file with line ranges
- **`find_symbol`** — find a function/class/variable by name, returns source
- **`replace_symbol_body`** — edit by symbol name, no string matching needed
- **`find_referencing_symbols`** — find all callers/importers
- **`rename_symbol`** — LSP rename across all references

Serena eliminates both the Read limit AND the Edit uniqueness problem.

## Fallback 1: code-map + offset/limit

```bash
bash ~/.claude/skills/pipeline/code-map.sh path/to/file.tsx
```

This shows functions, classes, CSS selectors with line numbers. Then:

```
Read tool → file_path: path/to/file.css, offset: 550, limit: 50
```

## Fallback 2: grep + sed

```bash
grep -n "font-size-base" path/to/file.css    # find line number
sed -i 's/old-value/new-value/' path/to/file.css  # replace it
```

## Fallback 3: cat via Bash

The Bash tool has NO token limit:
```bash
cat path/to/large-file.css
```

**NEVER skip a file because it's too large.** There is always a way to read it.
