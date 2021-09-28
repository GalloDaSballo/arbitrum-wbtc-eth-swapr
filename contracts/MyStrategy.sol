// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/badger/IController.sol";
import "../interfaces/badger/ISett.sol";

import {IUniswapRouterV2} from "../interfaces/uniswap/IUniswapRouterV2.sol";
import {
    IERC20StakingRewardsDistribution
} from "../interfaces/swapr/IERC20StakingRewardsDistribution.sol";

import {BaseStrategy} from "../deps/BaseStrategy.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    address public lpComponent; // Token we provide liquidity with
    address public reward; // Token we farm and swap to want / lpComponent

    address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // LP component we create when depositing weth/swapr, used for deposits to helper vault
    address public constant WETH_SWAPR_LP =
        0xA66b20912cBEa522278f3056B4aE60D0d3EE271b;
    // Vault for WETH/SWAPR, we deposit 50% of reward value as WETH/SWAPR
    // NOTE: At time of coding this is the development vault with development settings
    // Make sure the helper_vault has been configured properly before pushing this strat to prod
    ISett public constant HELPER_VAULT =
        ISett(0x0c2153e8aE4DB8233c61717cDC4c75630E952561);

    // Got from REGISTRY.get("badgerTree")
    address public constant badgerTree =
        0x635EB2C39C75954bb53Ebc011BDC6AfAAcE115A6;

    IUniswapRouterV2 public constant DX_SWAP_ROUTER =
        IUniswapRouterV2(0x530476d5583724A89c8841eB6Da76E7Af4C0F17E);

    // Can be changed by governance via setStakingContract
    address public stakingContract; // NOTE: Set in initialize as we can't set vars here
    bool public autocompoundOnWithdrawAll; // Should we swap rewards to want in withdrawAll? // False by default

    // Used to signal to the Badger Tree that rewards where sent to it
    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _controller,
            _keeper,
            _guardian
        );
        /// @dev Add config here
        want = _wantConfig[0];
        lpComponent = _wantConfig[1];
        reward = _wantConfig[2];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @notice initial staking contract at time of development
        stakingContract = 0x79ba8b76F61Db3e7D994f7E384ba8f7870A043b7;

        /// @dev do one off approvals here
        // Approvals for swaps and LP
        IERC20Upgradeable(reward).safeApprove(
            address(DX_SWAP_ROUTER),
            type(uint256).max
        );
        IERC20Upgradeable(WBTC).safeApprove(
            address(DX_SWAP_ROUTER),
            type(uint256).max
        );
        IERC20Upgradeable(WETH).safeApprove(
            address(DX_SWAP_ROUTER),
            type(uint256).max
        );

        // Approval for deposit
        IERC20Upgradeable(want).safeApprove(stakingContract, type(uint256).max);

        // Approval to allow depositFor for badgerTree
        IERC20Upgradeable(WETH_SWAPR_LP).safeApprove(
            address(HELPER_VAULT),
            type(uint256).max
        );
    }

    /// @dev Governance Set new stakingContract Function
    /// @notice this method is "safe" only if governance is a timelock
    function setStakingContract(address newStakingAddress) external {
        _onlyGovernance();

        require(newStakingAddress != address(0));

        if (stakingContract != address(0)) {
            if (balanceOfPool() > 0) {
                // Withdraw from old stakingContract
                IERC20StakingRewardsDistribution(stakingContract).exit(
                    address(this)
                );
            }
            IERC20Upgradeable(want).safeApprove(stakingContract, 0);
        }

        // Set new stakingContract
        stakingContract = newStakingAddress;

        // Add approvals to new stakingContract
        IERC20Upgradeable(want).safeApprove(stakingContract, type(uint256).max);

        if (balanceOfWant() > 0) {
            // Deposit all in new stakingContract
            IERC20StakingRewardsDistribution(stakingContract).stake(
                balanceOfWant()
            );
        }
    }

    function setAutocompoundOnWithdrawAll(bool newAutocompoundOnWithdrawAll)
        public
    {
        _onlyGovernance();
        autocompoundOnWithdrawAll = newAutocompoundOnWithdrawAll;
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external pure override returns (string memory) {
        return "Arbitrum-WBTC-WETH-swapr";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public view override returns (uint256) {
        return
            IERC20StakingRewardsDistribution(stakingContract).stakedTokensOf(
                address(this)
            );
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public view override returns (bool) {
        return true;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens()
        public
        view
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](6);
        protectedTokens[0] = want;
        protectedTokens[1] = lpComponent;
        protectedTokens[2] = reward;
        protectedTokens[3] = stakingContract; //NOTE: may not be needed, but doesn't hurt to have
        protectedTokens[4] = WBTC;
        protectedTokens[5] = WETH;
        return protectedTokens;
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for (uint256 x = 0; x < protectedTokens.length; x++) {
            require(
                address(protectedTokens[x]) != _asset,
                "Asset is protected"
            );
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        // NOTE: This reverts if emission has ended, just change the staking contract then
        IERC20StakingRewardsDistribution(stakingContract).stake(_amount);
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        // Withdraws all and claims rewards
        IERC20StakingRewardsDistribution(stakingContract).exit(address(this));

        // False by default
        if (autocompoundOnWithdrawAll) {
            // Swap rewards into want
            _swapRewardsToWant();
        }
    }

    /// @dev withdraw the specified amount of want, liquidate from lpComponent to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        // Due to rounding errors on the Controller, the amount may be slightly higher than the available amount in edge cases.
        if (balanceOfWant() < _amount) {
            uint256 toWithdraw = _amount.sub(balanceOfWant());

            if (balanceOfPool() < toWithdraw) {
                IERC20StakingRewardsDistribution(stakingContract).withdraw(
                    balanceOfPool()
                );
            } else {
                IERC20StakingRewardsDistribution(stakingContract).withdraw(
                    toWithdraw
                );
            }
        }

        return MathUpgradeable.min(_amount, balanceOfWant());
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));
        uint256 _beforeHelper =
            IERC20Upgradeable(WETH_SWAPR_LP).balanceOf(address(this));

        // Claim rewards
        IERC20StakingRewardsDistribution(stakingContract).claimAll(
            address(this)
        );

        // Swap to want
        _swapRewardsToWant();

        harvested = IERC20Upgradeable(want).balanceOf(address(this)).sub(
            _before
        );
        uint256 _afterHelper =
            IERC20Upgradeable(WETH_SWAPR_LP).balanceOf(address(this)).sub(
                _beforeHelper
            );

        /// @notice Take performance fee on want harvested
        _processRewardsFees(harvested, want);
        /// @notice Take performance fee on helper we got
        _processRewardsFees(_afterHelper, WETH_SWAPR_LP);

        //NOTE: This strat may end up emitting in future

        // TODO: If you are harvesting a reward token you're not compounding
        uint256 toEmit =
            IERC20Upgradeable(WETH_SWAPR_LP).balanceOf(address(this));
        if (toEmit > 0) {
            // NOTE: Would be better to take fees as HELPER_VAULT as they auto-compound for treasury
            uint256 treeBefore = HELPER_VAULT.balanceOf(badgerTree);
            HELPER_VAULT.depositFor(badgerTree, toEmit);
            uint256 treeAfter = HELPER_VAULT.balanceOf(badgerTree);
            uint256 emitted = treeAfter.sub(treeBefore);

            // NOTE: Signal the amount of reward sent to the badger tree
            emit TreeDistribution(
                address(HELPER_VAULT),
                emitted,
                block.number,
                block.timestamp
            );
        }

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(harvested, block.number);

        /// @dev Harvest must return the amount of want increased
        return harvested;
    }

    function _swapRewardsToWant() internal {
        uint256 toSwap = IERC20Upgradeable(reward).balanceOf(address(this));

        if (toSwap == 0) {
            return;
        }
        address[] memory path = new address[](2);
        path[0] = reward; // Swapr
        path[1] = WETH;

        // Swap 75% swapr for WETH
        DX_SWAP_ROUTER.swapExactTokensForTokens(
            toSwap.mul(75).div(100),
            0,
            path,
            address(this),
            now
        );

        // Provide liqudity to SWAPR / WETH HERE
        DX_SWAP_ROUTER.addLiquidity(
            reward,
            WETH,
            IERC20Upgradeable(reward).balanceOf(address(this)),
            IERC20Upgradeable(WETH).balanceOf(address(this)), // Note this may make input too high, need to test
            0,
            0,
            address(this),
            now
        );

        // Of the remaining (it's going to be 50% of initial reward value)
        // Swap 50% of WETH to wBTC
        path[0] = WETH;
        path[1] = WBTC;
        DX_SWAP_ROUTER.swapExactTokensForTokens(
            IERC20Upgradeable(WETH).balanceOf(address(this)).mul(50).div(100),
            0,
            path,
            address(this),
            now
        );

        // Now that we have WBTC and WETH, lp for more want
        DX_SWAP_ROUTER.addLiquidity(
            WBTC,
            WETH,
            IERC20Upgradeable(WBTC).balanceOf(address(this)),
            IERC20Upgradeable(WETH).balanceOf(address(this)),
            0,
            0,
            address(this),
            now
        );
    }

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();

        if (IERC20Upgradeable(want).balanceOf(address(this)) > 0) {
            // NOTE: This will revert if staking has ended, just change to next staking contract
            IERC20StakingRewardsDistribution(stakingContract).stake(
                IERC20Upgradeable(want).balanceOf(address(this))
            );
        }
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token)
        internal
        returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee)
    {
        governanceRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }
}
