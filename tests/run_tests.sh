#!/bin/bash
#
# Regression test for the Morpheus cruncher and build pipeline.
#
# Usage:
#   tests/run_tests.sh           Run tests, comparing against baselines.
#   tests/run_tests.sh --update  Regenerate baselines from current state.
#
# Baseline files (tests/*_expected.txt, tests/*_probe_*.txt, etc.) are not
# tracked in git.  If baselines exist, this script compares against them and
# shows diffs, but a diff alone does not count as a failure -- only crashes
# and build errors do.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CRUNCHER="$PROJECT_DIR/bin/cruncher"
UPDATE=0

if [ "$1" = "--update" ]; then
    UPDATE=1
fi

if [ ! -x "$CRUNCHER" ]; then
    echo "FAIL: cruncher not found (run 'make' first)"
    exit 1
fi

export MORPHLIB="$PROJECT_DIR/stemlib"
export PATH="$PROJECT_DIR/bin:$PATH"

FAILURES=0
DIFFS=0

# ── Test matrix ──────────────────────────────────────────────────────────
#
# Each entry: label, cruncher flags, input word list, baseline file.
# Adding a test here is all that is needed -- both test and baseline
# generation use this table.

run_cruncher_test() {
    local label="$1" flags="$2" words="$3" baseline="$4"

    if [ "$UPDATE" -eq 1 ]; then
        "$CRUNCHER" $flags < "$words" > "$baseline" 2>/dev/null
        return
    fi

    if ! "$CRUNCHER" $flags < "$words" > /tmp/morpheus_test_$$.txt 2>/dev/null; then
        echo "FAIL: $label (cruncher crashed)"
        rm -f /tmp/morpheus_test_$$.txt
        FAILURES=$((FAILURES + 1))
        return
    fi

    if [ ! -f "$baseline" ]; then
        echo "SKIP: $label (no baseline; run $0 --update)"
        rm -f /tmp/morpheus_test_$$.txt
        return
    fi

    if diff -u "$baseline" /tmp/morpheus_test_$$.txt > /dev/null 2>&1; then
        echo "PASS: $label"
    else
        echo "DIFF: $label"
        diff -u "$baseline" /tmp/morpheus_test_$$.txt | head -40
        DIFFS=$((DIFFS + 1))
    fi
    rm -f /tmp/morpheus_test_$$.txt
}

run_assert_test() {
    local flags="$1" file="$2"
    [ -f "$file" ] || return
    
    local filename
    filename=$(basename "$file")
    echo "=== Assertions: $filename ==="
    
    # AWK: Group lemmas, skip comments, chop '(', and handle "" for empty sets
    local aggregated
    aggregated=$(awk '/^#|^$/ {next} {
        
        # 1. Ignore everything from "(" to the end of the line
        sub(/\(.*/, "")
        
        if (NF < 2) next
        
        word = $1
        if (!(word in map)) {
            order[++count] = word
            map[word] = "" # Initialize empty in case it is just ""
        }
        for(i=2; i<=NF; i++) {
            # Skip arrow and our empty set marker
            if ($i == "->") continue
            if ($i == "\"\"") continue
            
            map[word] = map[word] " " $i
        }
    } END {
        for(i=1; i<=count; i++) {
            print order[i] map[order[i]]
        }
    }' "$file")

    # Loop through the grouped data
    while read -r form expected_str; do
        [ -z "$form" ] && continue
        
        # Get actual output, remove 'form:', sort alphabetically, format as one line
        actual=$(echo "$form" | "$CRUNCHER" $flags 2>/dev/null | grep -v '^form:' | sort | tr '\n' ' ' | sed 's/ *$//')
        
        # Format the expected string (sort alphabetically and remove duplicates)
        expected=$(echo "$expected_str" | tr ' ' '\n' | sort | uniq | tr '\n' ' ' | sed 's/ *$//')
        
        # Format for display so empty strings show up as "" in the terminal logs
        disp_expected=${expected:-\"\"}
        disp_actual=${actual:-\"\"}
        
        if [ "$actual" = "$expected" ]; then
            echo "PASS: '$form' -> $disp_expected"
        else
            echo "FAIL: $form"
            echo "      expected: [$disp_expected]"
            echo "      got:      [$disp_actual]"
            FAILURES=$((FAILURES + 1))
        fi
    done <<< "$aggregated"
    echo ""
}

for assert_file in "$SCRIPT_DIR"/latin_assertions*.txt; do
    run_assert_test "-Ll" "$assert_file"
done
GP="$SCRIPT_DIR/greek_probe.txt"
LP="$SCRIPT_DIR/latin_probe.txt"

# Main cruncher tests (full word lists)
run_cruncher_test "Greek cruncher" "" \
    "$SCRIPT_DIR/greek_words.txt" "$SCRIPT_DIR/greek_expected.txt"
run_cruncher_test "Latin cruncher" "-L" \
    "$SCRIPT_DIR/latin_words.txt" "$SCRIPT_DIR/latin_expected.txt"

# Output format flags
run_cruncher_test "Greek -d (dbase)"        "-d"   "$GP" "$SCRIPT_DIR/greek_probe_d.txt"
run_cruncher_test "Latin -d (dbase)"        "-Ld"  "$LP" "$SCRIPT_DIR/latin_probe_d.txt"
run_cruncher_test "Greek -l (lemma)"        "-l"   "$GP" "$SCRIPT_DIR/greek_probe_l.txt"
run_cruncher_test "Latin -l (lemma)"        "-Ll"  "$LP" "$SCRIPT_DIR/latin_probe_l.txt"
run_cruncher_test "Greek -Px (lexicon)"     "-Px"  "$GP" "$SCRIPT_DIR/greek_probe_Px.txt"
run_cruncher_test "Latin -Px (lexicon)"     "-LPx" "$LP" "$SCRIPT_DIR/latin_probe_Px.txt"
run_cruncher_test "Greek -Pp (parse)"       "-Pp"  "$GP" "$SCRIPT_DIR/greek_probe_Pp.txt"
run_cruncher_test "Latin -Pp (parse)"       "-LPp" "$LP" "$SCRIPT_DIR/latin_probe_Pp.txt"
run_cruncher_test "Greek -e (ending index)" "-e"   "$GP" "$SCRIPT_DIR/greek_probe_e.txt"
run_cruncher_test "Latin -e (ending index)" "-Le"  "$LP" "$SCRIPT_DIR/latin_probe_e.txt"
run_cruncher_test "Greek -Pk (keep beta)"   "-Pk"  "$GP" "$SCRIPT_DIR/greek_probe_Pk.txt"

# Analysis flags
run_cruncher_test "Greek -V (verbs only)"       "-V"  "$GP" "$SCRIPT_DIR/greek_probe_V.txt"
run_cruncher_test "Latin -V (verbs only)"       "-LV" "$LP" "$SCRIPT_DIR/latin_probe_V.txt"
run_cruncher_test "Greek -S (non-strict case)"  "-S"  \
    "$SCRIPT_DIR/greek_probe_upper.txt" "$SCRIPT_DIR/greek_probe_S.txt"
run_cruncher_test "Latin -S (non-strict case)"  "-LS" \
    "$SCRIPT_DIR/latin_probe_upper.txt" "$SCRIPT_DIR/latin_probe_S.txt"
run_cruncher_test "Greek -n (ignore accents)"   "-n"  \
    "$SCRIPT_DIR/greek_probe_noaccent.txt" "$SCRIPT_DIR/greek_probe_n.txt"

# ── Baseline update mode ────────────────────────────────────────────────

if [ "$UPDATE" -eq 1 ]; then
    echo "Baselines written to $SCRIPT_DIR/"
    exit 0
fi

# ── Stemlib rebuild verification ─────────────────────────────────────────

# Build stemlibs if needed (ensures test works from a clean checkout)
for lang in Greek Latin; do
    dir="$PROJECT_DIR/stemlib/$lang"
    if [ ! -f "$dir/steminds/nomind" ]; then
        echo "     (building $lang stemlib ...)"
        if ! (cd "$dir" && MORPHLIB=.. make -B all) > /dev/null 2>&1; then
            echo "FAIL: $lang stemlib build"
            FAILURES=$((FAILURES + 1))
        fi
    fi
done

# Rebuild stemlibs from source and verify the build succeeds
for lang in Greek Latin; do
    dir="$PROJECT_DIR/stemlib/$lang"
    echo "     (rebuilding $lang stemlib ...)"
    if ! (cd "$dir" && MORPHLIB=.. make -B all) > /dev/null 2>&1; then
        echo "FAIL: $lang stemlib rebuild"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $lang stemlib rebuild"
    fi
done

# ── Sublemmas (:sl:) ─────────────────────────────────────────────────────
#
# Each test builds a stemlib in a temporary directory with the Latin makefile: a copy of the Latin stem sources with a
# few lines added, beside the real ending tables, derivations and verb index. The words it adds start with qq, which no
# Latin word does.

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

new_scratch_stemlib() {
    rm -rf "${SCRATCH:?}"/*
    mkdir -p "$SCRATCH/Latin/steminds"
    ln -s "$PROJECT_DIR/stemlib/Greek" "$SCRATCH/Greek"
    for d in endtables derivs rule_files; do
        ln -s "$PROJECT_DIR/stemlib/Latin/$d" "$SCRATCH/Latin/$d"
    done
    cp -pr "$PROJECT_DIR/stemlib/Latin/stemsrc" "$SCRATCH/Latin/"
    cp "$PROJECT_DIR"/stemlib/Latin/steminds/vbind* "$SCRATCH/Latin/steminds/"
}

# Adds lines $2... to the scratch copy of stem source $1, after a newline: some sources don't end with one.
add_stem_lines() {
    local file="$SCRATCH/Latin/stemsrc/$1"
    shift
    printf '\n' >> "$file"
    printf '%s\n' "$@" >> "$file"
}

make_scratch() {
    MORPHLIB="$SCRATCH" make -s -B -C "$SCRATCH/Latin" -f "$PROJECT_DIR/stemlib/Latin/makefile" "$1" 2>&1
}

# The entries of word $1 in the scratch stemlib, as Morpheus orders them, one per line: the lemma, the sublemma (empty
# for the entry's own word) and the grammar of each reading.
scratch_entries() {
    printf '%s\n' "$1" | MORPHLIB="$SCRATCH" "$PROJECT_DIR/bin/morpheus" -L 2>/dev/null | awk '
        /<entry>/ { lemma = ""; sublemma = ""; readings = ""; next }
        /<hdwd/ { lemma = $0; gsub(/<[^>]*>/, "", lemma); next }
        /<sublemma/ { sublemma = $0; gsub(/<[^>]*>/, "", sublemma); next }
        /<infl>/ { ininfl = 1; g = ""; next }
        /<\/infl>/ { readings = readings (readings == "" ? "" : "; ") substr(g, 2); ininfl = 0; next }
        /<\/entry>/ { print lemma "\t" sublemma "\t" readings; next }
        ininfl && !/<term/ { t = $0; gsub(/<[^>]*>/, "", t); gsub(/&amp;/, "\\&", t); g = g " " t }'
}

expect_same() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $label"
    else
        echo "FAIL: $label"
        echo "      expected: [$(printf '%s' "$expected" | tr '\t\n' '|;')]"
        echo "      got:      [$(printf '%s' "$actual" | tr '\t\n' '|;')]"
        FAILURES=$((FAILURES + 1))
    fi
}

# Appends lines $5... to stem source $4 of a new scratch stemlib, and expects make's target $3 to stop with the
# checker's refusal of the $2th line appended.
expect_refusal() {
    local label="$1" refused="$2" target="$3" file="$4" out line
    shift 4
    new_scratch_stemlib
    line=$(( $(wc -l < "$SCRATCH/Latin/stemsrc/$file") + 1 + refused ))
    add_stem_lines "$file" "$@"
    if out=$(make_scratch "$target"); then
        echo "FAIL: $label (make $target exited 0)"
        FAILURES=$((FAILURES + 1))
    else
        expect_same "$label stops make $target" "1" "$(grep -c "^stemsrc/$file:$line: " <<< "$out")"
    fi
}

LONGEST_SUBLEMMA=Qq$(printf 'x%.0s' {1..57})

new_scratch_stemlib
# Two words of one entry with identical readings
add_stem_lines ls.nom ':le:Qqalpha' ':no:qqa	a_ae fem' ':sl:Qqbeta' ':no:qqa	a_ae fem'
# One word in two files, with two stem lines that differ only by a flag
add_stem_lines nom.04 ':le:Qqgamma' ':sl:Qqdelta' ':no:qqc	a_ae fem'
add_stem_lines ls.nom ':le:Qqgamma' ':sl:Qqdelta' ':no:qqc	a_ae fem pers_name'
# A tagged whole form followed by another entry's untagged one
add_stem_lines nom.01 ':le:Qqepsilon' ':sl:Qqzeta' ':wd:qqd	adverb' ':le:Qqeta' ':wd:qqd	adverb'
# A tagged whole form followed by another entry's untagged stem
add_stem_lines nom.01 ':le:Qqtheta' ':sl:Qqiota' ':wd:qqea	adverb' ':le:Qqkappa' ':no:qqe	a_ae fem'
# A tagged block, then a block of the same entry in another file
add_stem_lines nom.02 ':le:Qqlambda' ':sl:Qqmu' ':no:qqf	a_ae fem'
add_stem_lines nom.03 ':le:Qqlambda' ':no:qqg	a_ae fem'
# An @ line under a sublemma, after a stem of its own
add_stem_lines ls.nom ':le:Qqnu' ':aj:qqh	us_a_um' ':sl:Qqxi' ':aj:qqk	er_era_erum superl' '@	comp'
# The longest sublemma
add_stem_lines ls.nom ':le:Qqomicron' ":sl:$LONGEST_SUBLEMMA" ':no:qqj	a_ae fem'

if out=$(make_scratch steminds/nomind); then
    echo "PASS: a stemlib with sublemmas builds"
    expect_same "qqaae: two words of one entry with identical readings stay apart" "$(cat <<'EOF'
Qqalpha		noun 1st genitive feminine singular a_ae; noun 1st dative feminine singular a_ae; noun 1st nominative feminine plural a_ae; noun 1st vocative feminine plural a_ae
Qqalpha	Qqbeta	noun 1st genitive feminine singular a_ae; noun 1st dative feminine singular a_ae; noun 1st nominative feminine plural a_ae; noun 1st vocative feminine plural a_ae
EOF
)" "$(scratch_entries qqaae)"
    expect_same "qqaam: -d shows the sublemma of the tagged reading" "$(printf ':lem Qqalpha\n:lem Qqalpha\n:sublem Qqbeta')" \
        "$(printf 'qqaam\n' | MORPHLIB="$SCRATCH" "$CRUNCHER" -Ld 2>/dev/null | grep -E '^:(lem|sublem) ')"
    expect_same "qqaam: -l shows the lemma alone" "$(printf 'form:qqaam\nQqalpha')" \
        "$(printf 'qqaam\n' | MORPHLIB="$SCRATCH" "$CRUNCHER" -Ll 2>/dev/null)"
    expect_same "qqcam: identical readings of one word merge" \
        "Qqgamma	Qqdelta	noun 1st accusative feminine singular a_ae" "$(scratch_entries qqcam)"
    expect_same "qqd: a tagged whole form leaves the next entry's untagged" "$(cat <<'EOF'
Qqepsilon	Qqzeta	adverb adverb indeclform
Qqeta		adverb adverb indeclform
EOF
)" "$(scratch_entries qqd)"
    expect_same "qqea: a tagged whole form leaves the next entry's stem untagged" "$(cat <<'EOF'
Qqkappa		noun 1st nominative feminine singular a_ae; noun 1st vocative feminine singular a_ae; noun 1st ablative feminine singular a_ae
Qqtheta	Qqiota	adverb adverb indeclform
EOF
)" "$(scratch_entries qqea)"
    expect_same "qqfam: a tagged block" "Qqlambda	Qqmu	noun 1st accusative feminine singular a_ae" \
        "$(scratch_entries qqfam)"
    expect_same "qqgam: a later block of the same entry, in another file, is untagged" \
        "Qqlambda		noun 1st accusative feminine singular a_ae" "$(scratch_entries qqgam)"
    expect_same "qqkerior: an @ line under a sublemma carries it" "$(cat <<'EOF'
Qqnu	Qqxi	adjective 1st & 2nd nominative masculine comparative singular er_era_erum; adjective 1st & 2nd nominative feminine comparative singular er_era_erum; adjective 1st & 2nd vocative masculine comparative singular er_era_erum; adjective 1st & 2nd vocative feminine comparative singular er_era_erum
EOF
)" "$(scratch_entries qqkerior)"
    expect_same "qqjam: the longest sublemma" "Qqomicron	$LONGEST_SUBLEMMA	noun 1st accusative feminine singular a_ae" \
        "$(scratch_entries qqjam)"
else
    echo "FAIL: a stemlib with sublemmas builds"
    echo "$out" | head -5 | sed 's/^/      /'
    FAILURES=$((FAILURES + 1))
fi

expect_refusal ":sl: before the file's first :le:" 1 steminds/nomind nom.livy ':sl:Qqpi' ':no:qqm	a_ae fem'
expect_refusal "empty :sl:" 2 steminds/nomind nom.01 ':le:Qqrho' ':sl:' ':no:qqm	a_ae fem'
expect_refusal ":sl: with a space" 2 steminds/nomind nom.01 ':le:Qqrho' ':sl:Qq sigma' ':no:qqm	a_ae fem'
expect_refusal ":sl: with a colon" 2 steminds/nomind nom.01 ':le:Qqrho' ':sl:Qq:sigma' ':no:qqm	a_ae fem'
expect_refusal ":sl: one byte longer than the longest" 2 steminds/nomind ls.nom ':le:Qqrho' ":sl:${LONGEST_SUBLEMMA}x" \
    ':no:qqm	a_ae fem'
expect_refusal ":sl: equal to its :le:" 2 steminds/nomind ls.nom ':le:Qqrho' ':sl:Qqrho' ':no:qqm	a_ae fem'
expect_refusal "@ line under a :sl: with no stem of its own" 4 steminds/nomind ls.nom ':le:Qqrho' \
    ':aj:qqm	er_era_erum superl' ':sl:Qqsigma' '@	comp'
expect_refusal ":sl: in a verb source" 1 steminds/vbind vbs.latin ':sl:Qqtau'
expect_refusal ":sl: in the irregular nouns" 1 stemsrc/nom.irreg irreg.nom.src ':sl:Qqtau'
expect_refusal ":sl: in the irregular verbs" 1 stemsrc/vbs.irreg irreg.vbs.src ':sl:Qqtau'

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES failure(s)."
    [ "$DIFFS" -gt 0 ] && echo "$DIFFS baseline diff(s)."
    exit 1
elif [ "$DIFFS" -gt 0 ]; then
    echo "$DIFFS baseline diff(s) (review above). No failures."
    exit 0
else
    echo "All tests passed."
    exit 0
fi
