pragma solidity ^0.8.0;

// import "./utils/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMetaKeyMintable} from "./../IMetaKeyMintable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import {IMasterKeyMintable} from "./../IMasterKeyMintable.sol";

//for ERC777
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/interfaces/IERC1820Registry.sol";

//Meta Key NFT for the real NFTs, 
//Here MetaKeyNFT has no URI for the token

contract MasterKey is ERC721, ReentrancyGuard, Ownable,  IERC777Recipient {

    //events
    event MasterKeyNFTMinted(address _owner, uint _tokenId,  uint _mintTime);
    event MasterKeyActivated(address _owner, uint _tokenId);
    event WhiteListChanged(address[] _users, bool _add);
    event RandomSeedGenerated(uint _randomValue);


    // the rentFeeTaker takes _rentFee / _feeDivident * rentPrice
    using EnumerableSet for EnumerableSet.AddressSet;
    // using Counters for Counters.Counter; //counter for the mint


    // MetaKeyNFT contract addresses
    address[] private nftContracts;
    mapping(string => address) private nftNameMap;

    EnumerableSet.AddressSet WHITELIST;  // whitelist
    mapping(address => bool) whitelistedMemberMintStatus;
    // Counters.Counter private tokenCounter;
    address public masterKeyContract;

    // uint constant public MAX_ID = 10000; // here set the max id to 10000 , we can fix it later

    // uint private currentAvailableId = MAX_ID + 1;

    uint public activateTime = 999999999999; // time stamp when activation is available, first set invalid time
    uint public tokenPrice = 0;  // now we accept native tokens in the chain, first set invalid value

    
    // current Mintable Id for master key nft( just increment )
    uint public currentMintableId = 0;
    mapping(uint => mapping(address => uint)) metaKeyNFTIds;

    //erc20 tokens list
    mapping(address => uint) tokenPriceInERC20;
    address[] erc20Tokens;


    //erc 777
     //keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
    0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;


    
    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    //now not sure to set the related Contract in the constructer, after can be change
    uint private randNonce = 0;

    constructor() 
        ERC721("MetagateMasterKey", "GateMasterKey")
    {  
        
    }

    // Set IMetaKeyMintable address and name for MetaKeyContract
    function addNFTAddress(string memory _nftName, address _nftAddress) public {
        require(nftNameMap[_nftName] == address(0), "Name has used before");
        nftNameMap[_nftName] = _nftAddress;
        nftContracts.push(_nftAddress);
    }

    //set activation time of meta key contract 
    function setActivationTime(uint _activateTime) onlyOwner public {
        activateTime = _activateTime;
    }

    function setTokenPriceInEth(uint _tokenPrice) onlyOwner public {
        require(tokenPrice == 0, "Token price has been already set.");
        require(_tokenPrice != 0, "Token price must be bigger than zero.");
        tokenPrice = _tokenPrice;
    }

    function setTokenPriceInERC20(address _erc20Address, uint _tokenPrice) onlyOwner public {
        require(tokenPriceInERC20[_erc20Address] == 0, "Token price has been already set.");
        require(_tokenPrice != 0, "Token price must be bigger than zero.");
        tokenPriceInERC20[_erc20Address] = _tokenPrice;
        erc20Tokens.push(_erc20Address);
    }

    function getTokenPriceInERC20(address _erc20Address) public view returns (uint) {
        return tokenPriceInERC20[_erc20Address];
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
        emit WhiteListChanged(_users, _add);
    }



    function _mintMasterKey(address _owner) internal{
        whitelistedMemberMintStatus[_owner] = true;

        //set metak key id for the master key
        for (uint i = 0; i < nftContracts.length; i ++) {

            IMasterKeyMintable metaKeyContract = IMasterKeyMintable(nftContracts[i]);
            //for now I just send the ownership
            uint tokenId = metaKeyContract.mintFromMasterKey();
            metaKeyContract.transferFrom(address(this), _owner, tokenId);
        }

        whitelistedMemberMintStatus[_owner] = true;
        _mint(_owner, currentMintableId);
        emit MasterKeyNFTMinted(_owner, currentMintableId, block.timestamp);
        currentMintableId ++;
    }

    // mintMasterKeyNFT for customer, here admin mints it and send it to the owner

    function mintMasterKeyNFTInEth() public payable {
        //here only whitelisted users can mint
        require(WHITELIST.contains(msg.sender), "Address is not in the whitelist.");
        require(msg.value >= tokenPrice, "Value is smaller than the price");
        require(whitelistedMemberMintStatus[msg.sender] == false, "Minted already");

        // uint tokenId = getTokenId();
        // whitelistedMemberMintStatus[msg.sender] = true;
        // _mint(msg.sender, tokenId); // mint the token to msg.sender
        
        // emit MasterKeyNFTMinted(msg.sender, tokenId, block.timestamp);
        _mintMasterKey(msg.sender);
    }

    function mintMasterKeyNFTInERC20(address _erc20Address) public {
        require(WHITELIST.contains(msg.sender), "Address is not in the whitelist.");
        require(tokenPriceInERC20[_erc20Address] > 0, "Token is not supported in this contract!");
        require(whitelistedMemberMintStatus[msg.sender] == false, "Minted already");

        uint erc20Price = tokenPriceInERC20[_erc20Address];
        IERC20 erc20Contract = IERC20(_erc20Address);
        erc20Contract.transferFrom(msg.sender, address(this), erc20Price); // send the token to the contract.

        _mintMasterKey(msg.sender);

    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external override {
        // require(msg.sender == address(_token), "XToken777Recipient: Invalid token");
        address tokenAddress = msg.sender;
        require(WHITELIST.contains(from), "Address is not in the whitelist.");
        require(tokenPriceInERC20[tokenAddress] > 0, "Token is not supported in this contract!");
        require(whitelistedMemberMintStatus[from] == false, "Minted already");
        require(amount >=  tokenPriceInERC20[tokenAddress], "Token amount is not sufficient!");


        _mintMasterKey(from);
    }

    
    function withdraw() public onlyOwner {
        // send the native token
        payable(owner()).transfer(address(this).balance);

        //send the erc20 token
        for (uint i = 0; i < erc20Tokens.length; i++) {
            address erc20Address = erc20Tokens[i];
            IERC20 tokenContract = IERC20(erc20Address);
            tokenContract.transfer(owner(), tokenContract.balanceOf(address(this)));
        }
    }
}

