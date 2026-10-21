#!/usr/bin/env python3
"""Generate the bundled translation table from the reviewed TSV."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def catalog():
    result = {}
    for number, line in enumerate((ROOT / 'localization/zh-Hans.tsv').read_text().splitlines(), 1):
        if not line.strip():
            continue
        if '\t' not in line:
            raise ValueError(f'Line {number}: expected a tab')
        english, chinese = line.split('\t', 1)
        if not english or not chinese or english in result:
            raise ValueError(f'Line {number}: empty or duplicate translation')
        result[english] = chinese
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = ROOT / 'Compositor/Resources/ChineseLocalization.json'
    content = json.dumps(catalog(), ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if not target.exists() or target.read_text() != content:
            raise SystemExit('Translation resource is stale: run python3 localization/generate.py')
    else:
        target.write_text(content)
    print(f'{len(catalog())} translations verified')
