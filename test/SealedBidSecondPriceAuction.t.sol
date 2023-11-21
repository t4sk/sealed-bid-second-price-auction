// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "./ERC20.sol";
import {ERC721} from "./ERC721.sol";
import {SealedBidSecondPriceAuction} from
    "../src/SealedBidSecondPriceAuction.sol";

contract SealedBidSecondPriceAuctionTest is Test {
    ERC20 private token;
    ERC721 private nft;
    SealedBidSecondPriceAuction private auction;
    uint256[2] private nftIds = [1, 2];
    address[2] private sellers = [address(1), address(2)];
    address[5] private bidders =
        [address(11), address(12), address(13), address(14), address(15)];

    function setUp() public {
        token = new ERC20();
        nft = new ERC721();
        auction = new SealedBidSecondPriceAuction(address(token), address(nft));

        for (uint256 i = 0; i < sellers.length; i++) {
            nft.mint(sellers[i], nftIds[i]);
            vm.prank(sellers[i]);
            nft.approve(address(auction), nftIds[i]);
        }

        for (uint256 i = 0; i < bidders.length; i++) {
            token.mint(bidders[i], 1000);
            vm.prank(bidders[i]);
            token.approve(address(auction), type(uint256).max);
        }
    }

    function test_start() public {
        vm.prank(sellers[0]);
        uint256 id = auction.start(nftIds[0], 99);

        assertEq(auction.count(), 1);
        SealedBidSecondPriceAuction.Auction memory auc = auction.get(id);
        assertEq(auc.nftId, nftIds[0]);
        assertEq(auc.creator, sellers[0]);
        assertEq(auc.minBid, 99);
        assertEq(auc.bids[0], 0);
        assertEq(auc.bids[1], 0);
        assertLt(block.timestamp, auc.deadlines[0]);
        assertLt(auc.deadlines[0], auc.deadlines[1]);
        assertEq(nft.ownerOf(nftIds[0]), address(auction));
    }

    function test_stop_revert_if_auction_does_not_exist() public {
        vm.expectRevert("not authorized");
        auction.stop(1);
    }

    function test_stop_revert_if_not_creator() public {
        vm.prank(sellers[0]);
        uint256 id = auction.start(nftIds[0], 99);

        vm.expectRevert("not authorized");
        auction.stop(id);
    }

    function test_stop() public {
        vm.prank(sellers[0]);
        uint256 id = auction.start(nftIds[0], 99);

        vm.prank(sellers[0]);
        auction.stop(id);

        SealedBidSecondPriceAuction.Auction memory auc = auction.get(id);
        assertEq(auc.nftId, 0);
        assertEq(auc.creator, address(0));
        assertEq(auc.minBid, 0);
        assertEq(auc.bids[0], 0);
        assertEq(auc.bids[1], 0);
        assertEq(auc.deadlines[0], 0);
        assertEq(auc.deadlines[1], 0);
        assertEq(nft.ownerOf(nftIds[0]), sellers[0]);
    }

    // TODO: stop revert if bid placed

    function test_commit_revert_if_auction_does_not_exist() public {
        vm.expectRevert("auction does not exist");
        vm.prank(bidders[0]);
        auction.commit(0, bytes32(uint256(1)));
    }

    function test_commit_revert_deadline() public {
        vm.prank(sellers[0]);
        uint256 id = auction.start(nftIds[0], 99);

        SealedBidSecondPriceAuction.Auction memory auc = auction.get(id);
        vm.warp(auc.deadlines[0]);

        vm.expectRevert("commit deadline expired");
        vm.prank(bidders[0]);
        auction.commit(id, bytes32(uint256(1)));
    }

    function test_commit() public {
        vm.prank(sellers[0]);
        uint256 id = auction.start(nftIds[0], 99);

        vm.prank(bidders[0]);
        auction.commit(id, bytes32(uint256(1)));

        assertEq(auction.commits(id, bidders[0]), bytes32(uint256(1)));
    }

    function test_reveal_revert_if_auction_does_not_exist() public {
        vm.expectRevert("auction does not exist");
        vm.prank(bidders[0]);
        auction.reveal(0, bidders[0], 0, 0);
    }

    function test_reveal_revert_if_commit_deadline_not_expired() public {
        vm.prank(sellers[0]);
        uint256 id = auction.start(nftIds[0], 99);

        uint256 amount = 100;
        uint256 salt = 1;
        bytes32 c = auction.getCommitHash(id, bidders[0], amount, salt);

        vm.prank(bidders[0]);
        auction.commit(id, c);

        vm.expectRevert("commit deadline not expired");
        vm.prank(bidders[0]);
        auction.reveal(id, bidders[0], amount, salt);
    }

    function test_reveal_revert_if_reveal_deadline_expired() public {
        vm.prank(sellers[0]);
        uint256 id = auction.start(nftIds[0], 99);

        uint256 amount = 100;
        uint256 salt = 1;
        bytes32 c = auction.getCommitHash(id, bidders[0], amount, salt);

        vm.prank(bidders[0]);
        auction.commit(id, c);

        SealedBidSecondPriceAuction.Auction memory auc = auction.get(id);
        vm.warp(auc.deadlines[1]);

        vm.expectRevert("reveal deadline expired");
        vm.prank(bidders[0]);
        auction.reveal(id, bidders[0], amount, salt);
    }
    // TODO: function test_reveal_revert_if_bidder = address(0)
    // TODO: function test_reveal_revert_if_amount < min
    // TODO: function test_reveal_revert_if_commit hash mismatch
    // TODO: function test_reveal_revert_if_no commit
    // TODO: function test_reveal_first bidder
    // TODO: function test_reveal_second bidder > first
    // TODO: function test_reveal_second bidder <= first
    // TODO: function test_reveal_third bidder > second
    // TODO: function test_reveal_third bidder <= second
}

// TODO: invariant tests
