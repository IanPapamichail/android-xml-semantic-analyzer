#!/bin/sh
# Regression tests for the analyzer.
#
#   tests/valid/*.xml      must be accepted (exit 0)
#   tests/invalid/*.xml    must be rejected (exit 1) with output identical to
#                          the matching .expected file
#   stress cases           generated on the fly to exercise unbounded input
#
# Usage: tests/run.sh path/to/analyzer

set -u

ANALYZER=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TESTS=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

echo "valid inputs"
cd "$TESTS/valid" || exit 2
for f in *.xml; do
    if "$ANALYZER" "$f" > "$TMP/out" 2>&1; then
        ok "$f"
    else
        bad "$f"; sed 's/^/        /' "$TMP/out"
    fi
done

echo "invalid inputs"
cd "$TESTS/invalid" || exit 2
for f in *.xml; do
    expected="${f%.xml}.expected"
    "$ANALYZER" "$f" > "$TMP/out" 2>&1
    status=$?
    if [ "$status" -ne 1 ]; then
        bad "$f (exit $status, expected 1)"
    elif ! diff -u "$expected" "$TMP/out" > "$TMP/diff"; then
        bad "$f"; sed 's/^/        /' "$TMP/diff"
    else
        ok "$f"
    fi
done

echo "stress inputs"
cd "$TMP" || exit 2

# 5000 unique ids, each 300 characters long (old limits: 1000 ids, 99 chars).
long=$(printf '%0300d' 0)
awk -v long="$long" 'BEGIN {
    print "<LinearLayout android:layout_width=\"match_parent\" android:layout_height=\"match_parent\">"
    for (i = 0; i < 5000; i++)
        printf "<View android:id=\"@+id/v%d_%s\" android:layout_width=\"1\" android:layout_height=\"1\"/>\n", i, long
    print "</LinearLayout>"
}' > many_long_ids.xml
if "$ANALYZER" many_long_ids.xml > out 2>&1; then
    ok "5000 unique 300-char ids"
else
    bad "5000 unique 300-char ids"; head -5 out | sed 's/^/        /'
fi

# The same ids plus one duplicate of the very first: exactly one error expected.
sed '$d' many_long_ids.xml > dup_long_id.xml
printf '<View android:id="@+id/v0_%s" android:layout_width="1" android:layout_height="1"/>\n</LinearLayout>\n' "$long" >> dup_long_id.xml
"$ANALYZER" dup_long_id.xml > out 2>&1
if [ $? -eq 1 ] && grep -q "duplicate android:id 'v0_$long' (first declared at line 2)" out \
               && grep -q ': 1 error$' out; then
    ok "duplicate detected among 5000 long ids"
else
    bad "duplicate detected among 5000 long ids"; head -5 out | cut -c1-120 | sed 's/^/        /'
fi

# A RadioGroup with 500 buttons (old limit: 100) and checkedButton on the last.
awk 'BEGIN {
    print "<RadioGroup android:layout_width=\"wrap_content\" android:layout_height=\"wrap_content\""
    print "    android:checkedButton=\"@id/rb499\" android:count=\"500\">"
    for (i = 0; i < 500; i++)
        printf "<RadioButton android:id=\"@+id/rb%d\" android:layout_width=\"wrap_content\" android:layout_height=\"wrap_content\"/>\n", i
    print "</RadioGroup>"
}' > big_radio_group.xml
if "$ANALYZER" big_radio_group.xml > out 2>&1; then
    ok "RadioGroup with 500 buttons"
else
    bad "RadioGroup with 500 buttons"; head -5 out | sed 's/^/        /'
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
