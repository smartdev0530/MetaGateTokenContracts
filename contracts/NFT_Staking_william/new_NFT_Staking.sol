// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;


import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingRewards is ERC721Holder, ReentrancyGuard, Ownable, Pausable{

    IERC20 public rewardsToken;
    IERC721 public stakingToken;

    uint public rewardRate = 100;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    uint private _totalSupply;
    mapping(address => uint) private _balances;
    mapping(uint256 => address) private _stakedAssets;

    constructor(address _stakingToken, address _rewardsToken) {
        stakingToken = IERC721(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
    }

    function rewardPerToken() public view returns (uint) {
        if (_totalSupply == 0) {
            return 0;
        }
        return
            rewardPerTokenStored +
            (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / _totalSupply);
    }

    function earned(address account) public view returns (uint) {
        return
            ((_balances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    function stake(uint tokenId)  external nonReentrant whenNotPaused updateReward(msg.sender){
        _totalSupply ++;
        _balances[msg.sender] ++;

        // Transfer user's NFTs to the staking contract
        stakingToken.safeTransferFrom(msg.sender, address(this), tokenId);
        _stakedAssets[tokenId] = msg.sender;

    }

    function withdraw(uint tokenId) public nonReentrant updateReward(msg.sender) {
        require(
                _stakedAssets[tokenId] == msg.sender,
                "Staking: Not the staker of the token"
            );
        _totalSupply --;
        _balances[msg.sender] --;
        // Transfer NFTs back to the owner
        stakingToken.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        rewardsToken.transfer(msg.sender, reward);
    }

    function exit(uint tokenId) external {
        withdraw(tokenId);
        getReward();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
