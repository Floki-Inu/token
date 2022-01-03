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
    uint256 public priceImpactPercentage;
    IUniswapV2Router02 public router;

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

            if (contractTokenBalance > maxPriceImpactSale) {
                contractTokenBalance = maxPriceImpactSale;
            }

            _swapTokensForEth(contractTokenBalance);

            uint256 contractEthBalance = address(this).balance;
            if (contractEthBalance > 0) {
                treasury.sendValue(contractEthBalance);
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
}
