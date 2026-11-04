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

## Test Agents of other operating systems

The image also carries the cross toolchains that the Builder of TE needs for
the Test Agents of Windows and macOS. A suite selects one by the `--host`
triplet of its `TE_PLATFORM`:

| Agent | `--host` | Toolchain |
|---|---|---|
| Linux, the CPU of the image | none | gcc of the distribution |
| Windows x86-64 | `x86_64-w64-mingw32` | MinGW-w64 of the distribution |
| Windows ARM64 | `aarch64-w64-mingw32` | [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) in `/opt/llvm-mingw` |
| macOS arm64 | `aarch64-apple-darwin` | clang and `ld64.lld` |
| macOS x86-64 | `x86_64-apple-darwin` | clang and `ld64.lld` |

llvm-mingw is at the end of `PATH`. Its `x86_64-w64-mingw32-*` wrappers do
not hide the MinGW-w64 of the distribution.

The license of Apple does not let the image carry the SDK of macOS. Mount one
from a Mac (Xcode or the Command Line Tools) at `/opt/macos-sdk`:

```sh
docker run -v /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk:/opt/macos-sdk:ro ...
```

The `*-apple-darwin-*` tools are links to `apple-darwin-wrap`. It takes the
SDK from `MACOS_SDK` (default `/opt/macos-sdk`) and the oldest macOS to run
on from `MACOS_MIN` (default `11.0`).

The Unix agent needs PCRE2 (for ta_job) of the target. It cannot be built
without the SDK, so the image carries its sources: the first call of a
compiler wrapper or `pkg-config` builds a static PCRE2 into
`$MACOS_DEPS/<triplet>` (default `/opt/macos-deps`). Mount a volume there
to keep it between containers. `pkg-config` sees only the libraries there
and in `MACOS_PKG_CONFIG_LIBDIR`, never the libraries of the image.

The sniffers of the agent need Linux: give the agent type of macOS
`--without-sniffers`.

The provisioner of the plugin installs none of these toolchains: a run on a
bare image builds only the agents of Linux.

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
# an amd64 image on Apple silicon (Rosetta emulation):
docker build --platform linux/amd64 -t te-docker:latest .
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
