/*!
 * cjk_index runtime — queries an index built by the cjk_index Ruby gem.
 * Generated file: the variant table and character classes below are written
 * by CJKIndex::Runtime so that they match the Ruby side exactly.
 * License: MIT
 */
(function (global) {
  'use strict';

  var VARIANTS = /*@VARIANTS@*/{};
  var CJK = new RegExp(/*@CJK@*/'', 'u');
  var SEPARATOR = new RegExp(/*@SEPARATOR@*/'' + '+', 'u');
  var FORMAT = 'cjk_index/1';

  function normalize(text) {
    if (text === null || text === undefined) return '';
    var out = '';
    var prev = null;
    for (var ch of String(text).normalize('NFKC').toLowerCase()) {
      var c = ch.codePointAt(0);
      if (c >= 0x30a1 && c <= 0x30f6) ch = String.fromCodePoint(c - 0x60);
      if (VARIANTS[ch]) ch = VARIANTS[ch];
      if (ch === '々' && prev) ch = prev;
      out += ch;
      prev = ch;
    }
    return out;
  }

  function tokenize(text, unigrams) {
    var tokens = [];
    normalize(text).split(SEPARATOR).forEach(function (chunk) {
      if (!chunk) return;
      var run = '';
      var runIsCjk = null;
      var flush = function () {
        if (!run) return;
        if (runIsCjk) {
          var chars = Array.from(run);
          if (chars.length === 1 || unigrams) tokens.push.apply(tokens, chars);
          for (var i = 0; i < chars.length - 1; i++) tokens.push(chars[i] + chars[i + 1]);
        } else {
          tokens.push(run);
        }
        run = '';
      };
      for (var ch of chunk) {
        var isCjk = CJK.test(ch);
        if (runIsCjk !== null && isCjk !== runIsCjk) flush();
        runIsCjk = isCjk;
        run += ch;
      }
      flush();
    });
    return tokens;
  }

  // Substring test on normalized text, ignoring whitespace. Useful for
  // filters that do not need the index (e.g. a browse page).
  function includes(haystack, needle) {
    var strip = function (s) { return normalize(s).replace(/\s+/g, ''); };
    return strip(haystack).indexOf(strip(needle)) !== -1;
  }

  function Index(data) {
    if (!data || data.format !== FORMAT) {
      throw new Error('cjk_index: unsupported index format ' + (data && data.format));
    }
    this.fields = data.fields;
    this.boosts = data.boosts;
    this.refs = data.refs;
    this.tokens = data.tokens;
  }

  // Every token of the query must occur in the document (in any field).
  // Returns [{ref, score}] with the best match first.
  Index.prototype.search = function (query) {
    var terms = Array.from(new Set(tokenize(query, false)));
    if (!terms.length) return [];
    var n = this.refs.length;
    var scores = new Map();
    var hits = new Map();
    for (var t = 0; t < terms.length; t++) {
      var postings = this.tokens[terms[t]];
      if (!postings) return [];
      var docs = new Set();
      for (var i = 0; i < postings.length; i += 3) docs.add(postings[i]);
      var idf = Math.log(1 + n / docs.size);
      for (var j = 0; j < postings.length; j += 3) {
        var doc = postings[j];
        var s = this.boosts[postings[j + 1]] * (1 + Math.log(postings[j + 2])) * idf;
        scores.set(doc, (scores.get(doc) || 0) + s);
      }
      docs.forEach(function (d) { hits.set(d, (hits.get(d) || 0) + 1); });
    }
    var refs = this.refs;
    var results = [];
    hits.forEach(function (count, doc) {
      if (count === terms.length) results.push({ ref: refs[doc], score: scores.get(doc), doc: doc });
    });
    results.sort(function (a, b) { return b.score - a.score || a.doc - b.doc; });
    return results.map(function (r) { return { ref: r.ref, score: r.score }; });
  };

  function load(url) {
    return fetch(url).then(function (res) {
      if (!res.ok) throw new Error('cjk_index: ' + url + ' returned ' + res.status);
      return res.json();
    }).then(function (data) { return new Index(data); });
  }

  var api = { normalize: normalize, tokenize: tokenize, includes: includes, Index: Index, load: load };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else global.CJKIndex = api;
})(typeof window !== 'undefined' ? window : globalThis);
