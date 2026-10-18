"""Collects the records to judge for each query, without using cjk_index.

    python3 -I bench/retrieval/pool.py

A record goes into the pool of a query when one of its fields contains one of
the spellings listed for the query in queries.tsv (after NFKC, which folds
full-width and half-width forms). The spellings were written by hand, so the
pool does not depend on cjk_index's variant table. Writes pools/<corpus>.tsv:
one line per record and query, with every occurrence in context.
"""
import csv
import json
import os
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCES = {"utokyo": os.path.join(HERE, "data", "utokyo.jsonl"), "aozora": os.path.join(HERE, "cache", "aozora.jsonl")}
CONTEXT = 15


def load(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def occurrences(text, spellings):
    hits = []
    for s in spellings:
        start = text.find(s)
        while start >= 0:
            hits.append((start, start + len(s)))
            start = text.find(s, start + 1)
    return sorted(set(hits))


def main():
    with open(os.path.join(HERE, "queries.tsv"), encoding="utf-8") as f:
        queries = list(csv.DictReader(f, delimiter="\t"))
    os.makedirs(os.path.join(HERE, "pools"), exist_ok=True)
    for corpus, path in SOURCES.items():
        records = load(path)
        rows = []
        for q in (q for q in queries if q["corpus"] == corpus):
            spellings = [unicodedata.normalize("NFKC", s) for s in q["spellings"].split("|")]
            for r in records:
                kwic = []
                for field, value in r["fields"].items():
                    text = unicodedata.normalize("NFKC", value)
                    for a, b in occurrences(text, spellings):
                        snippet = f"{text[max(0, a - CONTEXT):a]}【{text[a:b]}】{text[b:b + CONTEXT]}"
                        kwic.append(f"{field}: " + snippet.replace("\r", "").replace("\n", "⏎").replace("\t", " "))
                if kwic:
                    rows.append([q["qid"], q["query"], r["id"], len(kwic), " ／ ".join(kwic)])
        out = os.path.join(HERE, "pools", f"{corpus}.tsv")
        with open(out, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f, delimiter="\t", lineterminator="\n")
            w.writerow(["qid", "query", "doc", "occurrences", "contexts"])
            w.writerows(rows)
        print(out, len(rows), "pairs")


main()
