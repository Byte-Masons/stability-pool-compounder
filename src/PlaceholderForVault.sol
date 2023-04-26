// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import "vault-v2/ReaperVaultERC4626.sol";

// This contract solely exists to ensure hardhat compiles the vault contracts.
// Otherwise hardhat will not be able to find the vault artifact when deploying.
// Forge works fine without this because forge tests will force vault compilation.
// However, since we don't have any js tests, hardhat needs this extra nudge.

contract PlaceholderForVault {}
