// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";

contract SealedBidSecondPriceAuction {
    event Start(
        uint256 indexed id,
        address indexed creator,
        uint256 nftId,
        uint256 minBid
    );
    event Stop(uint256 indexed id);
    event Commit(uint256 indexed id, address indexed bidder, bytes32 hash);
    event Reveal(
        uint256 indexed id,
        address indexed payer,
        address indexed bidder,
        uint256 amount,
        uint256 salt
    );
    event Claim(uint256 indexed id);

    struct Auction {
        uint256 nftId;
        address creator;
        uint256 minBid;
        uint256[2] bids;
        address[2] bidders;
        // commit and reveal deadlines
        uint32[2] deadlines;
    }

    IERC20 public immutable token;
    IERC721 public immutable nft;
    bool private locked;
    uint256 public count;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => bytes32)) public commits;

    modifier lock() {
        require(!locked, "locked");
        locked = true;
        _;
        locked = false;
    }

    constructor(address _token, address _nft) {
        token = IERC20(_token);
        nft = IERC721(_nft);
    }

    function get(uint256 id) external view returns (Auction memory) {
        return auctions[id];
    }

    function start(uint256 nftId, uint256 minBid)
        external
        lock
        returns (uint256)
    {
        uint256 id = ++count;
        // TODO: data exists after delete?
        auctions[id] = Auction({
            nftId: nftId,
            creator: msg.sender,
            bids: [uint256(0), uint256(0)],
            minBid: minBid,
            bidders: [address(0), address(0)],
            deadlines: [
                // commit expiration
                uint32(block.timestamp + 3 days),
                // reveal expiration
                uint32(block.timestamp + 5 days)
            ]
        });
        nft.transferFrom(msg.sender, address(this), nftId);
        emit Start(id, msg.sender, nftId, minBid);
        return id;
    }

    function stop(uint256 id) external lock {
        Auction memory auc = auctions[id];
        require(msg.sender == auc.creator, "not authorized");
        require(auc.bidders[0] == address(0), "bid placed");

        delete auctions[id];

        nft.transferFrom(address(this), msg.sender, auc.nftId);
        emit Stop(id);
    }

    function getCommitHash(
        uint256 auctionId,
        address bidder,
        uint256 amount,
        uint256 salt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(address(this), auctionId, bidder, amount, salt)
        );
    }

    function commit(uint256 id, bytes32 hash) external lock {
        Auction memory auc = auctions[id];
        require(auc.creator != address(0), "auction does not exist");
        require(block.timestamp < auc.deadlines[0], "commit deadline expired");
        commits[id][msg.sender] = hash;
        emit Commit(id, msg.sender, hash);
    }

    // TODO: not second price if first bidder is highest
    // TODO: is this same as english auction?
    // TODO: can be front runned?
    function reveal(uint256 id, address bidder, uint256 amount, uint256 salt)
        external
        lock
    {
        require(bidder != address(0), "bidder = 0 address");
        Auction storage auc = auctions[id];
        require(auc.creator != address(0), "auction does not exist");
        require(amount >= auc.minBid, "bid < min");
        require(
            auc.deadlines[0] < block.timestamp, "commit deadline not expired"
        );
        require(block.timestamp < auc.deadlines[1], "reveal deadline expired");
        bytes32 c = commits[id][bidder];
        require(c != bytes32(0), "commit = 0 bytes32");
        require(
            c == getCommitHash(id, bidder, amount, salt),
            "incorrect commit hash"
        );

        delete commits[id][bidder];

        if (amount > auc.bids[0]) {
            auc.bidders[1] = auc.bidders[0];
            auc.bids[1] = auc.bids[0];
            auc.bidders[0] = bidder;
            auc.bids[0] = amount;

            // TODO: what happens if msg.sender == bidders?
            if (auc.bidders[1] != address(0)) {
                token.transfer(auc.bidders[1], auc.bids[1]);
            }
            token.transferFrom(msg.sender, address(this), amount);
        }

        emit Reveal(id, msg.sender, bidder, amount, salt);
    }

    function claim(uint256 id) external lock {
        Auction memory auc = auctions[id];
        require(auc.bidders[0] != address(0), "no bids placed");
        require(
            msg.sender == auc.creator || msg.sender == auc.bidders[0],
            "not authorized"
        );
        require(
            auc.deadlines[1] < block.timestamp, "reveal deadline not expired"
        );

        delete auctions[id];

        if (auc.bids[1] > 0) {
            token.transfer(auc.creator, auc.bids[1]);
            token.transfer(auc.bidders[0], auc.bids[0] - auc.bids[1]);
        } else {
            token.transfer(auc.creator, auc.bids[0]);
        }
        nft.transferFrom(address(this), auc.bidders[0], auc.nftId);
        emit Claim(id);
    }
}
