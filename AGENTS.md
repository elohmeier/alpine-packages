# alpine-packages repository

## Layout

```
<package>.yaml      # melange build definition
<package>/          # supporting files (init scripts, config, udev rules)
```

## Building

```
melange build --arch arm64 <package>.yaml
```

## CI/CD

GitHub Actions builds packages on push to main using `chainguard-dev/actions/melange-build-pkg`. Packages are published to GitHub Pages at `https://elohmeier.github.io/alpine-packages/<arch>/`.

Required secret: `ABUILD_PRIVKEY` (RSA signing key)

## Relevant sources

- $HOME/repos/github.com/chainguard-dev/melange
- $HOME/repos/github.com/chainguard-dev/actions
- $HOME/repos/github.com/wolfi-dev/os
