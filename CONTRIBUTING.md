# Contributing

Issues and pull requests are welcome: bug reports from real hosts most of all, since this
repository's CI can only test on a GitHub-hosted runner.

## Reporting a problem

Say what host you run (operating system or NAS system and version, kernel, Docker and Compose
versions, the filesystem under Docker's data root), and attach the output of
`scripts/preflight.sh` and, if the node does not come up, of `scripts/trial.sh`. Remove anything
private first: addresses, host names, paths, repository names. Never paste a token, a private key
or the contents of `kubeconfig/`.

For security problems, do not open an issue: see [SECURITY.md](SECURITY.md).

## Changing things

1. Install the tools at the versions CI uses: [mise](https://mise.jdx.dev), then `mise install` in
   the repository.
2. Make the change. Keep every value that differs between hosts in `.env`, and every file
   readable on its own: say why a non-obvious line is there, in a comment next to it.
3. Run the static checks: `mise exec -- scripts/lint.sh`. It runs ShellCheck, hadolint, yamllint,
   actionlint, `helm lint` and `helm template` with the values in `helm/`, kubeconform, and
   `scripts/check-consistency.sh` (values that must agree across files, such as the proxy's
   address and the pinned versions).
4. If you can, run the stack on a Docker host and follow the README's Quick start. Otherwise the
   CI smoke test does it on a GitHub-hosted runner when the pull request is ready for review.
5. Add a line to `CHANGELOG.md` under "Unreleased".

Pin every image by digest and every GitHub Action by commit. Do not weaken the runner pod's
security context or the egress rules without saying why in the pull request; the README's
"Security posture" section must stay true.

Write commit messages that say what changed and why. By contributing you agree that your contribution is licensed under the [MIT licence](LICENSE).
