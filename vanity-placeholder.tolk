// SPDX-License-Identifier: MIT
//
// Vanity placeholder: a tiny contract that holds a chosen address until the
// real contract is installed at it.
//
// An account's address is the hash of the code and data it was created with,
// fixed for good. To give a contract an address that reads the way you want,
// you try salts until that hash comes out right. Searching against the real
// contract has two problems: every salt found is lost the moment its code
// changes, and its data is usually too long, or has references, for a fast
// searcher that hashes one flat 55-byte SHA-256 block.
//
// So the search runs against this instead: code that never changes and 40
// bytes of data, an ed25519 public key and a 64-bit salt. Deployed at the
// address the search found, it waits; one external message signed with that
// key installs any code and data you choose, and it is never this contract
// again. The address, the balance and every jetton wallet derived from the
// address stay where they are.
//
// The compiled code is part of every address found. Compile it once, keep the
// BOC, and never deploy anything but that exact BOC — see README.md.

import "@stdlib/gas-payments"

enum VanityErrors {
    /// The signature is not the key's, over the Become cell's hash.
    BadSignature = 201
    /// The install names another placeholder: the same key may hold several,
    /// and an install signed for one must not work on the rest.
    NotForThis = 202
    /// The install is past its validUntil.
    Expired = 203
}

/// What the placeholder is deployed with, and all it keeps: 320 bits, no
/// references, so the data cell's representation is 42 bytes and hashes in one
/// SHA-256 block. The salt is its last 8 bytes, big-endian.
struct VanityStorage {
    /// The only key that can install anything here.
    publicKey: uint256
    /// There only to move the address.
    salt: uint64
}

/// The one request the placeholder takes: become this code and data.
///
/// The external message body is a 512-bit ed25519 signature followed by this
/// cell as a reference; the signature is over the cell's hash. The 32-bit
/// prefix is "vany" in ASCII.
struct (0x76616e79) Become {
    /// This placeholder's own address.
    to: address
    /// Unix time; the install is refused from then on.
    validUntil: uint32
    /// What the account runs after this transaction, and the data it starts
    /// with.
    code: cell
    data: cell
}

contract VanityPlaceholder {
    author: "tolk-vanity-placeholder"
    version: "1.0.0"
    description: "Holds a chosen address until the real contract is installed at it"
    storage: VanityStorage
}

fun onInternalMessage(in: InMessage) {
    // Toncoin arriving: the deploy, and the balance the install will spend.
    // Kept, whatever it carries; there is nothing else this contract acts on.
}

fun onExternalMessage(inMsg: slice) {
    var body = inMsg;
    val signature = body.loadBits(512);
    val signed = body.loadRef();

    // Every check runs before the message is accepted, so a refused request
    // costs the balance nothing: the network drops it.
    val storage = lazy VanityStorage.fromCell(contract.getData());
    assert (isSignatureValid(signed.hash(), signature, storage.publicKey)) throw VanityErrors.BadSignature;
    val req = Become.fromCell(signed);
    assert (req.to == contract.getAddress()) throw VanityErrors.NotForThis;
    assert (blockchain.now() < req.validUntil) throw VanityErrors.Expired;
    acceptExternalMessage();

    // The new code runs from the next transaction on; the new data is in
    // place now. Nothing here guards against the same request twice: once
    // this transaction commits, the code that would honour it is gone. The
    // code installed must refuse this message itself, before accepting it.
    contract.setCodePostponed(req.code);
    contract.setData(req.data);
}

get fun publicKey(): int {
    val storage = lazy VanityStorage.fromCell(contract.getData());
    return storage.publicKey;
}

get fun salt(): int {
    val storage = lazy VanityStorage.fromCell(contract.getData());
    return storage.salt;
}
