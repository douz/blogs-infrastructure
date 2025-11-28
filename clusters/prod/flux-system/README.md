# Flux System

This directory is managed by `flux bootstrap`.

Do not manually edit files here unless you know what you're doing.

To bootstrap Flux on this cluster:

```bash
flux bootstrap github \
  --owner=douz \
  --repository=blogs-infrastructure \
  --branch=main \
  --path=clusters/prod \
  --personal
```
