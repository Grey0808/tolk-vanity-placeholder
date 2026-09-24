# Vanity placeholder — technical brief for an AI assistant

You are helping someone give a TON smart contract a chosen ("vanity") address
using the placeholder in `vanity-placeholder.tolk`. Read all of this before
writing code or giving instructions. Money is involved: a mistake in the
address, the key or the installed code can lock funds for good.

## 1. The idea

A TON address is `sha256` of the account's initial StateInit (code + data),
and it never changes afterwards, even when the code does. So:

1. Search for a salt that makes the **placeholder's** address look the way the
   user wants. The placeholder's code never changes, and its data is only 40
   bytes: an ed25519 public key and a 64-bit salt.
2. Fund that address.
3. Send one external message, signed with the key, that makes the placeholder
   set its code and data to the user's real contract (`Become`).

The address, the balance and every jetton wallet derived from the address
stay. The real contract's code and data do not affect the address at all.

## 2. The contract's interface

### Storage (data cell): 320 bits, no references

```
VanityStorage { publicKey: uint256, salt: uint64 }
```

### Become (the only request)

```
become#76616e79 to:MsgAddressInt valid_until:uint32 code:^Cell data:^Cell = Become;
```

- `to` must be the placeholder's own address, written as a plain `addr_std`
  (`10`, anycast `0`, workchain int8, 256-bit hash).
- `valid_until` is a unix time; the request is refused at or after it.
- `code` and `data` are what the account runs and holds afterwards. `data` is
  the real contract's **complete initial storage**: no constructor or deploy
  handler of the real contract ever runs.

### External message body

```
signature:bits512  ^Become
```

`signature = ed25519_sign(become_cell.hash(), secretKey)`, the cell hash as TON
defines it (the representation hash, not a hash of a BOC).

### What happens

Handled in `onExternalMessage`, all checks **before** `acceptExternalMessage()`,
so a refused request costs nothing and does not appear on chain:

| exit code | meaning |
|---|---|
| 201 | signature is not the stored key's over the Become hash |
| 202 | `to` is not this contract's address |
| 203 | `now >= valid_until` |
| 9 or similar | the body or the Become cell is malformed |

Then `setCodePostponed(code)` (takes effect after this transaction) and
`setData(data)` (takes effect now). Internal messages are accepted and kept,
whatever they carry: that is how it is funded.

Get-methods: `publicKey()`, `salt()`.

### Reference build

| | |
|---|---|
| compilers checked | `@ton/tolk-js` 1.4.2 and Acton 1.2.0 (16d49e1) |
| code hash | `b16b8b2cefaf342581684f59056ec1bd282e3428fb06327de53a4a737a60e497` |
| code depth | 4 |
| code BOC (base64) | `te6ccgEBCAEAfAABFP8A9KQT9LzyyAsBAgEgAgMCAUgEBQB68oMI1xjXTO1E0NcL/yH5AEAz+RDy4MnQ1ywjswtzzPK/+kjTH9TU0fgoFMcF8uDK+CNYufLgy/gA+wTtVAAM0DD4kfJAAgFIBgcAF7habtRNDT/zHXCz+AARuR+O1E0NcL/4` |

Comments do not change the code; any change to the logic, or another compiler
version, may. **The code hash is part of every address found.** Compile once,
check the hash, keep the BOC, and use that exact BOC for the search, the
address check and the deployment. Never recompile between them.

## 3. Address arithmetic, for a salt searcher

Two SHA-256 computations. Workchain 0 below.

**Buffer 1: the data cell's representation, 42 bytes, one SHA-256 block.**

```
offset 0     1     2 ................ 33   34 ........ 41
       d1=00 d2=50 publicKey (32 bytes)   salt (8 bytes, big-endian)
```

`d1 = 0x00`: no references. `d2 = 0x50 = 80 = floor(320/8) + ceil(320/8)`: 40
whole bytes, so there is no completion-tag byte. Searcher parameters:
`BUF1_LEN=42 SALT_OFF=34 SALT_LEN=8`. `dataHash = sha256(buffer1)`.

**Buffer 2: the StateInit's representation, 71 bytes, two blocks.**

```
02 01 34 | codeDepth:uint16 = 00 04 | dataDepth:uint16 = 00 00 | codeHash (32) | dataHash (32)
```

`02`: two references. `01`: 5 data bits in one byte. `34` = bits `00110` plus
the completion tag: no split_depth, not special, code present, data present,
no library. `address hash = sha256(buffer2)`.

**Precomputation.** In buffer 1's block, words W0..W7 (bytes 0–31) do not
depend on the salt, W8 holds only the salt's two high bytes, W9–W10 hold the
rest; W11–W14 are zero and W15 is the length, 336 = 0x150. Rounds 0–7 are
constant, and round 8 too while the salt's high two bytes do not change. In
buffer 2's first block, W0..W8 (bytes 0–35) are constant.

**User-friendly form** (36 bytes → 48 base64url characters):

```
flag (0x11 bounceable "EQ…", 0x51 non-bounceable "UQ…") | workchain byte | hash (32) | crc16-xmodem of the first 34 bytes (2)
```

- The 3rd character carries only the top 2 bits of `hash[0]`, so on workchain
  0 it is always one of `A B C D`. A free prefix starts at character 4.
- Characters 4–44 are hash bits only, the same in both forms.
- The last 4 characters hold `hash[31]` and the CRC. The CRC covers the flag
  byte, so **the EQ and UQ forms end differently**. Decide which form the
  pattern is for. Explorers and wallets usually show a contract with code as
  EQ…; search the EQ form unless the user says otherwise.

### Test vectors

Public key of the all-zero ed25519 seed:
`3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29`, with the
reference code hash above.

| salt | data hash | address (raw) | EQ | UQ |
|---|---|---|---|---|
| `0x0` | `695754e5…3dbd5636` | `0:02a38cd37c88ea3172e9ad9840cc400dab63b6687259b70f63f3fd1172f8e2d6` | `EQACo4zTfIjqMXLprZhAzEANq2O2aHJZtw9j8_0Rcvji1t1v` | `UQACo4zTfIjqMXLprZhAzEANq2O2aHJZtw9j8_0Rcvji1oCq` |
| `0x1` | `eb8084e7…da8ad876` | `0:895b43038788001812b5a72df98a9604ae201bb5cf19f88eb2a8b7e50ff0dbfd` | `EQCJW0MDh4gAGBK1py35ipYEriAbtc8Z-I6yqLflD_Db_ZVb` | `UQCJW0MDh4gAGBK1py35ipYEriAbtc8Z-I6yqLflD_Db_cie` |
| `0xdeadbeefcafef00d` | `b0582989…b93641b8` | `0:a84377ad2d117cc863cc218ecebaf72414b6b63b1e3723eddcb9d07ccbaa9264` | `EQCoQ3etLRF8yGPMIY7OuvckFLa2Ox43I-3cudB8y6qSZAgI` | `UQCoQ3etLRF8yGPMIY7OuvckFLa2Ox43I-3cudB8y6qSZFXN` |

Full data hashes: `695754e51751794d32f9cd945cbff1a5df26817e6ba2409f2e9a270b3dbd5636`,
`eb8084e72a0496a802bbb23d2c9a6fa9a2226c30611f3bd5b7a8e434da8ad876`,
`b0582989a2e1d306827dcc5c2461c0281797c3b3f581608efb3e9588b93641b8`.

Become vector, same key: `to` = the salt-0 address above, `valid_until` =
1700000000, `code` = a cell of one byte `0x01`, `data` = a cell of one byte
`0x02`:

- Become cell hash: `ca067d2bfab737af4f207a6fa0ca895346d772c11ad44495204d894e8ca289f3`
- signature: `d891dad53d4f7633b98cf709d76f7bfef8106c518103e306f0af93b94291c1f83b26d9e869664f26002ed3c1213bc413532f66c3597addb1a3d734ae251a0003`
- external body hash: `22bb814fcd1256710ec17e6bd7df49d61bc00fbb44be5d713347fcd833c75111`

Every vector was computed three times, independently — Go with
tonkeeper/tongo, plain Python with hashlib, and the TypeScript sketch in §4
with `@ton/core` and `@ton/crypto` — and they agree. Any implementation you write must
reproduce them before it is used with real money.

## 4. Deployment

### Flow A — one transaction deploys and installs (recommended)

1. Send Toncoin to the **non-bounceable** (UQ…) form of the address. A
   bounceable transfer to an address with nothing deployed comes back.
2. Send one external message to the address carrying the placeholder's
   StateInit (the reference code BOC, the storage cell with key and salt) and
   the signed Become body. In the one transaction the account is created from
   the StateInit, the placeholder's code checks and accepts the request, and
   the account ends it with the real contract's code and data.

The funding is necessarily a separate transfer: an external message carries
no Toncoin, and the import and gas fees come from the balance already there.

### Flow B — deploy first, install later

1. Deploy the placeholder from a wallet: an internal message with the
   StateInit attached and an empty body. The placeholder keeps the Toncoin.
2. Later, send the external Become message without StateInit.

Anyone can deploy the placeholder at the address (its StateInit is public);
that is harmless — it only obeys the key.

### TypeScript sketch (`@ton/core`, `@ton/crypto`)

```ts
import { beginCell, Cell, contractAddress, external, storeMessage } from '@ton/core';
import { sign } from '@ton/crypto';

const placeholderCode = Cell.fromBase64('te6ccgEBCAEAfAABFP8A9KQT9LzyyAsBAgEgAgMCAUgEBQB68oMI1xjXTO1E0NcL/yH5AEAz+RDy4MnQ1ywjswtzzPK/+kjTH9TU0fgoFMcF8uDK+CNYufLgy/gA+wTtVAAM0DD4kfJAAgFIBgcAF7habtRNDT/zHXCz+AARuR+O1E0NcL/4');
if (placeholderCode.hash().toString('hex') !== 'b16b8b2cefaf342581684f59056ec1bd282e3428fb06327de53a4a737a60e497') throw new Error('wrong placeholder code');

const placeholderData = beginCell().storeBuffer(publicKey /* 32 bytes */).storeUint(salt /* bigint */, 64).endCell();
const init = { code: placeholderCode, data: placeholderData };
const address = contractAddress(0, init);             // must equal the address the search found

const become = beginCell()
  .storeUint(0x76616e79, 32)
  .storeAddress(address)
  .storeUint(Math.floor(Date.now() / 1000) + 30 * 60, 32)
  .storeRef(realCode)
  .storeRef(realInitialData)
  .endCell();
const body = beginCell().storeBuffer(sign(become.hash(), secretKey)).storeRef(become).endCell();

// Flow A: include init. Flow B, placeholder already deployed: omit it.
const msg = external({ to: address, init, body });
const boc = beginCell().store(storeMessage(msg)).endCell().toBoc();
// broadcast `boc` (toncenter sendBoc, a liteserver, …) — only after the rehearsal in §5
```

## 5. Safety checklist — do not skip

1. **Freeze the placeholder code.** Check its hash against the reference before
   the search, before funding, and before sending.
2. **Check the address two ways** — the searcher's arithmetic and your SDK's
   `contractAddress(0, init)` — and against the vectors in §3.
3. **Rehearse before sending.** Run the exact external message through an
   emulator or a sandbox (`@ton/sandbox`, a mainnet-fork tool, the TVM
   emulator) against the account as the chain holds it: funded and uninit for
   Flow A, the deployed placeholder for Flow B. Then, on the state it leaves,
   run the real contract's own withdrawal with the real contract's key and
   check it moves the balance out. Only then send. After this message nothing
   but the installed code can move the money.
4. **The installed code must refuse the Become message before accepting it.**
   The same signed message stays valid until `valid_until`, and after the
   install it reaches the new code. A contract whose external handler checks a
   signature over its own layout, or that has no external handler, refuses it
   and pays nothing. Check this in the rehearsal: replay the Become at the
   installed contract and expect a refusal before accept.
5. **Keep `valid_until` short** (tens of minutes).
6. **The data you install is the whole initial state.** No constructor runs.
7. **The key is the only way in.** The placeholder has no withdrawal of its
   own; while it is the placeholder, the only thing that can move its money is
   a Become signed by the key, and a lost key means lost funds. It can install
   any code, including a simple wallet, if the real contract turns out wrong
   before the install.
8. **Size limits** (mainnet config param 43): an external message is at most
   65,535 bytes as a BOC and 512 cells deep, and any message at most 8,192
   cells and 2,097,152 bits. The real contract's code and data travel inside
   the Become, so together with the StateInit they must fit in the external
   message. For larger code, keep the code in a library cell and install a
   library reference, or change the placeholder to take Become in an internal
   message (the internal limits are larger) — and then search again, since the
   code hash changes.
9. **Gas.** The checks before accepting run on the external message's gas
   credit (10,000 gas on basechain) and use a small fraction of it. The whole
   install of a ~3 KB contract cost 0.0025 TON on mainnet.
10. Treat the private key like a wallet's seed. Never print it, log it or put
    it in a message to anyone.

## 6. How this differs from ton-community/vanity-contract

`github.com/ton-community/vanity-contract` (FunC) does the same job with an
owner **wallet address** in the data and a 256-bit salt; the owner's wallet
sends an internal message with code and data. This placeholder uses an ed25519
**key** instead, which gives: one external message that deploys and installs
(after a plain funding transfer), a request bound to one address and to a
deadline, and a 42-byte data cell that a GPU searcher hashes in one SHA-256
block.
