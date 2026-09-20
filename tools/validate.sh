#!/usr/bin/env bash
# Validate this extension mod against a real base ruleset.
#
# Running `mod-ci` on an extension mod on its own validates it in ISOLATION, so
# every name inherited from the base game (Rifleman, Nuclear Fission, Melee...)
# is reported as "does not fit parameter type". Those are false alarms and they
# drown the real findings.
#
# This script does what avoiding them requires: extracts Civ V - Gods & Kings
# out of Unciv.jar, merges this mod's entries into it, marks the result a base
# ruleset, and runs mod-ci on that. Findings about your own content are then
# real — and this is the ONLY check that catches bad unique *text*, because the
# JSON schema's Uniques type is just `string`.
#
# Usage:  bash tools/validate.sh
set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAR="${UNCIV_JAR:-C:/Users/sw/OneDrive/Desktop/Unciv/Unciv.jar}"
RULESET="Civ V - Gods & Kings"

[ -f "$JAR" ] || { echo "Unciv.jar not found at: $JAR"; echo "Set UNCIV_JAR to override."; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

unzip -q -o "$JAR" "jsons/$RULESET/*" -d "$WORK"
[ -d "$WORK/jsons/$RULESET" ] || { echo "Could not extract '$RULESET' from the jar."; exit 1; }

# mod-ci expects a mod folder containing a 'jsons' subfolder, so build one.
MERGED="$WORK/merged"
BASE="$MERGED/jsons"
mkdir -p "$BASE"
mv "$WORK/jsons/$RULESET"/*.json "$BASE/"

# Strip the outer [ ] from a JSON array file, as text.
# Done textually because the bundled rulesets use // comments and trailing
# commas, which a strict JSON parser rejects.
# Unciv's bundled json tolerates trailing commas, so strip any before splicing
# or the merge produces ",," and the parser dies.
inner_of() { awk 'BEGIN{RS="\0"}{sub(/^[[:space:]]*\[/,""); sub(/\][[:space:]]*$/,""); sub(/,[[:space:]]*$/,""); printf "%s", $0}' "$1"; }
without_close() { awk 'BEGIN{RS="\0"}{sub(/\][[:space:]]*$/,""); sub(/,[[:space:]]*$/,""); printf "%s", $0}' "$1"; }

merged=0
for f in "$MOD_DIR"/jsons/*.json; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"

    # ModOptions is mod metadata; handled separately below so that its
    # uniques (Allow raze capital, ...) still get validated.
    if [ "$name" = "ModOptions.json" ]; then continue; fi

    # Skip files that are empty or hold only an empty array/object.
    stripped="$(tr -d '[:space:]' < "$f")"
    if [ -z "$stripped" ] || [ "$stripped" = "[]" ] || [ "$stripped" = "{}" ]; then
        echo "  skipped $name (empty)"
        continue
    fi

    if [ "$name" = "GlobalUniques.json" ]; then
        # An object, not an array. Replacing is enough to validate OUR uniques;
        # it drops vanilla's unhappiness uniques, which we aren't checking here.
        cp "$f" "$BASE/$name"
        echo "  replaced $name"
    elif [ -f "$BASE/$name" ]; then
        { without_close "$BASE/$name"; printf ',\n'; inner_of "$f"; printf '\n]\n'; } > "$BASE/$name.new"
        mv "$BASE/$name.new" "$BASE/$name"
        echo "  merged into $name"
    else
        cp "$f" "$BASE/$name"
        echo "  added $name"
    fi
    merged=$((merged+1))
done

# Carry the mod's own ModOptions uniques through, so things like
# "Allow raze capital" are validated rather than silently skipped.
MO="$MOD_DIR/jsons/ModOptions.json"
if [ -f "$MO" ] && grep -q '"uniques"' "$MO"; then
    python -c "
import json,sys
u = json.load(open(sys.argv[1], encoding='utf-8')).get('uniques', [])
json.dump({'isBaseRuleset': True, 'uniques': u}, open(sys.argv[2],'w',encoding='utf-8'), indent=4)
print('  carried %d ModOptions unique(s)' % len(u))
" "$MO" "$BASE/ModOptions.json"
else
    echo '{"isBaseRuleset": true}' > "$BASE/ModOptions.json"
fi
cp "$JAR" "$MERGED/Unciv.jar"

echo
echo "Merged $merged file(s) into $RULESET. Running mod-ci:"
echo "------------------------------------------------------------"
cd "$MERGED"
# mod-ci exits non-zero when it reports findings; show them rather than abort.
# Noise filtered out, all of it from vanilla or from running headless:
#   ^OK:            vanilla's own translation-collision notices
#   ImageGetter     NullPointerException spam — no graphics context in mod-ci
#   Tutorial Task:  vanilla's tutorial events referencing images we didn't extract
#   AtlasPreview    always empty here
out="$(java -jar Unciv.jar mod-ci 2>&1 \
       | grep -viE "^Loaded |AtlasPreview|^OK: |ImageGetter|Tutorial Task:" || true)"
if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
    echo "No findings. Everything resolves."
else
    printf '%s\n' "$out"
fi
echo "------------------------------------------------------------"
echo "Anything above naming YOUR objects or uniques is a real finding."
