//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "openzeppelin/contracts/token/ERC20/ERC20.sol";
import "openzeppelin/contracts/utils/math/SafeMath.sol";
import "openzeppelin/contracts/access/Ownable.sol";
import "./Uniswap/IUniswapV2Router02.sol";
import "./Uniswap/IUniswapV2Factory.sol";
import "./Uniswap/IUniswapV2Pair.sol";


/**
 * @title NOVA
 * @author Justin W
 * @notice Implements a basic ERC20 staking token with incentive distribution.
 */
contract StakingToken is ERC20, Ownable {
    using SafeMath for uint256;
    /**
     * @notice We usually require to know who are all the stakeholders.
     */
    address[] internal stakeholders;
    uint private presaleAmount = 0;
    uint private currentPresaleAmount = 0;
    address Owner;

    address private ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // ropsten

    event SwapedTokenForEth(uint256 TokenAmount);
    event AddLiquify(uint256 WethAmount, uint256 tokensIntoLiquidity);

    IUniswapV2Router02 public router;
    address public pair;
    uint256 public liquidityAddedAt = 0;
    uint256 public totalStakedAmount = 0;

    uint public rewardPerTokenStored;

    

    /**
     * @notice The stakes for each stakeholder.
     */
    mapping(address => uint256) internal stakes;

    /**
     * @notice The accumulated rewards for each stakeholder.
     */
    mapping(address => uint256) internal rewards;
    mapping(address => uint256) internal lastUpdateTime;
    uint256 public totalSupply = 10 ** 7 ether;

    uint public oneYearDuration = 365 days;
    uint public rewardRate = 30;

    /**
     * @notice The constructor for the Staking Token.
     * @param _owner The address to receive all tokens on construction.
     * @param _supply The amount of tokens to mint on construction.
     */
    constructor(address _owner) ERC20("NOVA", "$Nova") 
    { 
        _mint(_owner, totalSupply);
        Owner = _owner;
        presaleAmount = _supply * 20 / 100;
        router = IUniswapV2Router02(ROUTER);
        pair = IUniswapV2Factory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );
        liquidityAddedAt = block.timestamp;
        _approve(address(this), ROUTER, type(uint256).max);
        _approve(_owner, address(this), type(uint256).max);
    }


    /** Presale 20% of Supply for 20 ETH | 200.000 Tokens | Token Price: 0.0001 ETH, -2x from Launch Price */
    function presale() public payable {
        require(msg.value > 0, "Should call with values");
        uint amount = msg.value / 1e14;    // presale price is 0.0001 ETH 
        currentPresaleAmount += amount;
        require(presaleAmount >= currentPresaleAmount, "Ended presale");

        transferFrom(Owner, msg.sender, amount);
        payable(msg.sender).transfer(msg.value - (amount * 1e14));
    }
    // ---------- STAKES ----------

    /**
     * @notice A method for a stakeholder to create a stake.
     * @param _stake The size of the stake to be created.
     */
    function createStake(uint256 _stake)
        public updateReward(msg.sender)
    {
        _burn(msg.sender, _stake);
        totalStakedAmount += _stake;
        if(stakes[msg.sender] == 0) addStakeholder(msg.sender);
        stakes[msg.sender] = stakes[msg.sender].add(_stake);
    }

    function swapTokensForWeth(uint256 amount, address ethRecipient) private {
        //@dev Generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        //@dev Make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0, // accept any amount of ETH
            path,
            ethRecipient,
            block.timestamp
        );

        emit SwapedTokenForEth(amount);
    }

    /** tokenAmount should be 40% of totalSupply */
    function addLiquidity(uint256 tokenAmount, uint256 WethAmount) public {
        // add the liquidity
        router.addLiquidityETH{value: WethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

        emit AddLiquify(WethAmount, tokenAmount);
    }


    function earned(address account) public view returns (uint) {
        return stakes[account] * (block.timestamp - lastUpdateTime[account]) * rewardRate / oneYearDuration / 100;
    }


    modifier updateReward(address account) {
        rewards[account].add(earned(account));
        lastUpdateTime[account] = block.timestamp;
        _;
    }

    /**
     * @notice A method for a stakeholder to remove a stake.
     * @param _stake The size of the stake to be removed.
     */
    function removeStake(uint256 _stake)
        public updateReward(msg.sender)
    {
        require(stakes[msg.sender] >= _stake, "staked amount is less than remove stake amount");
        stakes[msg.sender] = stakes[msg.sender].sub(_stake);
        if(stakes[msg.sender] == 0) removeStakeholder(msg.sender);
        transfer(msg.sender, _stake);
        totalStakedAmount -= _stake;
        _mint(msg.sender, _stake);
    }

    /**
     * @notice A method to retrieve the stake for a stakeholder.
     * @param _stakeholder The stakeholder to retrieve the stake for.
     * @return uint256 The amount of wei staked.
     */
    function stakeOf(address _stakeholder)
        public
        view
        returns(uint256)
    {
        return stakes[_stakeholder];
    }

    /**
     * @notice A method to the aggregated stakes from all stakeholders.
     * @return uint256 The aggregated stakes from all stakeholders.
     */
    function totalStakes()
        public
        view
        returns(uint256)
    {
        return totalStakedAmount;
    }

    // ---------- STAKEHOLDERS ----------

    /**
     * @notice A method to check if an address is a stakeholder.
     * @param _address The address to verify.
     * @return bool, uint256 Whether the address is a stakeholder, 
     * and if so its position in the stakeholders array.
     */
    function isStakeholder(address _address)
        public
        view
        returns(bool, uint256)
    {
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            if (_address == stakeholders[s]) return (true, s);
        }
        return (false, 0);
    }

    /**
     * @notice A method to add a stakeholder.
     * @param _stakeholder The stakeholder to add.
     */
    function addStakeholder(address _stakeholder)
        public
    {
        (bool _isStakeholder, ) = isStakeholder(_stakeholder);
        if(!_isStakeholder) stakeholders.push(_stakeholder);
    }

    /**
     * @notice A method to remove a stakeholder.
     * @param _stakeholder The stakeholder to remove.
     */
    function removeStakeholder(address _stakeholder)
        public
    {
        (bool _isStakeholder, uint256 s) = isStakeholder(_stakeholder);
        if(_isStakeholder){
            stakeholders[s] = stakeholders[stakeholders.length - 1];
            stakeholders.pop();
        } 
    }

    // ---------- REWARDS ----------
    
    /**
     * @notice A method to allow a stakeholder to check his rewards.
     * @param _stakeholder The stakeholder to check rewards for.
     */
    function rewardOf(address _stakeholder) 
        public
        view updateReward(_stakeholder)
        returns(uint256)
    {
        return rewards[_stakeholder];
    }

    // /**
    //  * @notice A method to the aggregated rewards from all stakeholders.
    //  * @return uint256 The aggregated rewards from all stakeholders.
    //  */
    // function totalRewards()
    //     public
    //     view
    //     returns(uint256)
    // {
    //     uint256 _totalRewards = 0;
    //     for (uint256 s = 0; s < stakeholders.length; s += 1){
    //         _totalRewards = _totalRewards.add(rewards[stakeholders[s]]);
    //     }
    //     return _totalRewards;
    // }

    // /** 
    //  * @notice A simple method that calculates the rewards for each stakeholder.
    //  * @param _stakeholder The stakeholder to calculate rewards for.
    //  */
    // function calculateReward(address _stakeholder)
    //     public
    //     view
    //     returns(uint256)
    // {
    //     return stakes[_stakeholder] / 100;
    // }

    /**
     * @notice A method to distribute rewards to all stakeholders.
     */
    // function distributeRewards() 
    //     public
    //     onlyOwner
    // {
    //     for (uint256 s = 0; s < stakeholders.length; s += 1){
    //         address stakeholder = stakeholders[s];
    //         uint256 reward = calculateReward(stakeholder);
    //         rewards[stakeholder] = rewards[stakeholder].add(reward);
    //     }
    // }

    /**
     * @notice A method to allow a stakeholder to withdraw his rewards.
     */
    function withdrawReward() 
        public updateReward(msg.sender)
    {
        uint reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        transferFrom(owner, msg.sender, reward);
    }
}