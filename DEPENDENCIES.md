# Vendored dependencies

All dependencies below are included as ordinary source files, with no submodules
or package-manager installation step. Vendored contents are unmodified upstream
files. `lib/SHA256SUMS` records their SHA-256 checksums.

| Dependency | Release | Commit | Included files | License |
| --- | --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3) | v5.0.2 | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | ERC20 and its four transitive Solidity dependencies | [MIT](lib/openzeppelin-contracts/LICENSE) |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7 | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Upstream `src/` Solidity files, used only by tests | [MIT](lib/forge-std/LICENSE-MIT) or [Apache-2.0](lib/forge-std/LICENSE-APACHE) |

Remappings are local to this repository. The deployable token imports only the
OpenZeppelin dependency. There are no externally linked libraries.
