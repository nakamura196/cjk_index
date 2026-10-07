// Runs the queries of queries.tsv with lunr.js 2.3.9 in three configurations.
//
//   node bench/retrieval/run_lunr.js utokyo
//   node bench/retrieval/run_lunr.js aozora
//
// lunr-default: lunr as CollectionBuilder ships it (_includes/js/lunr-js.html
//   of collectionbuilder-csv, also the "default" column of cb-ja-demo's
//   comparison page): English pipeline, idx.search(query).
// lunr-ja-or / lunr-ja-and: lunr with lunr-languages 1.21.0 for Japanese
//   (TinySegmenter, a statistical word segmenter). The builder segments the
//   records, but idx.search() splits a query only at spaces, so 東京大学 would
//   stay one term and match nothing. The query is therefore segmented with
//   the same lunr.ja.tokenizer and passed as terms: any term (or), or every
//   term (and, the closest to cjk_index, which requires the whole query).
//
// Writes results/<corpus>-<config>.tsv.
'use strict';
const fs = require('fs');
const path = require('path');
const lunr = require('lunr');
require('lunr-languages/lunr.stemmer.support')(lunr);
require('lunr-languages/tinyseg')(lunr);
require('lunr-languages/lunr.ja')(lunr);

const HERE = __dirname;
const SOURCES = { utokyo: path.join(HERE, 'data', 'utokyo.jsonl'), aozora: path.join(HERE, 'cache', 'aozora.jsonl') };
const corpus = process.argv[2];
const records = fs.readFileSync(SOURCES[corpus], 'utf8').trim().split('\n').map(JSON.parse);
const fields = [...new Set(records.flatMap(r => Object.keys(r.fields)))];
const queries = fs.readFileSync(path.join(HERE, 'queries.tsv'), 'utf8').trim().split('\n').slice(1)
  .map(line => line.split('\t')).filter(c => c[0] === corpus).map(c => ({ qid: c[1], query: c[2] }));

function build(japanese) {
  return lunr(function () {
    if (japanese) this.use(lunr.ja);
    this.ref('id');
    fields.forEach(f => this.field(f));
    records.forEach(r => this.add(Object.assign({ id: r.id }, r.fields)));
  });
}

function japaneseSearch(idx, query, presence) {
  const terms = lunr.ja.tokenizer(query).map(t => t.toString()).filter(Boolean);
  return idx.query(q => terms.forEach(t => q.term(t, { presence })));
}

const plain = build(false);
const ja = build(true);
const configs = {
  'lunr-default': q => { try { return plain.search(q); } catch (e) { return []; } },
  'lunr-ja-or': q => japaneseSearch(ja, q, lunr.Query.presence.OPTIONAL),
  'lunr-ja-and': q => japaneseSearch(ja, q, lunr.Query.presence.REQUIRED)
};

for (const [name, run] of Object.entries(configs)) {
  const lines = ['qid\trank\tdoc'];
  queries.forEach(({ qid, query }) => run(query).forEach((r, i) => lines.push(`${qid}\t${i + 1}\t${r.ref}`)));
  fs.writeFileSync(path.join(HERE, 'results', `${corpus}-${name}.tsv`), lines.join('\n') + '\n');
}
console.log(`${corpus}: ${records.length} records, ${queries.length} queries, configs ${Object.keys(configs).join(', ')}`);
console.log('query segmentation (lunr.ja.tokenizer):');
queries.forEach(({ qid, query }) => console.log(`  ${qid} ${query} -> ${lunr.ja.tokenizer(query).map(String).join(' | ')}`));
