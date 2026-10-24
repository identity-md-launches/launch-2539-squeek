# Squeek (SQK)

Squeek is an immutable, fixed-supply ERC-20. Its constructor mints the entire
supply to the immediate deploying address (`msg.sender`) exactly once.

| Parameter | Value |
| --- | --- |
| Contract | `src/Squeek.sol:Squeek` |
| Token name | `Squeek` |
| Symbol | `SQK` |
| Decimals | `18` |
| Supply in SQK | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deployer; the factory when factory-deployed |
| Target launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

## Behavior and assumptions

The brief requests a standard token, so SQK has no transfer tax, burn mechanism,
rebasing, transfer limits, allowlist, blacklist, pause, owner, minter role,
initialization step, upgrade path, or application contracts. `INITIAL_SUPPLY` is
the named constant for the requested supply. The constructor calls no external
contracts and requires no configuration or existing on-chain infrastructure.

ERC-20 behavior comes from the vendored OpenZeppelin implementation:

- Transfers move the exact requested quantity and return `true`. Invalid calls
  revert with ERC-6093 custom errors; balances and allowances roll back together.
- Zero-value transfers between nonzero addresses succeed and emit `Transfer`.
  Self-transfers leave the balance unchanged. Transfers to the zero address revert.
- `approve` replaces the caller's allowance for a nonzero spender and emits
  `Approval`. Setting it to zero revokes future spending authority.
- `transferFrom` requires the caller's allowance, including when the caller is
  the source. Finite allowances decrease by the amount spent. Maximum `uint256`
  approvals remain unchanged. Successful transfers emit `Transfer`; allowance
  consumption does not emit an additional `Approval` in this implementation.
- The constructor emits `Transfer(address(0), deployer, INITIAL_SUPPLY)`.
  There are no callable mint or burn functions, so total supply stays constant.
- Transfers perform no receiver callbacks. Sending SQK to a contract does not
  prove that the recipient can return or use it.

## Build and test

Foundry and Solidity 0.8.26 must be available. All Solidity dependencies, including
the test framework, are ordinary files in `lib/`; no package download, submodule,
RPC endpoint, wallet, or environment file is needed. The configuration enables
neither FFI nor filesystem permissions.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x824aac7b6b188102dba38bc055be093d7ddb7c89d771d0ed5f0c311894405b8a forge test
forge fmt --check
```

The suite has 35 unit/fuzz tests, including six fuzz properties run 1,024 times
each, plus two stateful invariant properties checked across 128 sequences of 64
operations. Coverage includes direct and CREATE/CREATE2 factory deployment,
metadata, issuance events, exact transfer amounts, zero/self/full-balance
transfers, allowances, revocation, unauthorized spending, failed-call rollback,
unavailable administrative entry points, and token-level launch distributions.
The invariant handler mixes successful and rejected transfers and approvals,
comparing balances and allowances with an independent accounting model and
checking supply conservation after every step. Tests read no environment
variables and share no external state.

The launch-flow test checks the token movements for distribution, claims, and
pool-facing transfers. It does not instantiate Uniswap or execute a real swap;
the network's supplied protected harness performs that integration separately.
Local test results are not an independent security audit. Slither and Mythril
were not run in this assignment.

## Deployment and operations

Deploy the creation bytecode for `Squeek` with no appended constructor arguments
and no ETH. The creation transaction's immediate caller receives every token.
When a factory creates it, the factory receives the supply; the wallet initiating
the factory call does not. There is no owner address to supply or transfer.

For the specified IdentityMD launch, the factory handles distribution after
deployment: 10% to the swarm distributor, 80% for pool seeding, and the remaining
10% to the launch's configured remainder recipient. These are launch-system
responsibilities, not constructor transfers. The token makes no allocations,
holds no reserve, and imposes no restrictions on these subsequent transfers.
The launch system supplies its manifest separately; this repository contains no
manifest or transaction-broadcasting script.

The deployer is responsible for using the reviewed artifact and pinned compiler
settings, checking the resulting name/symbol/decimals/supply and recipient,
executing the launch distribution, and verifying the deployed source. Review the
token and the complete launch integration independently before production use.

### After launch

No setters, initialization calls, privileged maintenance, keepers, or external
services are needed. No administrator can recover tokens, reverse transfers,
freeze accounts, or upgrade this contract. Holders control their balances and
approvals; recipient and spender selection is their responsibility. Prefer
bounded approvals. When changing an existing allowance, revoke it and confirm
that transaction before granting the replacement to reduce the usual ERC-20
allowance-change race; revocation cannot undo spending already executed.

## Dependencies

Pinned sources and licenses are listed in [DEPENDENCIES.md](DEPENDENCIES.md).
Use `sha256sum --check lib/SHA256SUMS` to check the vendored files.
