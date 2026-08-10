# Screwbot asset policy

Screwbot uses one mixed asset policy. It embeds only the small, stable authored
inputs relative to `examples/screwbot/main.roc`: Inter, the 2x2 white texture,
and five fragment shader sources. Its three 1024x1024 material textures are
always loaded through one manifest-validated `Assets.Store`.

By default, the Store uses `Assets.beside_executable("examples/assets")`. This
works when Screwbot is built into the Terracotta repository root:

```bash
roc build examples/screwbot/main.roc --no-cache
./main
```

For an installed application or a cross-worktree build, set
`SCREWBOT_ASSET_ROOT` to an **absolute** directory before launch:

```bash
SCREWBOT_ASSET_ROOT=/opt/screwbot/assets ./main
```

Screwbot passes that value to `Assets.absolute_directory`, then opens the store
with `RequireManifest`. A relative value is rejected; CWD is never a fallback.
The store holds its opened directory capability and resolves the three material
textures relative to it. For example, from the roc-ray worktree:

```bash
roc build ../terrocotta-screwbot-parity/examples/screwbot/main.roc --no-cache
SCREWBOT_ASSET_ROOT=/absolute/path/to/terrocotta-screwbot-parity/examples/assets ./main
```

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
only Screwbot's three disk-loaded materials. Generate or verify it with the
roc-ray tool:

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

The embedded constructors borrow their compile-time `List(U8)`/`Str` payloads
only during synchronous decode/compile; the host retains the resulting typed
font/GPU resources. The Store reads the three material files relative to its
opened directory capability and releases temporary file bytes after decode.
There is one renderer/uniform setup after both kinds of resources are ready.

This avoids embedding a fallback copy of the three materials: the executable is
close to its former 13 MiB instead of carrying their additional ~14 MiB payload.
