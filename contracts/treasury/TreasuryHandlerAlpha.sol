// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "../utils/ExchangePoolProcessor.sol";
import "../utils/LenientReentrancyGuard.sol";

/**
 * @title Treasury handler alpha contract
 * @dev Sells tokens that have accumulated through taxes and sends the resulting ETH to the treasury. If
 * `liquidityPercentage` has been set to a non-zero value, then that percentage will instead be added to the designated
 * liquidity pool.
 */
contract TreasuryHandlerAlpha is LenientReentrancyGuard, ExchangePoolProcessor {
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev The treasury address.
    address payable treasury;

    /// @dev The token that accumulates through taxes. This will be sold for ETH.
    IERC20 public token;

    /// @dev The percentage of tokens to sell and add as liquidity to the pool.
    uint256 public liquidityPercentage;

    /// @dev The maximum price impact the sell (initiated from this contract) may have.
    uint256 public priceImpactPercentage;

    /// @dev The Uniswap router that handles the sell and liquidity operations.
    IUniswapV2Router02 public router;

    /// @dev Emitted when the percentage of tokens to add as liquidity is updated.
    event LiquidityPercentageUpdated(uint256 oldPercentage, uint256 newPercentage);

    /// @dev Emitted when the maximum price impact percentage is updated.
    event PriceImpactPercentageUpdated(uint256 oldPercentage, uint256 newPercentage);

    /// @dev Emitted when the treasury address is updated.
    event TreasuryAddressUpdated(address oldTreasuryAddress, address newTreasuryAddress);

    /**
     * @param treasuryAddress Address of treasury to use.
     * @param tokenAddress Address of token to accumulate and sell.
     * @param routerAddress Address of Uniswap router for sell and liquidity operations.
     */
    constructor(
        address treasuryAddress,
        address tokenAddress,
        address routerAddress
    ) {
        treasury = payable(treasuryAddress);
        token = IERC20(tokenAddress);
        router = IUniswapV2Router02(routerAddress);
    }

    /**
     * @dev Perform operations before a sell action (or a liquidity addition) is executed. The accumulated tokens are
     * then sold for ETH. In case the number of accumulated tokens exceeds the price impact percentage threshold, then
     * the number will be adjusted to stay within the threshold. If a non-zero percentage is set for liquidity, then
     * that percentage will be added to the primary liquidity pool instead of being sold for ETH and sent to the
     * treasury.
     * @param benefactor Address of the benefactor.
     * @param beneficiary Address of the beneficiary.
     * @param amount Number of tokens in the transfer.
     */
    function beforeTransferHandler(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external nonReentrant {
        // Silence a few warnings. This will be optimized out by the compiler.
        benefactor;
        amount;

        // No actions are done on transfers other than sells.
        if (!_exchangePools.contains(beneficiary)) {
            return;
        }

        uint256 contractTokenBalance = token.balanceOf(address(token));
        if (contractTokenBalance > 0) {
            uint256 primaryPoolBalance = token.balanceOf(primaryPool);
            uint256 maxPriceImpactSale = (primaryPoolBalance * priceImpactPercentage) / 100;

            // Ensure the price impact is within reasonable bounds.
            if (contractTokenBalance > maxPriceImpactSale) {
                contractTokenBalance = maxPriceImpactSale;
            }

            // The number of tokens to sell for liquidity purposes. This is calculated as follows:
            //
            //      B     P
            //  L = - * -----
            //      2   10000
            //
            // Where:
            //  L = tokens to sell for liquidity
            //  B = available token balance
            //  P = basis points of tokens to use for liquidity
            //
            // The number is divided by two to preserve the token side of the token/WETH pool.
            uint256 liquidityBasisPoints = liquidityPercentage * 100;
            uint256 tokensForLiquidity = (contractTokenBalance * liquidityBasisPoints) / 10000 / 2;

            uint256 currentWeiBalance = address(this).balance;
            _swapTokensForEth(contractTokenBalance);
            uint256 weiEarned = currentWeiBalance - address(this).balance;
            uint256 weiForLiquidity = (weiEarned * liquidityBasisPoints) / 10000;

            _addLiquidity(tokensForLiquidity, weiForLiquidity);

            uint256 remainingWeiBalance = address(this).balance;
            if (remainingWeiBalance > 0) {
                treasury.sendValue(remainingWeiBalance);
            }
        }
    }

    /**
     * @dev Occurs after transfers, but this contract ignores those operations, hence nothing happens.
     * @param benefactor Address of the benefactor.
     * @param beneficiary Address of the beneficiary.
     * @param amount Number of tokens in the transfer.
     */
    function afterTransferHandler(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external nonReentrant {
        // Silence a few warnings. This will be optimized out by the compiler.
        benefactor;
        beneficiary;
        amount;

        return;
    }

    /**
     * @dev Set new liquidity percentage.
     * @param newPercentage New liquidity percentage. Cannot exceed 100% as that would break the calculation.
     */
    function setLiquidityPercentage(uint256 newPercentage) external onlyOwner {
        require(
            newPercentage <= 100,
            "TreasuryHandlerAlpha:setLiquidityPercentage:INVALID_PERCENTAGE: Cannot set more than 100 percent."
        );
        uint256 oldPercentage = liquidityPercentage;
        liquidityPercentage = newPercentage;

        emit LiquidityPercentageUpdated(oldPercentage, newPercentage);
    }

    /**
     * @dev Set new price impact percentage.
     * @param newPercentage New price impact percentage.
     */
    function setPriceImpactPercentage(uint256 newPercentage) external onlyOwner {
        uint256 oldPercentage = priceImpactPercentage;
        priceImpactPercentage = newPercentage;

        emit PriceImpactPercentageUpdated(oldPercentage, newPercentage);
    }

    /**
     * @dev Set new treasury address.
     * @param newTreasuryAddress New treasury address.
     */
    function setTreasury(address newTreasuryAddress) external onlyOwner {
        require(
            newTreasuryAddress != address(0),
            "TreasuryHandlerAlpha:setTreasury:ZERO_TREASURY: Cannot set zero address as treasury."
        );

        address oldTreasuryAddress = address(treasury);
        treasury = payable(newTreasuryAddress);

        emit TreasuryAddressUpdated(oldTreasuryAddress, newTreasuryAddress);
    }

    /**
     * @dev Withdraw any tokens or ETH stuck in the treasury handler.
     * @param tokenAddress Address of the token to withdraw. If set to the zero address, ETH will be withdrawn.
     * @param amount The number of tokens to withdraw.
     */
    function withdraw(address tokenAddress, uint256 amount) external onlyOwner {
        if (tokenAddress == address(0)) {
            treasury.sendValue(amount);
        } else {
            IERC20(tokenAddress).transferFrom(address(this), address(treasury), amount);
        }
    }

    /**
     * @dev Swap accumulated tokens for ETH.
     * @param tokenAmount Number of tokens to swap for ETH.
     */
    function _swapTokensForEth(uint256 tokenAmount) private {
        // The ETH/token pool is the primary pool. It always exists.
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        // Ensure the router can perform the swap for the designated number of tokens.
        token.approve(address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    /**
     * @dev Add liquidity to primary pool.
     * @param tokenAmount Number of tokens to add as liquidity.
     * @param weiAmount ETH value to pair with the tokens.
     */
    function _addLiquidity(uint256 tokenAmount, uint256 weiAmount) private {
        // Both minimum values are set to zero to allow for any form of slippage.
        router.addLiquidityETH{ value: weiAmount }(
            address(token),
            tokenAmount,
            0,
            0,
            address(treasury),
            block.timestamp
        );
    }
}
