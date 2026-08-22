// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_record_acl::acl_tests;

use miso::composition::{Self, Composition};
use miso::recording::{Self, Recording};
use miso::release::{Self, Release, ReleaseAdminCap};
use miso::track;
use miso_record::record::{Self, Record};
use miso_record::settings;
use miso_record_acl::acl;
use std::unit_test::destroy;
use sui::clock::{Self, Clock};

/// Stand-in for a sale package's minter witness.
public struct DemoMinter has drop {}

/// Stand-in share types. They are only ever phantom parameters, so they need no
/// abilities and are never instantiated. `SONG` is the composition's durable
/// identity; `MASTER` is the recording's.
public struct SONG {}
public struct MASTER {}

/// A nonce with no special meaning — the tests exercise the binding, not the
/// unguessability the nonce is there for.
const NONCE: vector<u8> = b"nonce";

fun id(addr: address): ID {
    object::id_from_address(addr)
}

/// A release holding one track per id in `recording_ids`, in order. Splits are
/// irrelevant to access, so every track takes an equal nominal share.
fun test_release(recording_ids: vector<ID>, ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    let tracks = recording_ids.map!(|rid| track::new_for_testing(rid, id(@0x0), 10_000));
    release::new_for_testing(b"Test Release".to_string(), tracks, ctx)
}

/// A record of `release_id`, minted through the authorized path.
fun test_record(release_id: ID, clk: &Clock, ctx: &mut TxContext): Record {
    let (mut cfg, cap) = settings::new_for_testing(ctx);
    settings::authorize<DemoMinter>(&mut cfg, &cap, ctx);
    let mut parent = object::new(ctx);
    let rec = record::mint<DemoMinter>(DemoMinter {}, &cfg, &mut parent, release_id, 1, clk, ctx);
    parent.delete();
    settings::destroy_for_testing(cfg, cap);
    rec
}

// === Identity ===

#[test]
fun an_identity_round_trips_to_its_subject() {
    let subject = id(@0xBEEF);

    assert!(acl::subject_of(acl::identity(subject, NONCE)) == subject);
    assert!(acl::subject_of(acl::identity(subject, b"")) == subject);
    // A nonce longer than one ULEB128 length byte still peels cleanly.
    let long = vector::tabulate!(300, |i| (i % 256) as u8);
    assert!(acl::subject_of(acl::identity(subject, long)) == subject);
}

#[test]
fun distinct_nonces_are_distinct_identities() {
    let subject = id(@0xBEEF);

    // Seal derives one key per identity, so this is what scopes a key to one
    // piece of material rather than to everything under the subject.
    assert!(acl::identity(subject, b"a") != acl::identity(subject, b"b"));
    assert!(acl::identity(subject, NONCE) != acl::identity(id(@0xCAFE), NONCE));
}

#[test, expected_failure(abort_code = acl::EMalformedIdentity)]
fun an_identity_with_trailing_bytes_aborts() {
    let mut id = acl::identity(id(@0xBEEF), NONCE);
    id.push_back(0);

    acl::subject_of(id);
}

#[test, expected_failure]
fun an_identity_too_short_to_name_a_subject_aborts() {
    // Peeling the subject runs off the end — the BCS reader aborts on its own.
    acl::subject_of(b"short");
}

// === Success ===

#[test]
fun approves_a_recording_on_the_records_release() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);
    let recording = id(@0xBEEF);

    let (rel, cap) = test_release(vector[recording, id(@0xCAFE)], &mut ctx);
    let rec = test_record(object::id(&rel), &clk, &mut ctx);

    acl::seal_approve_recording_for_testing(acl::identity(recording, NONCE), rec, &rel, &ctx);

    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}

#[test]
fun approves_a_recording_late_in_the_tracklist() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);
    let recording = id(@0xD15C2);

    // The target is the last of four tracks, so a scan that stopped early misses it.
    let (rel, cap) = test_release(vector[id(@0xA1), id(@0xA2), id(@0xB1), recording], &mut ctx);
    let rec = test_record(object::id(&rel), &clk, &mut ctx);

    acl::seal_approve_recording_for_testing(acl::identity(recording, NONCE), rec, &rel, &ctx);

    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}

#[test]
fun approves_a_copy_of_the_release() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);

    let (rel, cap) = test_release(vector[id(@0xA1), id(@0xA2)], &mut ctx);
    let rec = test_record(object::id(&rel), &clk, &mut ctx);

    acl::seal_approve_release_for_testing(acl::identity(object::id(&rel), NONCE), rec, &rel, &ctx);

    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}

#[test]
fun the_asserts_accept_a_matching_record() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);
    let recording = id(@0xBEEF);

    let (rel, cap) = test_release(vector[recording], &mut ctx);
    let rec = test_record(object::id(&rel), &clk, &mut ctx);

    acl::assert_grants_release(&rec, &rel);
    acl::assert_grants_recording(&rec, &rel, recording);

    record::destroy(rec, &ctx);
    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}

// === Composition ===
//
// Link 4 has no runtime negative test, and cannot have one: passing a
// `Composition<X>` alongside a `Recording<_, Y>` is a *type* error, so a
// mismatched pair fails to compile (and, in a PTB, fails type resolution before
// execution). The tests below cover links 2 and 3 as reached through the
// composition entry.

#[test]
fun approves_the_composition_behind_a_recording_on_the_release() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);

    let (comp, comp_cap) = composition::new_for_testing<SONG>(b"Song".to_string(), 1500, &mut ctx);
    let (rec_obj, rec_cap) = recording::new_for_testing<MASTER, SONG>(&mut ctx);

    // The release carries a track for this recording, alongside an unrelated one.
    let (rel, cap) = test_release(vector[id(@0xA1), object::id(&rec_obj)], &mut ctx);
    let record = test_record(object::id(&rel), &clk, &mut ctx);

    acl::seal_approve_composition_for_testing(
        acl::identity(object::id(&comp), NONCE),
        record,
        &rel,
        &rec_obj,
        &comp,
        &ctx,
    );

    destroy(comp);
    destroy(comp_cap);
    destroy(rec_obj);
    destroy(rec_cap);
    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}

#[test, expected_failure(abort_code = acl::ERecordingNotOnRelease)]
fun a_composition_reached_only_off_the_release_aborts() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);

    let (comp, comp_cap) = composition::new_for_testing<SONG>(b"Song".to_string(), 1500, &mut ctx);
    let (rec_obj, rec_cap) = recording::new_for_testing<MASTER, SONG>(&mut ctx);

    // The recording really is of this composition — it is just not on the release
    // the listener owns, so link 3 fails before link 4 is ever reached.
    let (rel, cap) = test_release(vector[id(@0xA1)], &mut ctx);
    let record = test_record(object::id(&rel), &clk, &mut ctx);

    acl::seal_approve_composition_for_testing(
        acl::identity(object::id(&comp), NONCE),
        record,
        &rel,
        &rec_obj,
        &comp,
        &ctx,
    );

    destroy(comp);
    destroy(comp_cap);
    destroy(rec_obj);
    destroy(rec_cap);
    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}

// === Failure ===

#[test, expected_failure(abort_code = acl::EWrongRelease)]
fun a_record_for_another_release_aborts() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);
    let recording = id(@0xBEEF);

    // The recording really is on this release — but the sender's record is a copy
    // of a different one, so link 2 fails.
    let (rel, cap) = test_release(vector[recording], &mut ctx);
    let (other, other_cap) = test_release(vector[recording], &mut ctx);
    let rec = test_record(object::id(&other), &clk, &mut ctx);

    acl::seal_approve_recording_for_testing(acl::identity(recording, NONCE), rec, &rel, &ctx);

    destroy(rel);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
    clk.destroy_for_testing();
}

#[test, expected_failure(abort_code = acl::EWrongRelease)]
fun a_record_for_another_release_fails_the_release_approval() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);

    let (rel, cap) = test_release(vector[id(@0xA1)], &mut ctx);
    let (other, other_cap) = test_release(vector[id(@0xA1)], &mut ctx);
    let rec = test_record(object::id(&other), &clk, &mut ctx);

    acl::seal_approve_release_for_testing(acl::identity(object::id(&rel), NONCE), rec, &rel, &ctx);

    destroy(rel);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
    clk.destroy_for_testing();
}

#[test, expected_failure(abort_code = acl::ERecordingNotOnRelease)]
fun a_recording_absent_from_the_release_aborts() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);

    // The sender owns a real copy of this release — it just does not contain the
    // recording being asked for, so link 3 fails.
    let (rel, cap) = test_release(vector[id(@0xA1), id(@0xA2)], &mut ctx);
    let rec = test_record(object::id(&rel), &clk, &mut ctx);

    acl::seal_approve_recording_for_testing(acl::identity(id(@0xDEAD), NONCE), rec, &rel, &ctx);

    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}

// === Identity binding ===
//
// Without these the policy fails open: a listener who legitimately holds a record
// presents it and collects the key for material they have no claim to.

#[test, expected_failure(abort_code = acl::EWrongSubject)]
fun an_identity_for_another_release_aborts() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);

    // The sender owns a genuine copy of `rel` — and asks for the key to `other`.
    let (rel, cap) = test_release(vector[id(@0xA1)], &mut ctx);
    let (other, other_cap) = test_release(vector[id(@0xA1)], &mut ctx);
    let rec = test_record(object::id(&rel), &clk, &mut ctx);

    acl::seal_approve_release_for_testing(acl::identity(object::id(&other), NONCE), rec, &rel, &ctx);

    destroy(rel);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
    clk.destroy_for_testing();
}

#[test, expected_failure(abort_code = acl::EWrongSubject)]
fun an_identity_for_another_composition_aborts() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);

    let (comp, comp_cap) = composition::new_for_testing<SONG>(b"Song".to_string(), 1500, &mut ctx);
    let (rec_obj, rec_cap) = recording::new_for_testing<MASTER, SONG>(&mut ctx);

    // Links 2, 3 and 4 all hold — the identity just names something else.
    let (rel, cap) = test_release(vector[object::id(&rec_obj)], &mut ctx);
    let record = test_record(object::id(&rel), &clk, &mut ctx);

    acl::seal_approve_composition_for_testing(
        acl::identity(id(@0xDEAD), NONCE),
        record,
        &rel,
        &rec_obj,
        &comp,
        &ctx,
    );

    destroy(comp);
    destroy(comp_cap);
    destroy(rec_obj);
    destroy(rec_cap);
    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}

#[test, expected_failure(abort_code = acl::EMalformedIdentity)]
fun a_malformed_identity_aborts_the_release_approval() {
    let mut ctx = tx_context::new_from_hint(@0xA, 0, 0, 0, 0);
    let clk = clock::create_for_testing(&mut ctx);

    let (rel, cap) = test_release(vector[id(@0xA1)], &mut ctx);
    let rec = test_record(object::id(&rel), &clk, &mut ctx);

    // The release id alone, with no nonce and no length byte: a key server would
    // happily derive a key for it, so the policy must not.
    let mut id = object::id(&rel).to_bytes();
    id.push_back(0);
    id.push_back(0);

    acl::seal_approve_release_for_testing(id, rec, &rel, &ctx);

    destroy(rel);
    destroy(cap);
    clk.destroy_for_testing();
}
