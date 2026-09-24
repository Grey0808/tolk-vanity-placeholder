# tolk-vanity-placeholder

**English** · [Русский](README.ru.md)

A tiny TON contract, written in Tolk, that holds a chosen ("vanity") address
until your real contract is installed at it.

A TON address is the hash of the contract's initial code and data, fixed for
good. To get an address like `EQC…----Gold` you try salts until the hash comes
out right. Doing that against your real contract is awkward: every salt found
is lost the moment the contract's code changes, and its data is usually too
big for a fast GPU searcher. So you search against this placeholder instead:

- its code never changes;
- its data is 40 bytes — your ed25519 public key and a 64-bit salt — which
  hash in a single SHA-256 block;
- one external message signed with your key turns it into your real contract:
  the address, the balance and the jetton wallets stay.

## Files

| file | what it is |
|---|---|
| `vanity-placeholder.tolk` | the contract |
| `PROMPT.md` | the full technical brief — layouts, address arithmetic, test vectors, a TypeScript sketch, the safety checklist. Give it to an AI assistant, or read it yourself before writing code |
| `README.md`, `README.ru.md` | this overview |

## How to use it

1. **Compile once and freeze the result.**
   `npx @ton/tolk-js@1.4.2 -o placeholder.json vanity-placeholder.tolk`
   The code hash must be
   `b16b8b2cefaf342581684f59056ec1bd282e3428fb06327de53a4a737a60e497`
   (Tolk 1.4.2; Acton 1.2.0 gives the same). Keep this exact code BOC: the
   code hash is part of every address, and a different build means different
   addresses.
2. **Search for a salt.** Give your searcher:
   `BUF1_LEN=42 SALT_OFF=34 SALT_LEN=8`, the code hash and code depth `4`, and
   the data template `0050` + your 32-byte public key + 8 zero bytes. Check it
   against the test vectors in `PROMPT.md` first. Decide whether the pattern is
   for the `EQ…` or the `UQ…` form: their last four characters differ.
3. **Check the address** the salt gives with your SDK
   (`contractAddress(0, { code, data })`), not only with the searcher.
4. **Fund it** with a **non-bounceable** (`UQ…`) transfer. A bounceable one
   comes back from an address with nothing deployed.
5. **Rehearse the install** in an emulator or sandbox: the external message
   with the placeholder's StateInit and a `Become` carrying your contract's
   code and full initial data, then your contract's own withdrawal on the
   result. Send only if the withdrawal works.
6. **Send the one external message.** In a single transaction the account is
   deployed as the placeholder and becomes your contract.

## Safety, in short

- Only your key can install anything, only at this address, and only until the
  request's `valid_until`. Every check runs before the message is accepted, so
  a refused request costs nothing.
- The placeholder has no withdrawal of its own: until the install, the key is
  the only way to the money. Lose it and the funds are gone.
- Your contract's data is installed as is — no constructor runs.
- Your contract must refuse the same signed message if it is replayed at it
  after the install (any contract that checks its own signed layout does).
- An external message is limited to 65,535 bytes: your code and data must fit.

All of it, with the reasons, is in `PROMPT.md`.

## Related

[ton-community/vanity-contract](https://github.com/ton-community/vanity-contract)
does the same with an owner wallet address and an internal message. This one
uses a key, deploys and installs in one external message, and keeps the data
to one SHA-256 block.

## License

MIT, see `LICENSE`.
