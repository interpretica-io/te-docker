# te-docker

The reference build-environment image for **container-isolated** midair runs.

A midair node with `isolation=container` — always the builtin `localhost` node
— runs each analysis or Test Environment suite inside a throwaway Docker
container. The container's image only has to carry the *build environment*:

- the platform injects the **visao** analyzer into it at run time, and
- the suite clones and builds TE/TS itself per run.

So this image bakes in the build **dependencies** only. It deliberately does
not bake TE in — that would pin a version and defeat the per-run checkout.

## Why it exists

A bare `ubuntu:26.04` works too: on first use the plugin's provisioner
(`isabelle-plugin-midair/src/provision.rs`) installs the same package set. This
image just bakes it in so a run starts in seconds instead of waiting ~2.5 min
for `apt`. The plugin probes for the toolchain (`meson ninja gcc flex bison
pkg-config git`) and, finding it present, skips provisioning entirely.

## Keeping it in sync

The package list in the `Dockerfile` is the Debian/Ubuntu superset from
`isabelle-plugin-midair/src/provision.rs` (the `APT` const). Both derive from
the TE user docs (`test-environment/doc/sphinx/pages/group_te_user.rst`) and
the `bublik-docker` image. **If one changes, change the other.**

## Build

```sh
docker build -t te-docker:latest .
# or, to publish the reference image:
docker build -t ghcr.io/interpretica-io/te-docker:latest .
docker push ghcr.io/interpretica-io/te-docker:latest
```

## Use

Point a workspace's image at it. A workspace that sets only `analysis_image`
gets that image for its tests too; a separate `test_image` overrides it. With
no image set at all, runs fall back to `ubuntu:26.04` and self-provision.

```
analysis_image = te-docker:latest        # local build, or
analysis_image = ghcr.io/interpretica-io/te-docker:latest   # once published
```

Once the image is published to a registry every deployment can pull from, it
can become the platform default (in `isolation.rs`, `DEFAULT_ANALYSIS_IMAGE`).
Until then the default stays `ubuntu:26.04` so a fresh deployment needs no
pre-pulled image.
