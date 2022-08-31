pragma solidity ^0.8.0;

// import "./utils/SafeMath.sol";
import {ERC721URIStorage, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMetaKeyMintable} from "./IMetaKeyMintable.sol";

contract IBOME is ERC721URIStorage, ReentrancyGuard, Ownable, IMetaKeyMintable {
    using SafeMath for uint256;
    using Counters for Counters.Counter; //counter for the mint
    using EnumerableSet for EnumerableSet.AddressSet;

    Counters.Counter private tokenCounter;
    EnumerableSet.AddressSet WHITELIST;

    address rentFeeTaker;
    uint public rentFee = 10; // set the rent fee to 10 %, 
    uint public feeDivident = 100; // set the divident to 100

    event TokenRented(uint tokenId, address renter, uint rentStartTime, uint rentEndTime);
    event RentBidSet(uint tokenId, address bidAddress, uint bidPrice, uint bidDuration, uint rentIndex);
    event RentEnded(uint tokenId);
    event RentBidCancelled(uint tokenId, uint rentIndex);
    event RentAskSet(uint tokenId, uint askPrice, uint askDuration);


    struct RentBid {
        address bidAddress; // address who sent the bid
        uint bidPrice; // bid price
        uint bidDuration; // bid duration
        uint bidTime; // bid timestamp
    }

    struct RentAsk {
        bool isRentable;
        uint askPrice;
        uint askDuration;
    }

    struct RentStatus {
        bool rented; 
        address renter;
        uint endTime;
    }

    mapping(uint => RentStatus) private rentStatus;
    mapping(uint => RentBid[]) private rentBids;
    mapping(uint => RentAsk) private rentAsk;

    // the rentFeeTaker takes _rentFee / _feeDivident * rentPrice 
    constructor(address _rentFeeTaker, uint _rentFee, uint _feeDivident) ERC721("IBOME", "IBOME"){  // set the NFT name to "IBOME"
        rentFeeTaker = _rentFeeTaker;
        require(_feeDivident != 0, "Fee divident is zero");
        require(_rentFee < _feeDivident, "rent Fee is not smaller than rent divident");
        rentFee = _rentFee;  // dynamically set rent Fee, _feeDivident.
        feeDivident = _feeDivident;
    }

    /**
     * @notice Require that the token has not been burned and has been minted
     */
     modifier onlyExistingToken(uint256 tokenId) {
        require(_exists(tokenId), "nonexistent token");
        _;
    }


    //might disable this part because we use ticket nft for minting.

    function mintNFT(string memory _tokenURI) public {
        //here only whitelisted users can mint
        require(WHITELIST.contains(msg.sender), "Address is not in the whitelist.");
        
        uint256 currentTokenId = tokenCounter.current();
        _mint(msg.sender, currentTokenId);
        _setTokenURI(currentTokenId, _tokenURI); // set the token URI
        tokenCounter.increment();
    }


    //override _transfer function for the rent
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        // if token is on rent, can not transfer
        require(rentStatus[tokenId].rented == false, "the token is on rent");

        //transfer token
        super._transfer(from, to, tokenId);
        //cancel all Rent bids
        _cancelAllRentBids(tokenId);
        
    }

    //override the ownerOf function for the rent
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        // address owner = _owners[tokenId];
        // require(owner != address(0), "ERC721: owner query for nonexistent token");
        // return owner;
        address owner = super.ownerOf(tokenId);
        if (rentStatus[tokenId].rented) {
            return rentStatus[tokenId].renter;
        }
        return owner;
    }

    // Set the rent Bid
    // if the rent Bid is set we should depoist the msg.value to the contract, and send to the token owner if the rent is accepted
    function setRentBid(uint _tokenId, uint _duration) onlyExistingToken(_tokenId) public payable { 
        require(rentStatus[_tokenId].rented == false, "the token is on rent"); // if the token is on the rent, can't set RentAsk
        require(rentAsk[_tokenId].isRentable, "This token can not be rent"); // if the token's rent ask is false, can't set RentAsk
        RentBid memory rentBid = RentBid({
            bidAddress : msg.sender, 
            bidPrice : msg.value, 
            bidDuration : _duration, 
            bidTime : block.timestamp
        });

        uint currentBidIndex = rentBids[_tokenId].length;
        
        emit RentBidSet(_tokenId, msg.sender, msg.value, _duration, currentBidIndex);
        rentBids[_tokenId].push(rentBid);

        // if the rent bid is acceptable, accept it (msg.value >= askPrice, _duration <= askDuration)
        if ((msg.value >= rentAsk[_tokenId].askPrice) && (_duration <= rentAsk[_tokenId].askDuration)) {
            acceptRentBid(_tokenId, currentBidIndex);
        }

    }

    //set the rentAsk
    function setRentAsk(uint _tokenId, bool _isRentable, uint _askPrice, uint _askDuration) onlyExistingToken(_tokenId) external {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "sender must be owner or approved");
        require(rentStatus[_tokenId].rented == false, "the token is on rent");
        require(_askPrice > 0, "ask price is zeor");
        require(_askDuration > 0, "ask duration is zeor");
        //set the rent ask
        rentAsk[_tokenId] = RentAsk({
            isRentable : _isRentable,
            askPrice : _askPrice, 
            askDuration : _askDuration
        });

        emit RentAskSet(_tokenId, _askPrice, _askDuration);

        // if _isRentable is false, cancel all rent bid
        if (_isRentable == false) _cancelAllRentBids(_tokenId);
    }

    
    //get all rent bid for the token
    function getRentBid(uint _tokenId) public view onlyExistingToken(_tokenId) returns(RentBid[] memory) {
        return rentBids[_tokenId];
    }


    // accept Rent
    // _tokenId : NFT id for rent
    // _index : rentAsk index
    function acceptRentBid(uint _tokenId, uint _index) public onlyExistingToken(_tokenId) nonReentrant{
        //can be called by owner or approved or contract itself
        require(_isApprovedOrOwner(msg.sender, _tokenId) || (msg.sender == address(this)), "Only owner or approved one can accept the rent ask");
        require(_index < rentBids[_tokenId].length, "index doese not exist in rent ask");
        require(rentStatus[_tokenId].rented == false, "Current token is on rent");
        require(rentBids[_tokenId][_index].bidAddress != address(0), "Bid Address does not exist.");
        
        //send the rent fee to the feeTaker
        RentBid memory acceptedBid = rentBids[_tokenId][_index];
        payable(rentFeeTaker).transfer(acceptedBid.bidPrice * rentFee / feeDivident);

        //send the remaing value to the owner
        payable(ownerOf(_tokenId)).transfer(acceptedBid.bidPrice * (feeDivident - rentFee) / feeDivident);

        //set the rent status
        rentStatus[_tokenId] = RentStatus({
            rented : true, 
            renter : acceptedBid.bidAddress, 
            endTime : block.timestamp + acceptedBid.bidDuration
        });

        //set the rentprice = 0, for _cancelAllBid
        rentBids[_tokenId][_index].bidPrice = 0;
        _cancelAllRentBids(_tokenId);

        emit TokenRented(_tokenId, acceptedBid.bidAddress, block.timestamp, block.timestamp + acceptedBid.bidDuration);
    }

    //cancel the rent bid, it can only be called by the rent bid setter
    function cancelRentBid(uint _tokenId, uint _index) public onlyExistingToken(_tokenId) nonReentrant{
        require(_index < rentBids[_tokenId].length, "index doese not exist in rent ask");
        RentBid memory currentBid = rentBids[_tokenId][_index];
        require(currentBid.bidAddress == msg.sender, "msg.sender is not equal to bidAddress");
        
        payable(currentBid.bidAddress).transfer(currentBid.bidPrice);
        //set the data to null in the _index
        rentBids[_tokenId][_index] = RentBid({
            bidAddress : address(0), 
            bidPrice : 0, 
            bidDuration : 0, 
            bidTime : block.timestamp
        });

        //emit the event
        emit RentBidCancelled(_tokenId, _index);
    }

    // end rent
    // it can be called by anyone, if the endTime < block.timestamp
    function endRent(uint _tokenId) public onlyExistingToken(_tokenId) {
        require(rentStatus[_tokenId].endTime < block.timestamp, "Rent is still on");
        delete rentStatus[_tokenId];
        emit RentEnded(_tokenId);
    }

    // get Rent status
    function getRentStatus(uint _tokenId) public onlyExistingToken(_tokenId) view returns(RentStatus memory) {
        return rentStatus[_tokenId];
    }


    //cancel all rent bids.
    // revert all bidPrice
    function _cancelAllRentBids(uint _tokenId) internal onlyExistingToken(_tokenId) {
        RentBid[] memory currentRentBid = rentBids[_tokenId];

        for (uint i = 0; i < currentRentBid.length; i++) {
            payable(currentRentBid[i].bidAddress).transfer(currentRentBid[i].bidPrice); // revert all bidPrice
        }
        delete rentBids[_tokenId];
    }

    // whitelist getters
    function getWhitelistedUsersLength() external view returns (uint256) {
        return WHITELIST.length();
    }

    function getWhitelistedUserAtIndex(uint256 _index)
        external
        view
        returns (address)
    {
            return WHITELIST.at(_index);
            
    }

    function getUserWhitelistStatus(address _user)
        external
        view
        returns (bool)
    {
        return WHITELIST.contains(_user);
    }

    function editWhitelist(address[] memory _users, bool _add)
        external
        onlyOwner
        
    {
        if (_add) {
            for (uint256 i = 0; i < _users.length; i++) {
                WHITELIST.add(_users[i]);
            }
        } else {
            for (uint256 i = 0; i < _users.length; i++) {
                WHITELIST.remove(_users[i]);
            }
        }
    }

    function mintFromMetaKey(uint _ticketId, address _nftOwner) external override {
        //just mint the _ticket ID for the _nftOwner
        // require(!_exists(_ticketId), "token already exists");
        _mint(_nftOwner, _ticketId);
    }
    
}


