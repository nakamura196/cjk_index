# Adapters: command line, Rake, Bridgetown, Rails

## 2026-10-27: what was built and how it was checked

Grant item 4 (small core, thin adapters). Ruby 4.0.1, Apple M4 Max.

Core: the gemspec has no runtime dependency. `lib/` outside the adapters
requires only `json`, `set` and `optparse` (the CLI); `fileutils` is used by
the Rake task and the Bridgetown plugin. `jekyll` is required only by
`cjk_index/jekyll`, `bridgetown-core` only by `cjk_index/bridgetown`, `rake`
only by `cjk_index/rake_task`.

CSV: `csv` is a bundled gem, not a default gem, since Ruby 3.4, so under Bundler
`require "csv"` fails unless the Gemfile lists it. The CLI and Rake task load
it on first use and, if that fails, say so (install the gem or give JSON /
JSON Lines). The repo's Gemfile lists it for its own tests. The test for the
message stubs `require`.

CLI (`exe/cjk_index`, `lib/cjk_index/cli.rb`): `build`, `search`, `runtime`.
Exit codes: 0 done, 1 input could not be read (missing file, invalid JSON),
2 wrong usage (unknown option, missing field). `test/test_cli.rb` runs each
command in process and a few through the executable (`ruby -I lib exe/...`).
A built index is compared with one made through the library API.
The Rake task (`CJKIndex::RakeTask`) calls the same `CLI.build_index`;
`records` can also be a lambda (database rows) instead of a file.

Bridgetown 2.2.2 (latest on rubygems on this date), real site made with
`bridgetown new --skip-bundle --skip-npm -t liquid` in a scratch folder, with
three Japanese/English posts. `bridgetown build` needs no Node or esbuild
(only `start` runs the frontend bundler), so no workaround was needed; the
default layout calls frontend helpers, so the scratch site's layout was
replaced by a plain one. The browser script, run under Node, found the
post by `鳥瞰図` (title match for 帝國 → 帝国 folding), `ソメイヨシノ`
(body, Markdown source), and a filter `category: 図鑑`.

Non-obvious facts about Bridgetown:

- `init :name` first requires the gem named `name`, then looks up the
  initializer, which must be registered during a config load
  (`Bridgetown.initializer` raises "without a preloaded configuration"
  otherwise). So the site's `config/initializers.rb` starts with
  `require "cjk_index/bridgetown"` and then `init :cjk_index, ...`. A name with a
  slash (`:"cjk_index/bridgetown"`) crashes `PluginManager.require_gem`.
- Files are written in a `:site, :post_write` hook straight into the
  destination. Bridgetown's cleaner runs before writing, so the files are
  deleted and written again on the next build; the plugin skips a write when
  the content is the same.
- Front matter `date` is a `Time`. `Builder` applies `Array()` to a value,
  and `Array(Time)` is `[sec, min, hour, ...]`, so a year filter on a Time
  gave 0. The plugin passes dates as `YYYY-MM-DD` strings. (Builder could
  handle this itself; not changed here.)
- The Jekyll plugin passes only the index fields of a collection document to
  the builder, so a filter on a front-matter field that is not an indexed field
  would be empty there; the Bridgetown plugin passes fields and filter fields.
  Not checked in the Jekyll plugin.
- Jekyll 4.3 and Bridgetown 2.2 cannot be resolved in one bundle. The test is
  run with `BUNDLE_GEMFILE=gemfiles/bridgetown.gemfile`; `test_jekyll.rb` skips
  there and `test_bridgetown.rb` skips in the normal bundle. A site with
  `"type": "module"` in `package.json` makes Node treat `cjk-index.js` as an
  ES module (`require` returns no `Index`); this affects only a Node check,
  not browsers.
- Bundler installed the Bridgetown test bundle into the global gem directory
  (`/opt/homebrew/lib/ruby/gems/4.0.0`).

Rails 8.1.4 (`rails new --minimal --skip-git`, SQLite, Puma 8.0.2), gems in a
scratch GEM_HOME. Through the app: `Article.create!` (4 separate
`bin/rails runner` processes, 5 records each, at the same time) while
`puma -w 4 -t 2:2` was running; all 20 records were found by
`GET /articles?q=...` (6 requests with `--no-keepalive`, so any worker),
the category filter and the year range (`from=1903&until=1904`: 10) gave the
expected counts, and after `destroy_all` of one category the search returned
15. `update!` replaced the old title in the index, `destroy` removed the
record, `rebuild_search_index` after wiping the file gave the database's
refs. The example files in `examples/rails` are the ones used.

Not checked: Bridgetown with ERB/Serbea templates (the plugin does not touch
templates), `bridgetown start` live rebuilds, Bridgetown below 2.2, Rails
other than 8.1.4, Rails with PostgreSQL/MySQL, `after_commit` inside a
nested transaction or with `insert_all` (callbacks are skipped by design),
Windows for the CLI and the Rake task (nothing platform specific in them).
