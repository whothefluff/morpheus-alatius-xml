#!/usr/bin/env python3
"""
Checks that every test word's output is byte for byte the same as on the build before a change, and fails on any
difference, except for the words in tests/unchanged_output_exceptions.txt, which a change of the stem files is meant to
change. A word listed there whose output did not change fails too.

    python3 tests/check_unchanged_output.py --update   on the build before the change: writes the baseline
    python3 tests/check_unchanged_output.py            on the build with the change: compares with the baseline

Git ignores the binaries and the indices, so after building the commit before the change and checking out the change,
the build is still the earlier one: run --update then, and again without it after building the change (make clean
first when src/includes changed). The baseline, tests/unchanged_output_expected.json, is ignored by git too, and only
--update writes it: tests/run_tests.sh --update leaves it as it is.

Each word runs on its own, through cruncher and morpheus with each set of flags that run_tests.sh and
run_xml_tests.sh use, over the word lists those scripts read and the forms of the Latin lemma assertions.

stdlib only (per the project's testing conventions).
"""

import argparse
import difflib
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Dict, List, Set, Tuple

TESTS = Path(__file__).resolve().parent
PROJECT = TESTS.parent
BASELINE = TESTS / 'unchanged_output_expected.json'
EXCEPTIONS = TESTS / 'unchanged_output_exceptions.txt'


def lines_of(name: str) -> List[str]:
    return [line for line in (TESTS / name).read_text().splitlines() if line]


def first_fields_of(names: List[Path]) -> List[str]:
    return [line.split()[0] for name in names for line in name.read_text().splitlines()
            if line.strip() and not line.startswith('#')]


LATIN = sorted(set(lines_of('latin_words.txt') + lines_of('latin_probe.txt')
                   + first_fields_of(sorted(TESTS.glob('latin_assertions*.txt'))
                                   + [TESTS / 'xml_whole_forms.txt', TESTS / 'xml_sublemmas.txt'])))
GREEK = sorted(set(lines_of('greek_words.txt') + lines_of('greek_probe.txt')))

# The words of each run, by program and flags.
RUNS: Dict[str, List[str]] = {
    **{f'cruncher {flags}': LATIN for flags in ['-L', '-Ld', '-Ll', '-LPx', '-LPp', '-Le', '-LV']},
    'morpheus -L': LATIN,
    'cruncher -LS': lines_of('latin_probe_upper.txt'),
    'morpheus -LS': lines_of('latin_probe_upper.txt'),
    **{f'cruncher {flags}'.strip(): GREEK for flags in ['', '-d', '-l', '-Px', '-Pp', '-e', '-Pk', '-V']},
    'morpheus': GREEK,
    'morpheus -i': GREEK,
    'cruncher -S': lines_of('greek_probe_upper.txt'),
    'morpheus -S': lines_of('greek_probe_upper.txt'),
    'cruncher -n': lines_of('greek_probe_noaccent.txt'),
    'morpheus -n': lines_of('greek_probe_noaccent.txt'),
}

Outputs = Dict[str, Dict[str, str]]


def output_of(run: str, word: str) -> str:
    program, *flags = run.split()
    return subprocess.run([str(PROJECT / 'bin' / program), *flags], input=f'{word}\n'.encode('latin-1'),
                          capture_output=True, env={**os.environ, 'MORPHLIB': str(PROJECT / 'stemlib')},
                          check=False).stdout.decode('latin-1')


def outputs_of(words_by_run: Dict[str, List[str]]) -> Outputs:
    pairs = [(run, word) for run, words in words_by_run.items() for word in words]
    with ThreadPoolExecutor(max_workers=os.cpu_count()) as pool:
        outputs = list(pool.map(lambda pair: output_of(*pair), pairs))
    by_run: Outputs = {run: {} for run in words_by_run}
    for (run, word), output in zip(pairs, outputs):
        by_run[run][word] = output
    return by_run


def changed_runs_of(baseline: Outputs, current: Outputs) -> Dict[str, List[str]]:
    changed: Dict[str, List[str]] = {}
    for run, words in baseline.items():
        for word, output in words.items():
            if current[run][word] != output:
                changed.setdefault(word, []).append(run)
    return changed


def exceptions() -> Set[str]:
    return set(first_fields_of([EXCEPTIONS]))


def report(baseline: Outputs, current: Outputs, changed: Dict[str, List[str]], expected: Set[str]) -> int:
    unexpected: List[Tuple[str, str]] = [(word, run) for word, runs in sorted(changed.items()) if word not in expected
                                         for run in runs]
    unchanged = sorted(expected - changed.keys())
    for word, run in unexpected:
        print(f'FAIL: {run}: {word} changed')
        sys.stdout.writelines(difflib.unified_diff(baseline[run][word].splitlines(keepends=True),
                                                   current[run][word].splitlines(keepends=True),
                                                   'before', 'after', n=0))
    for word in unchanged:
        print(f'FAIL: {word} is listed in {EXCEPTIONS.name} but its output did not change')
    print(f'{sum(len(words) for words in baseline.values())} outputs compared: {len(changed)} words changed, '
          f'{len(expected)} listed as changing.')
    return 1 if unexpected or unchanged else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--update', action='store_true', help='write the baseline from this build')
    if parser.parse_args().update:
        BASELINE.write_text(json.dumps(outputs_of(RUNS), indent=0, sort_keys=True))
        print(f'Baseline written to {BASELINE}')
        return 0
    baseline: Outputs = json.loads(BASELINE.read_text())
    current = outputs_of({run: list(words) for run, words in baseline.items()})
    return report(baseline, current, changed_runs_of(baseline, current), exceptions())


if __name__ == '__main__':
    sys.exit(main())
