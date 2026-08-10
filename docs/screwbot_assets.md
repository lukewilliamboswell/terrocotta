# Screwbot asset modes

Screwbot is self-contained by default. Its font, four textures, and five
fragment shaders are compile-time imports relative to `examples/screwbot/main.roc`.
It can therefore be built and launched from any working directory without
consulting a disk asset path.

For an end-to-end disk-store test or an application-managed asset installation,
set `SCREWBOT_ASSET_ROOT` to an **absolute** directory before launch:

```bash
SCREWBOT_ASSET_ROOT=/opt/screwbot/assets ./main
```

Screwbot passes that value to `Assets.absolute_directory`, then opens the store
with `RequireManifest`. A relative value is rejected; CWD is never a fallback.
The store holds its opened directory capability and resolves every font,
texture, and shader source relative to it.

## Checked-in example root

The repository's existing shared `examples/assets` directory contains
`roc-assets.manifest` with this contract:

```text
asset_set = "terrocotta-example-assets"
schema = 1
content_version = 1
content_sha256 = "480faac50efc42d0425eed8182aca8c907ecc85c95e0af927f26c765f21ab902"
```

The root intentionally includes all checked-in Terrocotta example assets, not
only Screwbot's ten inputs. Generate or verify it with the roc-ray tool:

```bash
python3 ../roc-ray-elm/scripts/asset_manifest.py write examples/assets \
  --asset-set terrocotta-example-assets --schema 1 --content-version 1
python3 ../roc-ray-elm/scripts/asset_manifest.py check examples/assets \
  --asset-set terrocotta-example-assets --schema 1 --content-version 1
```

The digest is a streamed canonical inventory hash over sorted portable paths,
sizes, and per-file SHA-256 values; the manifest itself is excluded. Startup
compares only the declared manifest value to Screwbot's compiled expectation,
so it is O(manifest bytes), not O(asset count). A stale loose tree is detected
by the offline `check` command; it is not rehashed at application startup.

## Resource lifetime and size

Both modes converge into the same `AuthoredAssets` bundle before texture
filtering, uniforms, render targets, and renderer setup. The embedded mode
borrows the compile-time `List(U8)`/`Str` payloads only during synchronous
decode/compile; the host retains the resulting typed font/GPU resources. Disk
mode reads relative to the opened store and similarly releases temporary file
bytes after decode/compile.

The default executable still embeds its fallback assets even when disk mode is
selected at runtime. That costs about 14 MiB of authored payload in this
example; a separately compiled disk-only entrypoint would be needed to omit it.
