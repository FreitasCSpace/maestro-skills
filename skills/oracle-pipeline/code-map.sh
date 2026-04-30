#!/bin/bash
# code-map.sh — Lightweight structure map for any source file
# Shows functions, classes, exports, CSS selectors with line numbers
# Usage: bash code-map.sh path/to/file.tsx
#
# Output example:
#   12-45   function handleSubmit(...)
#   47-89   const UserCard: React.FC = ...
#   91-120  export default UserDashboard
#
# The pipeline agent reads this BEFORE reading the file,
# then uses Read with offset/limit on just the section it needs.

FILE="$1"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "Usage: bash code-map.sh <file>"
  exit 1
fi

EXT="${FILE##*.}"
LINES=$(wc -l < "$FILE")
echo "=== $FILE ($LINES lines, .$EXT) ==="

case "$EXT" in
  # TypeScript / JavaScript / JSX / TSX
  ts|tsx|js|jsx|mjs|cjs)
    grep -n \
      -e '^export ' \
      -e '^export default ' \
      -e '^const [A-Z]' \
      -e '^function ' \
      -e '^async function ' \
      -e '^class ' \
      -e '^interface ' \
      -e '^type ' \
      -e '^enum ' \
      -e '^\s*const [A-Z].*=.*=>' \
      -e '^\s*export const ' \
      -e '^\s*export function ' \
      -e '^\s*export default ' \
      -e '^\s*export interface ' \
      -e '^\s*export type ' \
      -e '^\s*export enum ' \
      -e '^\s*export class ' \
      "$FILE" 2>/dev/null
    ;;

  # CSS / SCSS / LESS
  css|scss|less|module.css)
    # Show CSS custom property blocks, selectors, and @-rules
    grep -n \
      -e '^:root' \
      -e '^\.' \
      -e '^#' \
      -e '^@media' \
      -e '^@keyframes' \
      -e '^@layer' \
      -e '^@import' \
      -e '^\[data-' \
      -e '^body' \
      -e '^html' \
      -e '^--[a-z]' \
      -e '^\s*--font' \
      -e '^\s*--color' \
      -e '^\s*--spacing' \
      -e '^\s*--radius' \
      -e '^\s*--shadow' \
      "$FILE" 2>/dev/null
    ;;

  # Python
  py)
    grep -n \
      -e '^class ' \
      -e '^def ' \
      -e '^async def ' \
      -e '^\s\+def ' \
      -e '^\s\+async def ' \
      -e '^@' \
      "$FILE" 2>/dev/null
    ;;

  # Go
  go)
    grep -n \
      -e '^func ' \
      -e '^type .* struct' \
      -e '^type .* interface' \
      -e '^package ' \
      "$FILE" 2>/dev/null
    ;;

  # Java / Kotlin
  java|kt|kts)
    grep -n \
      -e '^public ' \
      -e '^private ' \
      -e '^protected ' \
      -e '^class ' \
      -e '^interface ' \
      -e '^abstract ' \
      -e '^fun ' \
      -e '^\s*fun ' \
      -e '^data class ' \
      -e '^sealed ' \
      -e '^object ' \
      "$FILE" 2>/dev/null
    ;;

  # Dart
  dart)
    grep -n \
      -e '^class ' \
      -e '^abstract ' \
      -e '^mixin ' \
      -e '^\s\+@override' \
      -e '^\s\+void ' \
      -e '^\s\+Future' \
      -e '^\s\+Widget build' \
      "$FILE" 2>/dev/null
    ;;

  # HTML / Vue / Svelte
  html|vue|svelte)
    grep -n \
      -e '<template' \
      -e '<script' \
      -e '<style' \
      -e '<section' \
      -e '<header' \
      -e '<footer' \
      -e '<main' \
      -e '<nav' \
      -e 'id="' \
      -e 'class="' \
      "$FILE" 2>/dev/null | head -40
    ;;

  # Fallback — show any function/class-like patterns
  *)
    grep -n \
      -e '^function ' \
      -e '^class ' \
      -e '^def ' \
      -e '^pub ' \
      -e '^impl ' \
      -e '^struct ' \
      -e '^enum ' \
      -e '^module ' \
      "$FILE" 2>/dev/null
    ;;
esac

echo "=== END ==="
