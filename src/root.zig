/// c-kzg-zig: Zig build wrapper and bindings for c-kzg-4844.
///
/// Re-export the main bindings module.
pub const c_kzg = @import("c_kzg.zig");

// Re-export all public declarations from c_kzg.zig for convenience.
pub const BYTES_PER_FIELD_ELEMENT = c_kzg.BYTES_PER_FIELD_ELEMENT;
pub const FIELD_ELEMENTS_PER_BLOB = c_kzg.FIELD_ELEMENTS_PER_BLOB;
pub const BYTES_PER_BLOB = c_kzg.BYTES_PER_BLOB;
pub const BYTES_PER_COMMITMENT = c_kzg.BYTES_PER_COMMITMENT;
pub const BYTES_PER_PROOF = c_kzg.BYTES_PER_PROOF;
pub const FIELD_ELEMENTS_PER_CELL = c_kzg.FIELD_ELEMENTS_PER_CELL;
pub const BYTES_PER_CELL = c_kzg.BYTES_PER_CELL;
pub const CELLS_PER_BLOB = c_kzg.CELLS_PER_BLOB;
pub const CELLS_PER_EXT_BLOB = c_kzg.CELLS_PER_EXT_BLOB;

pub const Blob = c_kzg.Blob;
pub const KzgCommitment = c_kzg.KzgCommitment;
pub const KzgProof = c_kzg.KzgProof;
pub const Bytes32 = c_kzg.Bytes32;
pub const Cell = c_kzg.Cell;
pub const KzgSettings = c_kzg.KzgSettings;
pub const KzgError = c_kzg.KzgError;

pub const loadTrustedSetupFile = c_kzg.loadTrustedSetupFile;
pub const loadTrustedSetup = c_kzg.loadTrustedSetup;
pub const freeTrustedSetup = c_kzg.freeTrustedSetup;
pub const blobToKzgCommitment = c_kzg.blobToKzgCommitment;
pub const computeKzgProof = c_kzg.computeKzgProof;
pub const computeBlobKzgProof = c_kzg.computeBlobKzgProof;
pub const verifyKzgProof = c_kzg.verifyKzgProof;
pub const verifyBlobKzgProof = c_kzg.verifyBlobKzgProof;
pub const verifyBlobKzgProofBatch = c_kzg.verifyBlobKzgProofBatch;
pub const computeCellsAndKzgProofs = c_kzg.computeCellsAndKzgProofs;
pub const recoverCellsAndKzgProofs = c_kzg.recoverCellsAndKzgProofs;
pub const verifyCellKzgProofBatch = c_kzg.verifyCellKzgProofBatch;
