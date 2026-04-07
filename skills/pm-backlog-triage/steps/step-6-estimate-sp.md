# Step 6: Estimate Missing SP → /tmp/sp-log.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/sp-log.txt

# Reuse backlog from Step 2 — ClickUp returns SP as a STRING; coerce before compare
jq '[.[] | select((.sp|tostring) == "0" or (.sp|tostring) == "" or .sp == null)
       | {id, name: .name[0:60], tags}]' \
  /tmp/cu-backlog.json > /tmp/no-sp.json

TOTAL=$(jq length /tmp/no-sp.json)
echo "Tasks missing SP: $TOTAL" | tee /tmp/sp-log.txt
COUNT=0; MAX=50

for row in $(jq -r '.[] | @base64' /tmp/no-sp.json); do
  [ $COUNT -ge $MAX ] && break
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  NAME=$(echo "$row"|base64 -d|jq -r '.name')
  TAGS=$(echo "$row"|base64 -d|jq -r '.tags|join(",")')

  # SP estimation heuristic — first match wins, no overwrites
  SP=2  # default
  case "$TAGS" in
    *security*|*compliance*) SP=8;;
    *bug*)
      if echo "$NAME" | grep -qiE "critical|crash|data.loss"; then SP=8; else SP=5; fi;;
    *feature*|*enhancement*)
      if   echo "$NAME" | grep -qiE "refactor|rewrite|migrate|redesign"; then SP=21
      elif echo "$NAME" | grep -qiE "add|create|new|implement";          then SP=13
      else SP=5; fi;;
    *infra*|*ci*|*config*) SP=3;;
  esac

  cu_api POST "task/$ID/field/$SP_FIELD_ID" "{\"value\":$SP}" > /dev/null
  echo "SP: $NAME → ${SP}" >> /tmp/sp-log.txt
  COUNT=$((COUNT+1)); sleep 0.2
done

echo "SP set: $COUNT" >> /tmp/sp-log.txt
tail -5 /tmp/sp-log.txt
```
