// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ValidatorMetadata} from "src/ValidatorMetadata.sol";

contract ValidatorMetadataScript is Script {
    /// @notice CREATE2 salt for deterministic deployment.
    /// @dev Bumping the version suffix is the supported way to land at a fresh address
    ///      (e.g. for a bytecode change that would otherwise share the same address).
    bytes32 internal constant SALT = keccak256("MRC-13:ValidatorMetadata:v1");

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // Inside a broadcast, `new X{salt: ...}()` is routed by Foundry through the
        // standard deterministic-deployer factory at
        // 0x4e59b44847b379578588920cA78FbF26c0B4956C, so the resulting address is
        // a function of (factory, salt, bytecode hash) only — identical on every
        // chain where the factory is present.
        address deployed = address(new ValidatorMetadata{salt: SALT}());
        vm.stopBroadcast();
        console.log("ValidatorMetadata deployed to:", deployed);
        console.log("Salt:");
        console.logBytes32(SALT);
    }
}
