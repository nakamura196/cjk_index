# Contributing

Thank you for helping with cjk_index. Issues and pull requests are welcome.
日本語でも構いません。

## Reporting a bug

Use the bug report form. The most useful report has:

- the query, and the text of a record it should (or should not) find
- what `CJKIndex.normalize` returns for both, if you can run Ruby
- whether the result differs between Ruby and the browser
- your Ruby version, and the browser if the problem is in the browser

Security problems: see [SECURITY.md](SECURITY.md). Please do not open a public
issue for them.

## Development

You need Ruby 3.1 or later and Node (the runtime tests run the browser runtime
under Node).

```sh
bundle install
bundle exec rake test
```

## Pull requests

- Keep Ruby and the browser in step. The browser runtime is generated from the
  Ruby tables, and the test suite requires identical results in both; a change
  to normalization, tokenization or ranking must keep those tests passing.
- A change to the folding tables (`data/`) changes what existing indexes
  match. Say so in the pull request and in CHANGELOG.md; indexes built with the
  old tables need rebuilding.
- Add or update tests for the behavior you change.
- Write code, comments, commit messages and documentation in English. The
  discussion in issues and pull requests can be in Japanese.
