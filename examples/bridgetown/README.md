# cjk_index in a Bridgetown site

Tested with Bridgetown 2.2.2 on Ruby 4.0 (Liquid templates). No Node or
esbuild is needed to build the index: the plugin runs after Bridgetown has
written the site and adds files to `output/`.

1. Add `gem "cjk_index"` to the Gemfile and run `bundle install`.
2. Copy `initializers.rb` into your `config/initializers.rb` (the `require`
   line must come first: Bridgetown only knows `init :cjk_index` after it).
3. Run `bin/bridgetown build`. You get `output/cjk-index/posts.json` and
   `output/cjk-index/cjk-index.js`.
4. In a layout, load the script and the index:

```html
<script src="/cjk-index/cjk-index.js"></script>
<script>
  CJKIndex.load("/cjk-index/posts.json").then(function (index) {
    index.search("鳥瞰図");  // [{ ref: "/posts/tokyo/", score: ..., fields: ["title"] }]
  });
</script>
```

A result's `ref` is the resource's URL, so it can be linked directly.
Front-matter fields are read from the resource (`category`, `tags`, ...);
`date` is indexed as a year when used as a `year` filter.

Notes

- The files are written after each build, including the rebuilds of
  `bin/bridgetown start`; a file is rewritten only when its content changed.
- Pages such as `src/about.md` belong to the `pages` collection; index them
  with `collection: %w[posts pages]`.
