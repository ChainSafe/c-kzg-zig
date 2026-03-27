# c-kzg-zig

Zig build wrapper and bindings for [c-kzg-4844](https://github.com/ethereum/c-kzg-4844) — the C implementation of KZG commitments for EIP-4844 (blob transactions).

Structured similarly to [ChainSafe/blst.zig](https://github.com/ChainSafe/blst.zig).

## Features

- Compiles c-kzg-4844 C sources and blst entirely via the Zig build system — no external toolchain required
- Zig-idiomatic API wrapping all EIP-4844 and EIP-7594 (PeerDAS) operations
- Error union return types mapping C error codes to Zig errors
- Tested against the c-kzg-4844 trusted setup

## Requirements

- Zig 0.16.0-dev (zig-master)

## Usage

Add to your `build.zig.zon`:

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
const c_kzg_dep = b.dependency("c_kzg", .{ .target = target, .optimize = optimize });
const c_kzg_mod = c_kzg_dep.module("c_kzg");
exe.root_module.addImport("c_kzg", c_kzg_mod);
```

Then in your Zig code:

```zig
const kzg = @import("c_kzg");

// Load trusted setup
const settings = try kzg.loadTrustedSetupFile(allocator, "trusted_setup.txt");
defer kzg.freeTrustedSetup(allocator, settings);

// Compute commitment
var blob: kzg.Blob = [_]u8{0} ** kzg.BYTES_PER_BLOB;
const commitment = try kzg.blobToKzgCommitment(&blob, settings);

// Compute and verify proof
const proof = try kzg.computeBlobKzgProof(&blob, &commitment, settings);
const ok = try kzg.verifyBlobKzgProof(&blob, &commitment, &proof, settings);
```

## API

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `FIELD_ELEMENTS_PER_BLOB` | 4096 | Field elements per blob |
| `BYTES_PER_FIELD_ELEMENT` | 32 | Bytes per field element |
| `BYTES_PER_BLOB` | 131072 | Total blob size (4096 × 32) |
| `BYTES_PER_COMMITMENT` | 48 | KZG commitment size |
| `BYTES_PER_PROOF` | 48 | KZG proof size |
| `CELLS_PER_EXT_BLOB` | 128 | Cells in extended blob (EIP-7594) |

### EIP-4844 Functions

```zig
// Setup
fn loadTrustedSetupFile(allocator, path: []const u8) !*KzgSettings
fn loadTrustedSetup(allocator, g1_monomial, g1_lagrange, g2_monomial) !*KzgSettings
fn freeTrustedSetup(allocator, settings: *KzgSettings) void

// Blob operations
fn blobToKzgCommitment(blob: *const Blob, settings: *const KzgSettings) !KzgCommitment
fn computeKzgProof(blob, z: *const Bytes32, settings) !struct{ proof: KzgProof, y: Bytes32 }
fn computeBlobKzgProof(blob, commitment: *const KzgCommitment, settings) !KzgProof

// Verification
fn verifyKzgProof(commitment, z, y, proof, settings) !bool
fn verifyBlobKzgProof(blob, commitment, proof, settings) !bool
fn verifyBlobKzgProofBatch(blobs, commitments, proofs, settings) !bool
```

### EIP-7594 / PeerDAS Functions

```zig
fn computeCellsAndKzgProofs(blob, settings) !struct{ cells, proofs }
fn recoverCellsAndKzgProofs(cell_indices, cells, settings) !struct{ cells, proofs }
fn verifyCellKzgProofBatch(allocator, commitments_per_cell, cell_indices, cells, proofs, settings) !bool
```

### Errors

```zig
const KzgError = error{
    InvalidArgument,   // C_KZG_BADARGS
    KzgInternalError,  // C_KZG_ERROR
    OutOfMemory,       // C_KZG_MALLOC
};
```

## Build Options

| Option | Default | Description |
|--------|---------|-------------|
| `-Dportable` | false | Use portable blst (disable platform asm) |
| `-Dfield_elements_per_blob` | 4096 | Override for non-mainnet |

## Running Tests

Integration tests require the c-kzg-4844 trusted setup file:

```bash
# Run compile-only tests (no setup file needed)
zig build test

# Run all tests including integration tests
C_KZG_TRUSTED_SETUP_PATH=/path/to/trusted_setup.txt zig build test
```

The trusted setup file is available in the [c-kzg-4844 repository](https://github.com/ethereum/c-kzg-4844/blob/main/src/trusted_setup.txt).

## License

Apache 2.0 — same as c-kzg-4844.
