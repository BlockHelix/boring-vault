// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "@forge-std/Test.sol";
import {BlockHelixMasterDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/BlockHelixMasterDecoderAndSanitizer.sol";
import {DeadlineDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/Protocols/DeadlineDecoderAndSanitizer.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";

contract NgPoolMock {
    uint256 public calls;

    function exchange(int128, int128, uint256, uint256, address) external returns (uint256) {
        calls++;
        return 0;
    }

    function exchange_received(int128, int128, uint256, uint256, address) external returns (uint256) {
        calls++;
        return 0;
    }
}

contract RouterMock {
    uint256 public calls;

    function multicall(uint256 deadline, bytes[] calldata) external returns (bytes[] memory r) {
        require(block.timestamp <= deadline, "Transaction too old");
        calls++;
        return r;
    }
}

contract DeadlineCurveNgDecoderAndSanitizerTest is Test {
    BlockHelixMasterDecoderAndSanitizer decoder;
    BoringVault vault;
    ManagerWithMerkleVerification manager;
    NgPoolMock pool;
    NgPoolMock nextPool;
    RouterMock router;
    address constant ATTACKER = address(0xBAD);
    address constant STRATEGIST = address(0x5747);
    uint8 constant MANAGER_ROLE = 1;
    uint8 constant STRATEGIST_ROLE = 2;

    function setUp() public {
        decoder = new BlockHelixMasterDecoderAndSanitizer();
        vault = new BoringVault(address(this), "V", "V", 6);
        manager = new ManagerWithMerkleVerification(address(this), address(vault), address(0xBA1));
        pool = new NgPoolMock();
        nextPool = new NgPoolMock();
        router = new RouterMock();
        RolesAuthority auth = new RolesAuthority(address(this), Authority(address(0)));
        vault.setAuthority(auth);
        manager.setAuthority(auth);
        auth.setRoleCapability(MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address,bytes,uint256)")), true);
        auth.setRoleCapability(MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address[],bytes[],uint256[])")), true);
        auth.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        auth.setUserRole(address(manager), MANAGER_ROLE, true);
        auth.setUserRole(STRATEGIST, STRATEGIST_ROLE, true);
    }

    // ---- sanitizer outputs ----

    function test_selectorsMatchTheCurveNgAndRouter02Abis() public {
        assertEq(bytes4(keccak256("exchange(int128,int128,uint256,uint256,address)")), bytes4(0xddc1f59d));
        assertEq(bytes4(keccak256("exchange_received(int128,int128,uint256,uint256,address)")), bytes4(0xafb43012));
        assertEq(bytes4(keccak256("multicall(uint256,bytes[])")), bytes4(0x5ae401dc));
    }

    function test_ngExchangeReturnsTheReceiver() public {
        assertEq(decoder.exchange(0, 1, 1, 0, address(nextPool)), abi.encodePacked(address(nextPool)));
    }

    function test_ngExchangeReceivedReturnsTheReceiver() public {
        assertEq(decoder.exchange_received(0, 1, 1, 0, address(vault)), abi.encodePacked(address(vault)));
    }

    function test_deadlineMulticallWithEmptyDataReturnsNothing() public {
        assertEq(decoder.multicall(block.timestamp, new bytes[](0)), "");
    }

    function test_deadlineMulticallRefusesAnyData() public {
        bytes[] memory data = new bytes[](1);
        data[0] = hex"04e45aaf";
        vm.expectRevert(DeadlineDecoderAndSanitizer.DeadlineDecoderAndSanitizer__DataNotEmpty.selector);
        decoder.multicall(block.timestamp, data);
    }

    /// The v8 4-arg exchange must be unaffected by the overload.
    function test_fourArgExchangeStillDecodes() public {
        assertEq(decoder.exchange(0, 1, 1, 0), "");
    }

    // ---- through the real manager: what a leaf can and cannot authorise ----

    function _leaf(address target, bytes4 selector, bytes memory packed) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(decoder), target, false, selector, packed));
    }

    function _manage(address target, bytes memory data) internal {
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);
        address[] memory decoders = new address[](1);
        decoders[0] = address(decoder);
        address[] memory targets = new address[](1);
        targets[0] = target;
        bytes[] memory datas = new bytes[](1);
        datas[0] = data;
        uint256[] memory values = new uint256[](1);
        vm.prank(STRATEGIST);
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, datas, values);
    }

    function test_receiverPinnedToTheNextPoolCannotBeRedirectedOutside() public {
        manager.setManageRoot(STRATEGIST, _leaf(address(pool), 0xddc1f59d, abi.encodePacked(address(nextPool))));
        _manage(address(pool), abi.encodeWithSelector(0xddc1f59d, int128(0), int128(1), 1, 0, address(nextPool)));
        assertEq(pool.calls(), 1);

        bytes memory stolen = abi.encodeWithSelector(0xddc1f59d, int128(0), int128(1), 1, 0, ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerWithMerkleVerification.ManagerWithMerkleVerification__FailedToVerifyManageProof.selector,
                address(pool), stolen, 0
            )
        );
        _manage(address(pool), stolen);
    }

    function test_exchangeReceivedReceiverPinnedToTheVaultCannotBeRedirected() public {
        manager.setManageRoot(STRATEGIST, _leaf(address(nextPool), 0xafb43012, abi.encodePacked(address(vault))));
        _manage(address(nextPool), abi.encodeWithSelector(0xafb43012, int128(1), int128(0), 1, 0, address(vault)));
        assertEq(nextPool.calls(), 1);

        bytes memory stolen = abi.encodeWithSelector(0xafb43012, int128(1), int128(0), 1, 0, ATTACKER);
        vm.expectRevert();
        _manage(address(nextPool), stolen);
    }

    function test_deadlineLeafCannotCarryARouterCall() public {
        manager.setManageRoot(STRATEGIST, _leaf(address(router), 0x5ae401dc, ""));
        _manage(address(router), abi.encodeWithSelector(0x5ae401dc, block.timestamp, new bytes[](0)));
        assertEq(router.calls(), 1);

        bytes[] memory swap = new bytes[](1);
        swap[0] = hex"04e45aaf";
        vm.expectRevert(DeadlineDecoderAndSanitizer.DeadlineDecoderAndSanitizer__DataNotEmpty.selector);
        _manage(address(router), abi.encodeWithSelector(0x5ae401dc, block.timestamp, swap));
    }

    function test_deadlineLegRevertsTheBundleOncePast() public {
        manager.setManageRoot(STRATEGIST, _leaf(address(router), 0x5ae401dc, ""));
        uint256 deadline = block.timestamp + 24;
        vm.warp(deadline + 1);
        vm.expectRevert(bytes("Transaction too old"));
        _manage(address(router), abi.encodeWithSelector(0x5ae401dc, deadline, new bytes[](0)));
    }
}
