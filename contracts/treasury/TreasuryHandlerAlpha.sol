// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "../utils/ExchangePoolProcessor.sol";
import "../utils/LenientReentrancyGuard.sol";

contract TreasuryHandlerAlpha is LenientReentrancyGuard, ExchangePoolProcessor {
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;

    address payable treasury;
    IERC20 public token;
    uint256 public liquidityPercentage;
    uint256 public priceImpactPercentage;
    IUniswapV2Router02 public router;

    event LiquidityPercentageUpdated(uint256 oldPercentage, uint256 newPercentage);
    event PriceImpactPercentageUpdated(uint256 oldPercentage, uint256 newPercentage);
    event TreasuryAddressUpdated(address oldTreasuryAddress, address newTreasuryAddress);

    constructor(
        address treasuryAddress,
        address tokenAddress,
        address routerAddress
    ) {
        treasury = payable(treasuryAddress);
        token = IERC20(tokenAddress);
        router = IUniswapV2Router02(routerAddress);
    }

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

    function setLiquidityPercentage(uint256 newPercentage) external onlyOwner {
        require(
            newPercentage <= 100,
            "TreasuryHandlerAlpha:setLiquidityPercentage:INVALID_PERCENTAGE: Cannot set more than 100 percent."
        );
        uint256 oldPercentage = liquidityPercentage;
        liquidityPercentage = newPercentage;

        emit LiquidityPercentageUpdated(oldPercentage, newPercentage);
    }

    function setPriceImpactPercentage(uint256 newPercentage) external onlyOwner {
        uint256 oldPercentage = priceImpactPercentage;
        priceImpactPercentage = newPercentage;

        emit PriceImpactPercentageUpdated(oldPercentage, newPercentage);
    }

    function setTreasury(address newTreasuryAddress) external onlyOwner {
        require(
            newTreasuryAddress != address(0),
            "TreasuryHandlerAlpha:setTreasury:ZERO_TREASURY: Cannot set zero address as treasury."
        );

        address oldTreasuryAddress = address(treasury);
        treasury = payable(newTreasuryAddress);

        emit TreasuryAddressUpdated(oldTreasuryAddress, newTreasuryAddress);
    }

    function withdraw(address tokenAddress, uint256 amount) external onlyOwner {
        if (tokenAddress == address(0)) {
            treasury.sendValue(amount);
        } else {
            IERC20(tokenAddress).transferFrom(address(this), address(treasury), amount);
        }
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        token.approve(address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function _addLiquidity(uint256 tokenAmount, uint256 weiAmount) private {
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
