/// Zig bindings for c-kzg-4844.
///
/// Wraps the C API with idiomatic Zig types, error handling, and safety.
/// All C types are mapped to Zig equivalents; KZGSettings is heap-allocated
/// and must be freed with freeTrustedSetup().

const std = @import("std");

// ---------------------------------------------------------------------------
// Raw C bindings
// ---------------------------------------------------------------------------

const c = @cImport({
    @cInclude("ckzg.h");
});

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

pub const BYTES_PER_FIELD_ELEMENT: usize = 32;
pub const FIELD_ELEMENTS_PER_BLOB: usize = 4096;
pub const BYTES_PER_BLOB: usize = FIELD_ELEMENTS_PER_BLOB * BYTES_PER_FIELD_ELEMENT;
pub const BYTES_PER_COMMITMENT: usize = 48;
pub const BYTES_PER_PROOF: usize = 48;

/// Number of field elements per cell (EIP-7594 / PeerDAS).
pub const FIELD_ELEMENTS_PER_CELL: usize = 64;
pub const BYTES_PER_CELL: usize = FIELD_ELEMENTS_PER_CELL * BYTES_PER_FIELD_ELEMENT;
pub const CELLS_PER_BLOB: usize = FIELD_ELEMENTS_PER_BLOB / FIELD_ELEMENTS_PER_CELL;
pub const CELLS_PER_EXT_BLOB: usize = CELLS_PER_BLOB * 2;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Raw blob bytes (131_072 bytes for mainnet).
pub const Blob = [BYTES_PER_BLOB]u8;

/// A 48-byte KZG commitment.
pub const KzgCommitment = [BYTES_PER_COMMITMENT]u8;

/// A 48-byte KZG proof.
pub const KzgProof = [BYTES_PER_PROOF]u8;

/// A 32-byte BLS scalar field element.
pub const Bytes32 = [32]u8;

/// A single data availability cell (EIP-7594).
pub const Cell = [BYTES_PER_CELL]u8;

/// Opaque trusted setup handle.
///
/// Callers receive a *KzgSettings from loadTrustedSetup* and must pass it to
/// freeTrustedSetup when done.
pub const KzgSettings = c.KZGSettings;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

pub const KzgError = error{
    /// The supplied data is invalid in some way.
    InvalidArgument,
    /// Internal error — should not occur in correct usage.
    KzgInternalError,
    /// Memory allocation failed.
    OutOfMemory,
};

fn mapRet(ret: c.C_KZG_RET) KzgError!void {
    return switch (ret) {
        c.C_KZG_OK => {},
        c.C_KZG_BADARGS => KzgError.InvalidArgument,
        c.C_KZG_ERROR => KzgError.KzgInternalError,
        c.C_KZG_MALLOC => KzgError.OutOfMemory,
        else => KzgError.KzgInternalError,
    };
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

/// Load a trusted setup from a file path.
///
/// The returned *KzgSettings is heap-allocated by c-kzg-4844 internals.
/// The caller MUST call freeTrustedSetup() when done.
pub fn loadTrustedSetupFile(allocator: std.mem.Allocator, path: []const u8) (KzgError || error{FileOpenFailed})!*KzgSettings {
    const settings = try allocator.create(KzgSettings);
    errdefer allocator.destroy(settings);

    // Need null-terminated path for fopen.
    const path_z = allocator.dupeZ(u8, path) catch return KzgError.OutOfMemory;
    defer allocator.free(path_z);

    const file = c.fopen(path_z.ptr, "r") orelse return error.FileOpenFailed;
    defer _ = c.fclose(file);

    try mapRet(c.load_trusted_setup_file(settings, file, 0));
    return settings;
}

/// Load trusted setup from raw byte slices (for embedding).
///
/// - g1_monomial_bytes: G1 points in monomial form
/// - g1_lagrange_bytes: G1 points in Lagrange form
/// - g2_monomial_bytes: G2 points in monomial form
pub fn loadTrustedSetup(
    allocator: std.mem.Allocator,
    g1_monomial_bytes: []const u8,
    g1_lagrange_bytes: []const u8,
    g2_monomial_bytes: []const u8,
) KzgError!*KzgSettings {
    const settings = try allocator.create(KzgSettings);
    errdefer allocator.destroy(settings);

    try mapRet(c.load_trusted_setup(
        settings,
        g1_monomial_bytes.ptr,
        @intCast(g1_monomial_bytes.len),
        g1_lagrange_bytes.ptr,
        @intCast(g1_lagrange_bytes.len),
        g2_monomial_bytes.ptr,
        @intCast(g2_monomial_bytes.len),
        0,
    ));
    return settings;
}

/// Free a trusted setup previously returned by loadTrustedSetupFile or
/// loadTrustedSetup.
pub fn freeTrustedSetup(allocator: std.mem.Allocator, settings: *KzgSettings) void {
    c.free_trusted_setup(settings);
    allocator.destroy(settings);
}

// ---------------------------------------------------------------------------
// EIP-4844 API
// ---------------------------------------------------------------------------

/// Compute the KZG commitment for a blob.
pub fn blobToKzgCommitment(blob: *const Blob, settings: *const KzgSettings) KzgError!KzgCommitment {
    var out: c.KZGCommitment = undefined;
    try mapRet(c.blob_to_kzg_commitment(
        &out,
        @ptrCast(blob),
        settings,
    ));
    return out.bytes;
}

/// Compute a KZG proof for a blob at an evaluation point z.
///
/// Returns (proof, y) where y = p(z).
pub fn computeKzgProof(
    blob: *const Blob,
    z: *const Bytes32,
    settings: *const KzgSettings,
) KzgError!struct { proof: KzgProof, y: Bytes32 } {
    var proof_out: c.KZGProof = undefined;
    var y_out: c.Bytes32 = undefined;
    try mapRet(c.compute_kzg_proof(
        &proof_out,
        &y_out,
        @ptrCast(blob),
        @ptrCast(z),
        settings,
    ));
    return .{ .proof = proof_out.bytes, .y = y_out.bytes };
}

/// Compute a blob KZG proof (proof for the entire blob at the Fiat-Shamir challenge).
pub fn computeBlobKzgProof(
    blob: *const Blob,
    commitment: *const KzgCommitment,
    settings: *const KzgSettings,
) KzgError!KzgProof {
    var out: c.KZGProof = undefined;
    const commitment_bytes = c.Bytes48{ .bytes = commitment.* };
    try mapRet(c.compute_blob_kzg_proof(
        &out,
        @ptrCast(blob),
        &commitment_bytes,
        settings,
    ));
    return out.bytes;
}

/// Verify a KZG proof: check that p(z) == y for the committed polynomial p.
pub fn verifyKzgProof(
    commitment: *const KzgCommitment,
    z: *const Bytes32,
    y: *const Bytes32,
    proof: *const KzgProof,
    settings: *const KzgSettings,
) KzgError!bool {
    var ok: bool = false;
    try mapRet(c.verify_kzg_proof(
        &ok,
        @ptrCast(commitment),
        @ptrCast(z),
        @ptrCast(y),
        @ptrCast(proof),
        settings,
    ));
    return ok;
}

/// Verify a blob KZG proof.
pub fn verifyBlobKzgProof(
    blob: *const Blob,
    commitment: *const KzgCommitment,
    proof: *const KzgProof,
    settings: *const KzgSettings,
) KzgError!bool {
    var ok: bool = false;
    try mapRet(c.verify_blob_kzg_proof(
        &ok,
        @ptrCast(blob),
        @ptrCast(commitment),
        @ptrCast(proof),
        settings,
    ));
    return ok;
}

/// Batch-verify multiple blob KZG proofs.
///
/// All three slices must have the same length.
pub fn verifyBlobKzgProofBatch(
    blobs: []const Blob,
    commitments: []const KzgCommitment,
    proofs: []const KzgProof,
    settings: *const KzgSettings,
) KzgError!bool {
    if (blobs.len != commitments.len or blobs.len != proofs.len) {
        return KzgError.InvalidArgument;
    }
    var ok: bool = false;
    try mapRet(c.verify_blob_kzg_proof_batch(
        &ok,
        @ptrCast(blobs.ptr),
        @ptrCast(commitments.ptr),
        @ptrCast(proofs.ptr),
        @intCast(blobs.len),
        settings,
    ));
    return ok;
}

// ---------------------------------------------------------------------------
// EIP-7594 / PeerDAS API
// ---------------------------------------------------------------------------

/// Compute all cells and their KZG proofs for a blob.
///
/// Returns cells[CELLS_PER_EXT_BLOB] and proofs[CELLS_PER_EXT_BLOB].
pub fn computeCellsAndKzgProofs(
    blob: *const Blob,
    settings: *const KzgSettings,
) KzgError!struct {
    cells: [CELLS_PER_EXT_BLOB]Cell,
    proofs: [CELLS_PER_EXT_BLOB]KzgProof,
} {
    var cells: [CELLS_PER_EXT_BLOB]c.Cell = undefined;
    var proofs: [CELLS_PER_EXT_BLOB]c.KZGProof = undefined;

    try mapRet(c.compute_cells_and_kzg_proofs(
        &cells,
        &proofs,
        @ptrCast(blob),
        settings,
    ));

    var out_cells: [CELLS_PER_EXT_BLOB]Cell = undefined;
    var out_proofs: [CELLS_PER_EXT_BLOB]KzgProof = undefined;
    for (0..CELLS_PER_EXT_BLOB) |i| {
        @memcpy(&out_cells[i], &cells[i].bytes);
        out_proofs[i] = proofs[i].bytes;
    }
    return .{ .cells = out_cells, .proofs = out_proofs };
}

/// Recover all cells and their KZG proofs from a subset of cells.
///
/// - cell_indices: indices (0..CELLS_PER_EXT_BLOB) of the provided cells
/// - cells: the corresponding cell data (same length as cell_indices)
/// - cells.len must be <= CELLS_PER_EXT_BLOB
pub fn recoverCellsAndKzgProofs(
    cell_indices: []const u64,
    cells: []const Cell,
    settings: *const KzgSettings,
) KzgError!struct {
    cells: [CELLS_PER_EXT_BLOB]Cell,
    proofs: [CELLS_PER_EXT_BLOB]KzgProof,
} {
    if (cell_indices.len != cells.len) return KzgError.InvalidArgument;
    if (cells.len > CELLS_PER_EXT_BLOB) return KzgError.InvalidArgument;

    // Copy into a fixed C-compatible buffer.
    var c_cells_buf: [CELLS_PER_EXT_BLOB]c.Cell = undefined;
    for (cells, 0..) |*cell, i| {
        @memcpy(&c_cells_buf[i].bytes, cell);
    }

    var out_cells: [CELLS_PER_EXT_BLOB]c.Cell = undefined;
    var out_proofs: [CELLS_PER_EXT_BLOB]c.KZGProof = undefined;

    try mapRet(c.recover_cells_and_kzg_proofs(
        &out_cells,
        &out_proofs,
        cell_indices.ptr,
        &c_cells_buf,
        @intCast(cell_indices.len),
        settings,
    ));

    var result_cells: [CELLS_PER_EXT_BLOB]Cell = undefined;
    var result_proofs: [CELLS_PER_EXT_BLOB]KzgProof = undefined;
    for (0..CELLS_PER_EXT_BLOB) |i| {
        @memcpy(&result_cells[i], &out_cells[i].bytes);
        result_proofs[i] = out_proofs[i].bytes;
    }
    return .{ .cells = result_cells, .proofs = result_proofs };
}

/// Batch-verify cell KZG proofs.
///
/// - allocator: used for a temporary buffer (freed before return)
/// - commitments_per_cell: one KzgCommitment per cell (same length as cells)
/// - cell_indices: which cell index (0..CELLS_PER_EXT_BLOB) within the extended blob
/// - cells: the cell data
/// - proofs: the KZG proof for each cell
///
/// All slices must have the same length (num_cells).
pub fn verifyCellKzgProofBatch(
    allocator: std.mem.Allocator,
    commitments_per_cell: []const KzgCommitment,
    cell_indices: []const u64,
    cells: []const Cell,
    proofs: []const KzgProof,
    settings: *const KzgSettings,
) (KzgError || error{OutOfMemory})!bool {
    if (commitments_per_cell.len != cells.len or
        cell_indices.len != cells.len or
        cells.len != proofs.len)
    {
        return KzgError.InvalidArgument;
    }

    // Heap-allocate the C cell buffer to avoid large stack frames.
    const c_cells_buf = try allocator.alloc(c.Cell, cells.len);
    defer allocator.free(c_cells_buf);
    for (cells, 0..) |*cell, i| {
        @memcpy(&c_cells_buf[i].bytes, cell);
    }

    var ok: bool = false;
    try mapRet(c.verify_cell_kzg_proof_batch(
        &ok,
        @ptrCast(commitments_per_cell.ptr),
        cell_indices.ptr,
        c_cells_buf.ptr,
        @ptrCast(proofs.ptr),
        @intCast(cells.len),
        settings,
    ));
    return ok;
}
