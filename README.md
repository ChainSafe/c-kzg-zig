# c-kzg-zig

Zig build packaging for [c-kzg-4844](https://github.com/ethereum/c-kzg-4844).

This package exports:

- a `c_kzg` Zig module generated with `translate-c` from `ckzg.h`
- a `blst` Zig module generated with `translate-c` from the exact `blst.h` used to build `c_kzg`
- the `c_kzg` C library artifact
- the c-kzg public headers, installed on that artifact
- a `trusted_setup` Zig module with decoded byte slices for `load_trusted_setup`
- `trusted_setup.txt` as a named lazy path

This package does not export a handwritten Zig wrapper over the C API. It exports the translated C ABI directly, so consumers can import the module instead of writing their own `@cImport`.

## Requirements

- Zig 0.16.0-dev

## Public Surface

From a dependency handle:

- `dep.module("c_kzg")`
- `dep.module("blst")`
- `dep.artifact("c_kzg")`
- `dep.module("trusted_setup")`
- `dep.namedLazyPath("trusted_setup")`

The `c_kzg` artifact installs:

- the full c-kzg public header tree
- `blst.h` and related installed headers forwarded from `blst.zig`

The exported `c_kzg` module is produced by `translate-c` and links the packaged `c_kzg` library transitively. The exported `blst` module is produced from the same `blst` build step that `c_kzg` uses internally.

## Ownership Model

This package owns the concrete `blst` version used to build `c_kzg`.

If downstream code needs only the KZG API, import `c_kzg`.
If downstream code needs both the KZG API and direct `blst` access, import both `c_kzg` and `blst` from this package.

Do not add a second, separate `blst.zig` dependency next to `c-kzg-zig` unless you are intentionally taking ownership of the entire versioning and link-compatibility story yourself. Mixing two independently selected `blst` package instances is where symbol duplication and drift become possible.

## Usage

Add dependencies to `build.zig.zon`:

```zon
.dependencies = .{
    .c_kzg = .{
        .url = "https://github.com/ChainSafe/c-kzg-zig/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "<hash>",
    },
},
```

In `build.zig`:

```zig
const c_kzg_dep = b.dependency("c_kzg", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("c_kzg", c_kzg_dep.module("c_kzg"));
exe.root_module.addImport("blst", c_kzg_dep.module("blst"));
exe.root_module.addImport("trusted_setup", c_kzg_dep.module("trusted_setup"));

const install_setup = b.addInstallFile(
    c_kzg_dep.namedLazyPath("trusted_setup"),
    "trusted_setup.txt",
);
b.getInstallStep().dependOn(&install_setup.step);
```

In Zig code:

```zig
const c = @import("c_kzg");
const blst = @import("blst"); // Only if you need direct blst access.
```

The exported `trusted_setup` module contains the decoded buffers expected by `load_trusted_setup`:

```zig
const c = @import("c_kzg");
const trusted_setup = @import("trusted_setup");

var settings: c.KZGSettings = undefined;
try expectOk(c.load_trusted_setup(
    &settings,
    trusted_setup.g1_monomial_bytes.ptr,
    trusted_setup.g1_monomial_bytes.len,
    trusted_setup.g1_lagrange_bytes.ptr,
    trusted_setup.g1_lagrange_bytes.len,
    trusted_setup.g2_monomial_bytes.ptr,
    trusted_setup.g2_monomial_bytes.len,
    0,
));
defer c.free_trusted_setup(&settings);
```

If you want the original upstream text file at runtime instead, keep using `dep.namedLazyPath("trusted_setup")`.

If you still want to use your own wrapper around the headers, `dep.artifact("c_kzg")` still installs the public header tree and can be linked directly.

## Build Options

| Option | Default | Description |
|--------|---------|-------------|
| `-Dportable` | false | Passed through to the package's build-time `blst.zig` dependency |
| `-Dfield_elements_per_blob` | 4096 | Override for non-mainnet |

## Tests

`zig build test` runs compile-time and C-API smoke tests against the exported embedded trusted setup module.

## License

Apache 2.0.
