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

contract MetaKeyNFT is ERC721, ReentrancyGuard, Ownable,  VRFConsumerBase,  IMasterKeyMintable, IERC777Recipient {

    //events
    event MetaKeyNFTMinted(address _owner, uint _tokenId,  uint _mintTime);
    event MetaKeyActivated(address _owner, uint _tokenId);
    event WhiteListChanged(address[] _users, bool _add);
    event RandomSeedGenerated(uint _randomValue);


    // the rentFeeTaker takes _rentFee / _feeDivident * rentPrice
    using EnumerableSet for EnumerableSet.AddressSet;
    // using Counters for Counters.Counter; //counter for the mint


    // address public propertyAddress; // contract address of Property NFT
    // address public avatarAddress; // address of avatar NFT
    address[] private nftContracts;
    mapping(string => address) private nftNameMap;

    EnumerableSet.AddressSet WHITELIST;  // whitelist
    mapping(address => bool) whitelistedMemberMintStatus;
    // Counters.Counter private tokenCounter;
    address public masterKeyContract;

    uint constant public MAX_ID = 10000; // here set the max id to 10000 , we can fix it later

    // uint private currentAvailableId = MAX_ID + 1;

    uint public activateTime = 999999999999; // time stamp when activation is available, first set invalid time
    uint public tokenPrice = 0;  // now we accept native tokens in the chain, first set invalid value

    

    bytes32 internal keyHash; // keyhash for chainlink.
    uint256 internal fee;    // fee for LINK token.

    // uint[] public generatedIds;
    uint public generatedIdCount = 0;
    mapping(uint => bool) generatedIds;  //maybe equal to ownerOf(tokenId)

    //erc20 tokens list
    mapping(address => uint) tokenPriceInERC20;
    address[] erc20Tokens;

    uint public randomSeed;  // for the test, we set the randomSeed public


    //erc 777
     //keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
    0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;


    
    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    //now not sure to set the related Contract in the constructer, after can be change
    uint private randNonce = 0;

    constructor(address _VRFCoordinator, address _LinkToken, bytes32 _keyhash) 
        ERC721("MetagateMetaKey", "GateMetaKey")
        VRFConsumerBase(_VRFCoordinator, _LinkToken)
    {  
        // set the NFT name to "IBOME"
        //for chainlink

        // now disable chainlink
        keyHash = _keyhash;
        fee = 0.1 * 10**18; // 0.1 LINK

        //for ERC777 tokens 
        //for dev net just disable this
        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function initializeRandomSeed() onlyOwner public {
        // currentAvailableId = MAX_ID + 1;
        requestNewRandomNumber();
    }

    // // set the property Address of the meta key contract
    // function setPropertyAddress(address _propertyAddress) public onlyOwner {
    //     require(propertyAddress == address(0), "Property contract has alreay been set.");
    //     propertyAddress = _propertyAddress;
    // }

    // // set the avatar address of the meta key contract
    // function setAvatarAddress(address _avatarAddress) public onlyOwner {
    //     require(avatarAddress == address(0), "Avatar contract has alreay been set.");
    //     avatarAddress = _avatarAddress;
    // }


    // Set IMetaKeyMintable address and name for MetaKeyContract
    function setNFTAddress(string memory _nftName, address _nftAddress) public {
        require(nftNameMap[_nftName] == address(0), "Name has used before");
        nftNameMap[_nftName] = _nftAddress;
        nftContracts.push(_nftAddress);
    }

    // set the MasterKeyContract address of the meta key contract.
    function setMasterKeyContractAddress(address _masterAddress) onlyOwner public {
        require(masterKeyContract == address(0), "matser Key contract has alreay been set.");
        masterKeyContract = _masterAddress;
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

    function getTokenId() public override returns(uint) {
        //restrict function caller to the contract and msg.sender
        require(msg.sender == address(this) || msg.sender == masterKeyContract, "Only master contract and contract itself can call getTokenId");
        // require(currentAvailableId < MAX_ID, "Current token id can not be used");
        // uint retValue = currentAvailableId; //save the current token id
        // currentAvailableId = MAX_ID + 1; // set currentTokenId invalid
        // // requestNewRandomNumber(); // start generating new random number
        // return retValue;

        // uint nextTokenId = randomNumber % (MAX_ID - generatedIdCount);

        uint tokenId = _randMod(MAX_ID - generatedIdCount);

        //get availabeTokenId;
        //Must pay attention to the gas problem
        for (uint i = 0; (i < MAX_ID && i <= tokenId); i++) {
            if (generatedIds[i]) tokenId++;
        }

        generatedIds[tokenId] = true;
        generatedIdCount++;

        return tokenId;
    }

    function requestNewRandomNumber() internal returns (bytes32) {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );
        bytes32 requestId = requestRandomness(keyHash, fee);
        // requestToCharacterName[requestId] = name;
        // requestToSender[requestId] = msg.sender;
        
        return requestId;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomNumber)
        internal
        override
    {
        // uint generatedCount = generatedIds.length;
        // uint nextTokenId = randomNumber % (MAX_ID - generatedIdCount);
        // for (uint i = 0; (i < MAX_ID && i <= nextTokenId); i++) {
        //     if (generatedIds[i]) nextTokenId++;
        // }

        // // if (ownerOf(nextTokenId) != address(0)) { // if the generated token id is used
        // //     requestNewRandomNumber();
        // //     return;
        // // }
        // generatedIds[nextTokenId] = true;
        // generatedIdCount++;
        // currentAvailableId = nextTokenId;
        randomSeed = randomNumber;
        emit RandomSeedGenerated(randomSeed);
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

    // mintMetaKeyNFT for customer, here admin mints it and send it to the owner

    function mintMetaKeyNFTInEth() public payable {
        //here only whitelisted users can mint
        require(WHITELIST.contains(msg.sender), "Address is not in the whitelist.");
        require(msg.value >= tokenPrice, "Value is smaller than the price");
        require(whitelistedMemberMintStatus[msg.sender] == false, "Minted already");

        _mintMetaKey(msg.sender);
    }

    function mintMetaKeyNFTInERC20(address _erc20Address) public {
        require(WHITELIST.contains(msg.sender), "Address is not in the whitelist.");
        require(tokenPriceInERC20[_erc20Address] > 0, "Token is not supported in this contract!");
        require(whitelistedMemberMintStatus[msg.sender] == false, "Minted already");

        //send erc20 token to the contract
        uint erc20Price = tokenPriceInERC20[_erc20Address];
        IERC20 erc20Contract = IERC20(_erc20Address);
        erc20Contract.transferFrom(msg.sender, address(this), erc20Price); // send the token to the contract.

        _mintMetaKey(msg.sender);
    }

    function mintFromMasterKey() external override returns(uint) {
        require(msg.sender == masterKeyContract, "msg.sender must be Master Contract");
        //just mint for master key contract
        return _mintMetaKey(msg.sender);
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

        _mintMetaKey(from);
    }

    function _mintMetaKey(address _owner) internal returns(uint){
        uint tokenId = getTokenId();    
        whitelistedMemberMintStatus[_owner] = true;
        _mint(_owner, tokenId); // mint the token to msg.sender
        
        emit MetaKeyNFTMinted(_owner, tokenId, block.timestamp);
        return tokenId;
    }

    function activateMetaKeyNFT(uint _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender, "Only token owner can actiate meta key NFT");
        require(activateTime <= block.timestamp, "After the activate time, you can activate it");
        address owner = msg.sender;

        for (uint i = 0; i < nftContracts.length; i++) {
            IMetaKeyMintable currentContract = IMetaKeyMintable(nftContracts[i]);
            currentContract.mintFromMetaKey(_tokenId, owner);
        }
        // IMetaKeyMintable propertyContract = IMetaKeyMintable(propertyAddress);
        // propertyContract.mintFromMetaKey(_tokenId, owner);
        // IMetaKeyMintable avatarContract = IMetaKeyMintable(avatarAddress);
        // avatarContract.mintFromMetaKey(_tokenId, owner);

        _burn(_tokenId);
        emit MetaKeyActivated(owner, _tokenId);
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


    // Defining a function to generate
    // a random number
    function _randMod(uint _modulus) internal returns(uint)
    {
    // increase nonce
        randNonce++; 
        return uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, randNonce, randomSeed))) % _modulus;
    }
}

