// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Seal access policies for data associated with Miso Compositions,
/// Recordings, and Releases.
///
/// A caller supplies a `&Record` and the Release named by that Record. Release
/// access is bound directly to that Release. Composition and Recording access
/// additionally select one track and bind its member ID to the supplied object.
module miso_record_seal_policy::policy;

use miso::composition::Composition;
use miso::recording::Recording;
use miso::release::Release;
use miso_record::record::{Self, Record};
use sui::bcs;

// === Errors ===

#[error]
const EInvalidIdentityLength: vector<u8> = b"Seal identity has the wrong length";

#[error]
const EWrongRelease: vector<u8> = b"Record or Seal identity names a different Release";

#[error]
const EInvalidTrackIndex: vector<u8> = b"Seal identity track index is outside the Release";

#[error]
const EWrongComposition: vector<u8> =
    b"Seal identity does not name the supplied Composition at the selected track";

#[error]
const EWrongRecording: vector<u8> =
    b"Seal identity does not name the supplied Recording at the selected track";

// === Seal policies ===

/// Approve data for the Composition at one track of the Record's Release.
entry fun seal_approve_composition<CompositionShare>(
    id: vector<u8>,
    record: &Record,
    release: &Release,
    composition: &Composition<CompositionShare>,
) {
    let (release_id, track_idx, composition_id) = parse_track_member_identity(id);
    assert_record_release(record, release, release_id);

    let tracks = release.tracks();
    assert!(track_idx < tracks.length(), EInvalidTrackIndex);
    let track = &tracks[track_idx];
    assert!(track.composition_id() == composition_id, EWrongComposition);
    assert!(object::id(composition) == composition_id, EWrongComposition);
}

/// Approve data for the Recording at one track of the Record's Release.
entry fun seal_approve_recording<RecordingShare, CompositionShare>(
    id: vector<u8>,
    record: &Record,
    release: &Release,
    recording: &Recording<RecordingShare, CompositionShare>,
) {
    let (release_id, track_idx, recording_id) = parse_track_member_identity(id);
    assert_record_release(record, release, release_id);

    let tracks = release.tracks();
    assert!(track_idx < tracks.length(), EInvalidTrackIndex);
    let track = &tracks[track_idx];
    assert!(track.recording_id() == recording_id, EWrongRecording);
    assert!(object::id(recording) == recording_id, EWrongRecording);
}

/// Approve data for the Record's Release.
entry fun seal_approve_release(id: vector<u8>, record: &Record, release: &Release) {
    assert!(id.length() == 32, EInvalidIdentityLength);

    let mut reader = bcs::new(id);
    let release_id = reader.peel_address().to_id();
    assert_record_release(record, release, release_id);
}

fun parse_track_member_identity(id: vector<u8>): (ID, u64, ID) {
    assert!(id.length() == 65, EInvalidIdentityLength);

    let mut reader = bcs::new(id);
    let release_id = reader.peel_address().to_id();
    let track_idx = reader.peel_u8() as u64;
    let member_id = reader.peel_address().to_id();
    (release_id, track_idx, member_id)
}

fun assert_record_release(record: &Record, release: &Release, release_id: ID) {
    assert!(object::id(release) == release_id, EWrongRelease);
    assert!(record.release_id() == release_id, EWrongRelease);
}

// === Test helpers ===

#[test_only]
public fun seal_approve_composition_for_testing<CompositionShare>(
    id: vector<u8>,
    record: &Record,
    release: &Release,
    composition: &Composition<CompositionShare>,
) {
    seal_approve_composition(id, record, release, composition)
}

#[test_only]
public fun seal_approve_recording_for_testing<RecordingShare, CompositionShare>(
    id: vector<u8>,
    record: &Record,
    release: &Release,
    recording: &Recording<RecordingShare, CompositionShare>,
) {
    seal_approve_recording(id, record, release, recording)
}

#[test_only]
public fun seal_approve_release_for_testing(
    id: vector<u8>,
    record: &Record,
    release: &Release,
) {
    seal_approve_release(id, record, release)
}
