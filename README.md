# nixpkgs-darwin-ci

Builds a nixpkgs attribute on an Apple Silicon GitHub Actions runner
(`aarch64-darwin`), for testing Darwin support in packages before they reach
Hydra.

```sh
gh workflow run build.yml -R yzhou216/nixpkgs-darwin-ci \
  -f ref=<branch-or-commit> -f attribute=<attribute>
```

The `repository` input defaults to `yzhou216/nixpkgs`.  After a successful
build, `tests/<attribute>.sh` runs if it exists; it receives the output path
and a directory whose contents are uploaded as an artifact.
