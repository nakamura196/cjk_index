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
  var SEPARATOR = new RegExp(/*@SEPARATOR@*/'', 'u');
  var FORMAT = 'cjk_index/2';

  // BM25 parameters (the usual defaults, as in Lucene and Pagefind).
  var K1 = 1.2;
  var B = 0.75;
  // Score multiplier for matches found by prefix or typo expansion.
  var EXPANDED = 0.6;

  // Folds one character; prev is the previous folded character (for 々).
  function foldChar(ch, prev) {
    var c = ch.codePointAt(0);
    if (c >= 0x30a1 && c <= 0x30f6) ch = String.fromCodePoint(c - 0x60);
    if (VARIANTS[ch]) ch = VARIANTS[ch];
    if (ch === '々' && prev) ch = prev;
    return ch;
  }

  function normalize(text) {
    if (text === null || text === undefined) return '';
    var out = '';
    var prev = null;
    for (var ch of String(text).normalize('NFKC').toLowerCase()) {
      prev = foldChar(ch, prev);
      out += prev;
    }
    return out;
  }

  // Same loop as CJKIndex::Tokenizer.phrases in Ruby: split at separators
  // into phrases of [token, offset]; CJK runs become bigrams (plus unigrams
  // when asked), other runs stay words. Offsets count code points.
  function phrases(text, unigrams) {
    var result = [];
    var phrase = [];
    var run = [];
    var runCjk = null;
    var runStart = 0;
    var flush = function () {
      if (!run.length) return;
      if (runCjk) {
        if (run.length === 1 || unigrams) {
          for (var i = 0; i < run.length; i++) phrase.push([run[i], runStart + i]);
        }
        for (var j = 0; j < run.length - 1; j++) phrase.push([run[j] + run[j + 1], runStart + j]);
      } else {
        phrase.push([run.join(''), runStart]);
      }
      run = [];
    };
    var offset = 0;
    for (var ch of normalize(text)) {
      if (SEPARATOR.test(ch)) {
        flush();
        if (phrase.length) result.push(phrase);
        phrase = [];
        runCjk = null;
      } else {
        var cjk = CJK.test(ch);
        if (runCjk !== null && cjk !== runCjk) flush();
        if (!run.length) runStart = offset;
        runCjk = cjk;
        run.push(ch);
      }
      offset++;
    }
    flush();
    if (phrase.length) result.push(phrase);
    return result;
  }

  function tokenize(text, unigrams) {
    var out = [];
    phrases(text, unigrams).forEach(function (p) { p.forEach(function (t) { out.push(t[0]); }); });
    return out;
  }

  // Substring test on normalized text, ignoring whitespace. Useful for
  // filters that do not need the index (e.g. a browse page).
  function includes(haystack, needle) {
    var strip = function (s) { return normalize(s).replace(/\s+/g, ''); };
    return strip(haystack).indexOf(strip(needle)) !== -1;
  }

  function isLatin(token) { return !CJK.test(token); }

  // true when a and b differ by exactly one insertion, deletion or substitution.
  function oneEdit(a, b) {
    if (a === b || Math.abs(a.length - b.length) > 1) return false;
    var i = 0;
    while (i < a.length && i < b.length && a[i] === b[i]) i++;
    if (a.length === b.length) return a.slice(i + 1) === b.slice(i + 1);
    if (a.length > b.length) return a.slice(i + 1) === b.slice(i);
    return a.slice(i) === b.slice(i + 1);
  }

  function Index(data, options) {
    if (!data || data.format !== FORMAT) {
      throw new Error('cjk_index: unsupported index format ' + (data && data.format));
    }
    options = options || {};
    this.prefix = options.prefix !== false;          // last Latin word matches as a prefix
    this.typos = options.typos !== false;            // Latin words of 5+ letters allow one edit
    this.fields = data.fields;
    this.boosts = data.boosts;
    this.refs = data.refs;
    this.lengths = data.lengths;
    this.tokens = data.tokens;
    var nf = this.fields.length;
    var avg = new Array(nf).fill(0);
    for (var i = 0; i < this.lengths.length; i++) avg[i % nf] += this.lengths[i];
    this.avgLength = avg.map(function (s) { return s / Math.max(1, data.refs.length) || 1; });
    this.latinTokens = Object.keys(this.tokens).filter(isLatin).sort();
  }

  // Map of "doc,field" key -> Set of positions, merged over the alternatives.
  Index.prototype._positions = function (tokens) {
    var nf = this.fields.length;
    var map = new Map();
    for (var t = 0; t < tokens.length; t++) {
      var p = this.tokens[tokens[t]];
      if (!p) continue;
      for (var i = 0; i < p.length;) {
        var key = p[i] * nf + p[i + 1];
        var n = p[i + 2];
        var set = map.get(key);
        if (!set) { set = new Set(); map.set(key, set); }
        for (var k = 0; k < n; k++) set.add(p[i + 3 + k]);
        i += 3 + n;
      }
    }
    return map;
  };

  // Alternatives for one query token: itself, and for Latin words the index
  // words it is a prefix of (last word only) or one edit away from.
  Index.prototype._alternatives = function (token, isLast) {
    if (!isLatin(token)) return { tokens: [token], expanded: false };
    var out = this.tokens[token] ? [token] : [];
    var keys = this.latinTokens;
    if (this.prefix && isLast) {
      var lo = 0, hi = keys.length;
      while (lo < hi) { var mid = (lo + hi) >> 1; if (keys[mid] < token) lo = mid + 1; else hi = mid; }
      for (var i = lo; i < keys.length && keys[i].indexOf(token) === 0; i++) if (keys[i] !== token) out.push(keys[i]);
    }
    if (this.typos && !this.tokens[token] && Array.from(token).length >= 5) {
      keys.forEach(function (k) { if (oneEdit(token, k)) out.push(k); });
    }
    return { tokens: out, expanded: out.length > 0 && out[0] !== token };
  };

  // Every phrase of the query must occur in the document (in any field),
  // with its tokens adjacent and in order. Returns [{ref, score, fields}]
  // with the best match first; fields lists the names of the fields that matched.
  Index.prototype.search = function (query) {
    var self = this;
    var nf = this.fields.length;
    var n = this.refs.length;
    var qp = phrases(query, false);
    if (!qp.length) return [];
    var scores = new Map();
    var matchedFields = new Map();
    var docsSoFar = null;

    for (var q = 0; q < qp.length; q++) {
      var phrase = qp[q];
      var expanded = false;
      var parts = phrase.map(function (tok, i) {
        var alt = self._alternatives(tok[0], q === qp.length - 1 && i === phrase.length - 1);
        if (alt.expanded) expanded = true;
        return { offset: tok[1], positions: self._positions(alt.tokens) };
      });
      if (parts.some(function (p) { return p.positions.size === 0; })) return [];
      parts.sort(function (a, b) { return a.positions.size - b.positions.size; });
      var rare = parts[0];
      var hits = new Map();                       // "doc,field" key -> phrase occurrences
      rare.positions.forEach(function (set, key) {
        var tf = 0;
        set.forEach(function (pos) {
          var start = pos - rare.offset;
          for (var i = 1; i < parts.length; i++) {
            var other = parts[i].positions.get(key);
            if (!other || !other.has(start + parts[i].offset)) return;
          }
          tf++;
        });
        if (tf) hits.set(key, tf);
      });
      var docs = new Set();
      hits.forEach(function (tf, key) { docs.add(Math.floor(key / nf)); });
      if (!docs.size) return [];
      if (docsSoFar) {
        docs.forEach(function (d) { if (!docsSoFar.has(d)) docs.delete(d); });
        if (!docs.size) return [];
      }
      docsSoFar = docs;
      var idf = Math.log(1 + (n - docs.size + 0.5) / (docs.size + 0.5));
      var weight = expanded ? EXPANDED : 1;
      hits.forEach(function (tf, key) {
        var doc = Math.floor(key / nf), field = key % nf;
        var norm = 1 - B + B * self.lengths[key] / self.avgLength[field];
        var s = weight * self.boosts[field] * idf * (tf * (K1 + 1)) / (tf + K1 * norm);
        scores.set(doc, (scores.get(doc) || 0) + s);
        var f = matchedFields.get(doc);
        if (!f) { f = new Set(); matchedFields.set(doc, f); }
        f.add(self.fields[field]);
      });
    }

    var results = [];
    docsSoFar.forEach(function (doc) {
      results.push({ ref: self.refs[doc], score: scores.get(doc), fields: Array.from(matchedFields.get(doc)), doc: doc });
    });
    results.sort(function (a, b) { return b.score - a.score || a.doc - b.doc; });
    return results.map(function (r) { return { ref: r.ref, score: r.score, fields: r.fields }; });
  };

  function escapeHtml(s) {
    return s.replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // [start, end) ranges, in code points of the original text, where a phrase
  // of the query occurs after normalization.
  function matchRanges(text, query) {
    var chars = Array.from(String(text === null || text === undefined ? '' : text));
    var norm = [];
    var origin = [];
    var prev = null;
    chars.forEach(function (ch, i) {
      for (var c of ch.normalize('NFKC').toLowerCase()) {
        prev = foldChar(c, prev);
        norm.push(prev);
        origin.push(i);
      }
    });
    var normText = norm.join('');
    var ranges = [];
    var needles = [];
    var current = '';
    for (var qc of normalize(query)) {
      if (SEPARATOR.test(qc)) { if (current) needles.push(current); current = ''; } else current += qc;
    }
    if (current) needles.push(current);
    needles.forEach(function (needle) {
      var len = Array.from(needle).length;
      var from = 0;
      var at;
      while ((at = normText.indexOf(needle, from)) !== -1) {
        var cp = Array.from(normText.slice(0, at)).length;
        ranges.push([origin[cp], origin[cp + len - 1] + 1]);
        from = at + needle.length;
      }
    });
    ranges.sort(function (a, b) { return a[0] - b[0]; });
    var merged = [];
    ranges.forEach(function (r) {
      var last = merged[merged.length - 1];
      if (last && r[0] <= last[1]) last[1] = Math.max(last[1], r[1]); else merged.push(r.slice());
    });
    return { chars: chars, ranges: merged };
  }

  // HTML-escaped text with every match of the query wrapped in <mark>.
  // 「東京帝國大學」 is marked for the query 「帝国大学」.
  function highlight(text, query) {
    var m = matchRanges(text, query);
    var out = '';
    var at = 0;
    m.ranges.forEach(function (r) {
      out += escapeHtml(m.chars.slice(at, r[0]).join('')) + '<mark>' + escapeHtml(m.chars.slice(r[0], r[1]).join('')) + '</mark>';
      at = r[1];
    });
    return out + escapeHtml(m.chars.slice(at).join(''));
  }

  // A highlighted window of about `length` characters around the first match.
  function excerpt(text, query, length) {
    length = length || 80;
    var m = matchRanges(text, query);
    if (!m.ranges.length) return m.chars.length > length ? escapeHtml(m.chars.slice(0, length).join('')) + '…' : escapeHtml(m.chars.join(''));
    var start = Math.max(0, m.ranges[0][0] - Math.floor(length / 3));
    var end = Math.min(m.chars.length, start + length);
    var part = m.chars.slice(start, end).join('');
    return (start > 0 ? '…' : '') + highlight(part, query) + (end < m.chars.length ? '…' : '');
  }

  function load(url, options) {
    return fetch(url).then(function (res) {
      if (!res.ok) throw new Error('cjk_index: ' + url + ' returned ' + res.status);
      return res.json();
    }).then(function (data) { return new Index(data, options); });
  }

  var api = {
    normalize: normalize, tokenize: tokenize, phrases: phrases, includes: includes,
    highlight: highlight, excerpt: excerpt, Index: Index, load: load
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else global.CJKIndex = api;
})(typeof window !== 'undefined' ? window : globalThis);
