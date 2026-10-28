/*!
 * cjk_index runtime — queries an index built by the cjk_index Ruby gem.
 * Generated file: the variant table and character classes below are written
 * by CJKIndex::Runtime so that they match the Ruby side exactly.
 * License: MIT
 */
(function (global) {
  'use strict';

  var VARIANTS = /*@VARIANTS@*/{};
  var TABLES = /*@TABLES@*/[];
  var DIGEST = /*@DIGEST@*/'';
  var CJK = new RegExp(/*@CJK@*/'', 'u');
  var SEPARATOR = new RegExp(/*@SEPARATOR@*/'', 'u');
  var FORMATS = ['cjk_index/2', 'cjk_index/3', 'cjk_index/4'];
  var COMPACT = 'cjk_index/4';
  var hasOwn = Object.prototype.hasOwnProperty;

  // Posting lists of format 4 (CJKIndex::Postings in Ruby): numbers written
  // with 90 printable characters, '#' to '}' without '\'. The first 60 are the
  // last digit of a number (base 60), the other 30 lead it (base 30).
  var DIGIT = [];
  for (var code = 0x23, digit = 0; code <= 0x7d; code++) if (code !== 0x5c) DIGIT[code] = digit++;

  // A posting list of format 4 as the flat list of format 3:
  // [doc, field, n, pos, ..., doc, field, n, ...].
  function decodePostings(s, nf) {
    var out = [];
    var key = -1, state = 0, left = 0, pos = 0, acc = 0;
    for (var i = 0; i < s.length; i++) {
      var d = DIGIT[s.charCodeAt(i)];
      if (d >= 60) { acc = acc * 30 + d - 60; continue; }
      var v = acc * 60 + d;
      acc = 0;
      if (state === 0) { key += v + 1; out.push(Math.floor(key / nf), key % nf); state = 1; }
      else if (state === 1) { out.push(v); left = v; pos = 0; state = 2; }
      else { pos += v; out.push(pos); if (--left === 0) state = 0; }
    }
    return out;
  }

  // Compares strings by code point, as Ruby compares UTF-8 strings (the
  // order of the shards). JavaScript's < compares UTF-16 code units, which
  // puts characters beyond U+FFFF before U+E000-U+FFFF.
  function compareCodePoints(a, b) {
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      var x = a.codePointAt(i), y = b.codePointAt(j);
      if (x !== y) return x < y ? -1 : 1;
      i += x > 0xffff ? 2 : 1;
      j += y > 0xffff ? 2 : 1;
    }
    return (i < a.length ? 1 : 0) - (j < b.length ? 1 : 0);
  }

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
  // Folded form of a filter value: as Builder.filter_key in Ruby.
  function filterKey(value) {
    return normalize(value).replace(/[ \t\n\r\f\v]+/g, ' ').replace(/^ /, '').replace(/ $/, '');
  }

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
    if (!data || FORMATS.indexOf(data.format) < 0) {
      throw new Error('cjk_index: unsupported index format ' + (data && data.format));
    }
    if (JSON.stringify(data.variants) !== JSON.stringify(TABLES)) {
      throw new Error('cjk_index: index built with variant tables ' + JSON.stringify(data.variants) +
        ' but this script folds with ' + JSON.stringify(TABLES) + '; rebuild both together');
    }
    if (data.variant_digest !== undefined && data.variant_digest !== DIGEST) {
      throw new Error('cjk_index: index built with other contents of the variant tables ' +
        JSON.stringify(TABLES) + ' (an older cjk_index?); rebuild it');
    }
    options = options || {};
    this.prefix = options.prefix !== false;          // last Latin word matches as a prefix
    this.typos = options.typos !== false;            // Latin words of 5+ letters allow one edit
    this.fields = data.fields;
    this.boosts = data.boosts;
    this.refs = data.refs;
    this.lengths = data.lengths;
    this.tokens = data.tokens || null;
    this.encoded = data.format === COMPACT;
    this.decoded = new Map();
    if (data.shards) {
      // Split index: the manifest lists the first token and file of each shard.
      this.loadShard = options.loadShard;
      if (!this.loadShard) throw new Error('cjk_index: a split index needs options.loadShard (CJKIndex.load sets it)');
      this.shardFirst = data.shards.map(function (s) { return s[0]; });
      this.shardFile = data.shards.map(function (s) { return s[1]; });
      this.shards = new Map();     // file -> tokens, once loaded
      this.pending = new Map();    // file -> Promise while loading
    }
    var nf = this.fields.length;
    var avg = new Array(nf).fill(0);
    for (var i = 0; i < this.lengths.length; i++) avg[i % nf] += this.lengths[i];
    this.avgLength = avg.map(function (s) { return s / Math.max(1, data.refs.length) || 1; });
    this.latinTokens = (this.tokens ? Object.keys(this.tokens).filter(isLatin) : data.latin.slice()).sort();
    this.latinSet = new Set(this.latinTokens);
    this.slotOf = new Map();
    for (var d = 0; d < this.refs.length; d++) if (!this.slotOf.has(this.refs[d])) this.slotOf.set(this.refs[d], d);
    // Filter values by document: keys (value filters) or a year, with the
    // form to show for each key and its rank of first appearance.
    this.filters = {};
    var filters = data.filters || {};
    Object.keys(filters).forEach(function (name) {
      var f = filters[name];
      var docs = f.docs;
      var display = new Map();
      if (f.kind !== 'year') {
        var keys = f.values.map(filterKey);
        f.values.forEach(function (v, i) { if (!display.has(keys[i])) display.set(keys[i], v); });
        docs = f.docs.map(function (ids) { return ids.map(function (id) { return keys[id]; }); });
      }
      var rank = new Map();
      docs.forEach(function (value) {
        (f.kind === 'year' ? (value === null ? [] : [value]) : value).forEach(function (key) {
          if (!rank.has(key)) rank.set(key, rank.size);
        });
      });
      if (f.kind === 'year') rank.forEach(function (r, year) { display.set(year, year); });
      this.filters[name] = { kind: f.kind, docs: docs, display: display, rank: rank };
    }, this);
  }

  // [[filter, test], ...] from the filter option of search.
  Index.prototype._compileFilter = function (filter) {
    var self = this;
    var out = [];
    Object.keys(filter).forEach(function (name) {
      var f = self.filters[name];
      if (!f) throw new Error('cjk_index: no filter ' + name);
      var c = filter[name];
      if (c === null || c === undefined || (Array.isArray(c) && !c.length)) return;
      if (f.kind === 'year') {
        var min = typeof c === 'object' ? c.min : c;
        var max = typeof c === 'object' ? c.max : c;
        out.push([f, function (year) {
          return year !== null && (min === null || min === undefined || year >= min) &&
            (max === null || max === undefined || year <= max);
        }]);
      } else {
        var keys = new Set((Array.isArray(c) ? c : [c]).map(filterKey));
        out.push([f, function (values) { return values.some(function (k) { return keys.has(k); }); }]);
      }
    });
    return out;
  };

  Index.prototype._pass = function (doc, conditions) {
    for (var i = 0; i < conditions.length; i++) if (!conditions[i][1](conditions[i][0].docs[doc])) return false;
    return true;
  };

  // Counts of the values of a filter, for a facet list: over results (as
  // returned by search, or refs) or over the whole index. Returns
  // [{value, count}], the most frequent first, ties in index order.
  Index.prototype.facets = function (field, results) {
    var self = this;
    var f = this.filters[field];
    if (!f) throw new Error('cjk_index: no filter ' + field);
    var docs = [];
    if (results) {
      results.forEach(function (r) {
        var d = self.slotOf.get(typeof r === 'object' ? r.ref : String(r));
        if (d !== undefined) docs.push(d);
      });
    } else {
      for (var d = 0; d < this.refs.length; d++) docs.push(d);
    }
    var counts = new Map();
    docs.forEach(function (doc) {
      var v = f.docs[doc];
      (f.kind === 'year' ? (v === null ? [] : [v]) : v).forEach(function (key) {
        counts.set(key, (counts.get(key) || 0) + 1);
      });
    });
    var out = Array.from(counts.entries());
    out.sort(function (a, b) { return b[1] - a[1] || f.rank.get(a[0]) - f.rank.get(b[0]); });
    return out.map(function (e) { return { value: f.display.get(e[0]), count: e[1] }; });
  };

  // File of the shard that holds token (split index), or null.
  Index.prototype._shardOf = function (token) {
    var lo = 0, hi = this.shardFirst.length;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (compareCodePoints(this.shardFirst[mid], token) <= 0) lo = mid + 1; else hi = mid;
    }
    return lo ? this.shardFile[lo - 1] : null;
  };

  // The posting list of a token as [doc, field, n, pos, ...], or null.
  Index.prototype._postings = function (token) {
    var table = this.tokens;
    if (!table) {
      var file = this._shardOf(token);
      if (file === null) return null;
      table = this.shards.get(file);
      if (!table) {
        throw new Error('cjk_index: the shard of "' + token + '" is not loaded; use searchAsync(query) or await prepare(query)');
      }
    }
    if (!hasOwn.call(table, token)) return null;
    if (!this.encoded) return table[token];
    var p = this.decoded.get(token);
    if (!p) { p = decodePostings(table[token], this.fields.length); this.decoded.set(token, p); }
    return p;
  };

  Index.prototype._loadShard = function (file) {
    var self = this;
    var p = this.pending.get(file);
    if (!p) {
      p = Promise.resolve(this.loadShard(file)).then(function (tokens) { self.shards.set(file, tokens); });
      p.catch(function () { self.pending.delete(file); });
      this.pending.set(file, p);
    }
    return p;
  };

  // Fetches the shards that a search for query needs (split index), so that
  // search(query) can then run. Resolves to the index; resolves at once for
  // an index in one file.
  Index.prototype.prepare = function (query) {
    var self = this;
    if (!this.shardFirst) return Promise.resolve(this);
    var files = new Set();
    var qp = phrases(query, false);
    qp.forEach(function (phrase, q) {
      phrase.forEach(function (tok, i) {
        self._alternatives(tok[0], q === qp.length - 1 && i === phrase.length - 1).tokens.forEach(function (t) {
          var file = self._shardOf(t);
          if (file !== null && !self.shards.has(file)) files.add(file);
        });
      });
    });
    return Promise.all(Array.from(files).map(function (f) { return self._loadShard(f); })).then(function () { return self; });
  };

  // search, after fetching the shards it needs. Works for every index, so
  // a page can use it whether or not the index is split.
  Index.prototype.searchAsync = function (query, options) {
    var self = this;
    return this.prepare(query).then(function () { return self.search(query, options); });
  };

  // Map of "doc,field" key -> Set of positions, merged over the alternatives.
  Index.prototype._positions = function (tokens) {
    var nf = this.fields.length;
    var map = new Map();
    for (var t = 0; t < tokens.length; t++) {
      var p = this._postings(tokens[t]);
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
    var out = this.latinSet.has(token) ? [token] : [];
    var keys = this.latinTokens;
    if (this.prefix && isLast) {
      var lo = 0, hi = keys.length;
      while (lo < hi) { var mid = (lo + hi) >> 1; if (keys[mid] < token) lo = mid + 1; else hi = mid; }
      for (var i = lo; i < keys.length && keys[i].indexOf(token) === 0; i++) if (keys[i] !== token) out.push(keys[i]);
    }
    if (this.typos && !this.latinSet.has(token) && Array.from(token).length >= 5) {
      keys.forEach(function (k) { if (oneEdit(token, k)) out.push(k); });
    }
    return { tokens: out, expanded: out.length > 0 && out[0] !== token };
  };

  // Every phrase of the query must occur in the document (in any field),
  // with its tokens adjacent and in order. Returns [{ref, score, fields}]
  // with the best match first; fields lists the names of the fields that matched.
  // options.filter: { type: '地図', subject: ['植物', '動物'], date: { min: 1900, max: 1950 } }
  // keeps the documents that meet every condition (see Searcher#search in Ruby).
  // With a filter, a blank query returns every document that passes it.
  Index.prototype.search = function (query, options) {
    var self = this;
    var nf = this.fields.length;
    var n = this.refs.length;
    var conditions = options && options.filter ? this._compileFilter(options.filter) : null;
    var qp = phrases(query, false);
    if (!qp.length) {
      if (!conditions) return [];
      var all = [];
      for (var d = 0; d < n; d++) {
        if (this._pass(d, conditions)) all.push({ ref: this.refs[d], score: 0, fields: [] });
      }
      return all;
    }
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
      if (conditions && !self._pass(doc, conditions)) return;
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

  // Characters that NFKC may compose with the one before (combining marks,
  // Hangul vowel and final jamo, half-width sound marks): kept in one cluster
  // so that the cluster normalizes as it does inside the whole text.
  var JOINS_PREVIOUS = /^[\p{M}\u1160-\u11ff\ud7b0-\ud7ff\u314f-\u3163\u3187-\u318e\uff9e\uff9f]$/u;

  // [start, end) ranges, in code points of the original text, where a phrase
  // of the query occurs after normalization.
  function matchRanges(text, query) {
    var chars = Array.from(String(text === null || text === undefined ? '' : text));
    var norm = [];
    var start = [];
    var end = [];
    var prev = null;
    // Each folded code point remembers which original characters it came
    // from. A character may fold to several (ko: one Private Use Area
    // character -> a jamo sequence), and a cluster may compose into fewer.
    function emit(str, from, to) {
      for (var c of str.normalize('NFKC').toLowerCase()) {
        prev = foldChar(c, prev);
        for (var p of prev) { norm.push(p); start.push(from); end.push(to); }
      }
    }
    for (var i = 0, j; i < chars.length; i = j) {
      for (j = i + 1; j < chars.length && JOINS_PREVIOUS.test(chars[j]); j++);
      var cluster = chars.slice(i, j);
      var whole = cluster.join('').normalize('NFKC');
      if (cluster.map(function (c) { return c.normalize('NFKC'); }).join('') === whole) {
        cluster.forEach(function (c, k) { emit(c, i + k, i + k + 1); });
      } else {
        emit(cluster.join(''), i, j);
      }
    }
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
        ranges.push([start[cp], end[cp + len - 1]]);
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

  function fetchJson(url) {
    return fetch(url).then(function (res) {
      if (!res.ok) throw new Error('cjk_index: ' + url + ' returned ' + res.status);
      return res.json();
    });
  }

  // Loads an index file, or the manifest of a split index: its shards are
  // then fetched from the same directory as queries need them (searchAsync).
  function load(url, options) {
    options = Object.assign({}, options);
    return fetchJson(url).then(function (data) {
      if (data && data.shards && !options.loadShard) {
        var base = new URL(url, typeof location !== 'undefined' ? location.href : undefined);
        options.loadShard = function (file) { return fetchJson(new URL(file, base).href); };
      }
      return new Index(data, options);
    });
  }

  var api = {
    tables: TABLES, normalize: normalize, filterKey: filterKey, tokenize: tokenize, phrases: phrases, includes: includes,
    highlight: highlight, excerpt: excerpt, Index: Index, load: load
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else global.CJKIndex = api;
})(typeof window !== 'undefined' ? window : globalThis);
