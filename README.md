# c-kzg-zig

Zig build packaging for [c-kzg-4844](https://github.com/ethereum/c-kzg-4844).

This package exports:

- the `c_kzg` C library artifact
- the c-kzg public headers, installed on that artifact
- `trusted_setup.txt` as a named lazy path

This package does not export a handwritten Zig wrapper module. Consumers are expected to add their own wrapper, and to add `blst.zig` separately for final linking.

## Requirements

- Zig 0.16.0-dev

## Public Surface

From a dependency handle:

- `dep.artifact("c_kzg")`
- `dep.namedLazyPath("trusted_setup")`

The `c_kzg` artifact installs:

- the full c-kzg public header tree
- `blst.h` and related installed headers forwarded from `blst.zig`

That means a consumer wrapper module can `@cImport("ckzg.h")` after linking against `dep.artifact("c_kzg")`.

## Usage

Add dependencies to `build.zig.zon`:

```zon
.dependencies = .{
    .c_kzg = .{
        .url = "https://github.com/ChainSafe/c-kzg-zig/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "<hash>",
    },
    .blst = .{
        .url = "git+https://github.com/lodekeeper-z/blst.zig.git#254f2869b9c72b7f70900b41ec90213807c7a675",
        .hash = "blst_zig-0.0.0-cnAxzg4LAACIXTmj0X4unkf0FCYcFTZVzDdWE32PZl_A",
    },
},
```

That `blst` ref is the head commit of [ChainSafe/blst.zig PR #4](https://github.com/ChainSafe/blst.zig/pull/4), which contains the Zig 0.16 build updates.

In `build.zig`:

```zig
const c_kzg_dep = b.dependency("c_kzg", .{
    .target = target,
    .optimize = optimize,
});
const blst_dep = b.dependency("blst", .{
    .target = target,
    .optimize = optimize,
});

const kzg_wrapper = b.addModule("kzg_wrapper", .{
    .root_source_file = b.path("src/kzg_wrapper.zig"),
    .target = target,
    .optimize = optimize,
});
kzg_wrapper.linkLibrary(c_kzg_dep.artifact("c_kzg"));

exe.root_module.addImport("kzg_wrapper", kzg_wrapper);
exe.root_module.linkLibrary(blst_dep.artifact("blst"));

const install_setup = b.addInstallFile(
    c_kzg_dep.namedLazyPath("trusted_setup"),
    "trusted_setup.txt",
);
b.getInstallStep().dependOn(&install_setup.step);
```

In your wrapper module:

```zig
pub const c = @cImport({
    @cInclude("ckzg.h");
});
```

If you want to embed the trusted setup instead of installing it as a runtime file, use `dep.namedLazyPath("trusted_setup")` as the source of that build step.

## Build Options

| Option | Default | Description |
|--------|---------|-------------|
| `-Dportable` | false | Passed through to the package's build-time `blst.zig` dependency |
| `-Dfield_elements_per_blob` | 4096 | Override for non-mainnet |

## Tests

`zig build test` runs compile-time and C-API smoke tests. Integration tests are enabled when `C_KZG_TRUSTED_SETUP_PATH` is set:

```bash
C_KZG_TRUSTED_SETUP_PATH=/path/to/trusted_setup.txt zig build test
```

## License

Apache 2.0.
