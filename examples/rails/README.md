# cjk_index in a Rails app

Four small files you copy into an app that has an `Article` model
(`title`, `body`, `category`, `published_on`). Tested with Rails 8.1.4 on
Ruby 4.0 with SQLite and Puma 8 (`puma -w 4`).

| File | What it does |
|---|---|
| `config/initializers/cjk_index.rb` | opens the index file `db/search-<env>.json` as `SEARCH_INDEX` |
| `app/models/concerns/searchable.rb` | updates the index after commit; `Article.search`; `Article.rebuild_search_index` |
| `app/models/article.rb` | `include Searchable` and the fields to index |
| `app/controllers/articles_controller.rb` | `GET /articles?q=鳥瞰図&category=地図&from=1890&until=1910` |
| `lib/tasks/search.rake` | `bin/rails search:rebuild` |

Setup: add `gem "cjk_index"` to the Gemfile, copy the files, add
`resources :articles, only: :index` to `config/routes.rb`, run
`bin/rails search:rebuild`, and add `/db/search-*.json*` to `.gitignore`
(the index is built from the database, not committed).

## Several processes

Puma workers, `rails console`, runners and jobs may all write. `IndexFile`
takes a lock on `db/search-<env>.json.lock` for each update, reads the current
file, applies the change and replaces the file in one step. No update is lost,
and a reader never sees a half-written file. Each worker notices a changed
file on its next search. A search that starts just after
another process's update may still see the old index for a moment (at most 0.26 s
with 5,000 records in `bench/puma`).

The index file must be on a local disk (not NFS), and every process must see the
same `db/` folder, so this does not fit several servers behind a load
balancer; there, build the index at deploy time or give each server its own.

## Cost of one update

An update rewrites the whole file: about 0.1 s for 1,000 records and about
0.85 s for 17,000 (see `docs/notes/filters-and-updates.md`). That is fine for
an editorial app. For imports use `Article.rebuild_search_index` once at the
end (or `insert_all`, which skips callbacks), and for heavy traffic move
`index_for_search` into a background job.
