"""Writes the two collections of the retrieval evaluation as JSON Lines.

    python3 -I bench/retrieval/prepare.py utokyo <cb-ja-demo>/_data/utokyo-agri.csv
    python3 -I bench/retrieval/prepare.py aozora bench/retrieval/cache/aozora.jsonl.gz

utokyo: the 69 records of the cb-ja-demo site (nakamura196/cb-ja-demo,
        _data/utokyo-agri.csv at 2e8cc12). Same records, ids and fields as the
        site's search: every row with an objectid (the site shows child
        objects), the fields marked index=true in _data/config-search.csv,
        whitespace collapsed as in CJKIndex::Jekyll's collectionbuilder preset.
        Written to bench/retrieval/data/utokyo.jsonl (committed).
aozora: the 16,951 works of globis-university/aozorabunko-clean (revision
        42a9c9c, sha256 3f41359c...d278): title, author and the first 200
        characters of the text, as in bench/aozora.rb (catalog mode).
        Written to bench/retrieval/cache/aozora.jsonl (not committed; it is
        rebuilt from the pinned file).
"""
import csv
import gzip
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
UTOKYO_FIELDS = ["title", "title_kana", "alternative", "date", "creator", "description", "note", "era"]
AOZORA_SHA256 = "3f41359c59b4bb1bf2d5692131463afc3f34a8208b987a563c1d60f9ab90d278"


def utokyo(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if not row["objectid"]:
                continue
            parent = row["parentid"]
            ref = f"{parent}.html#{row['objectid']}" if parent else f"{row['objectid']}.html"
            out.append({"id": ref, "fields": {k: " ".join(row[k].split()) for k in UTOKYO_FIELDS if row[k].strip()}})
    write(os.path.join(HERE, "data", "utokyo.jsonl"), out)


def aozora(path):
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if digest != AOZORA_SHA256:
        sys.exit(f"unexpected sha256 {digest}")
    out = []
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            m = d["meta"]
            out.append({"id": m["作品ID"], "fields": {"title": m["作品名"], "author": m["姓"] + m["名"], "text": d["text"][:200]}})
    write(os.path.join(HERE, "cache", "aozora.jsonl"), out)


def write(path, records):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    ids = [r["id"] for r in records]
    assert len(ids) == len(set(ids)), "duplicate ids"
    with open(path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{path}: {len(records)} records")


{"utokyo": utokyo, "aozora": aozora}[sys.argv[1]](sys.argv[2])
