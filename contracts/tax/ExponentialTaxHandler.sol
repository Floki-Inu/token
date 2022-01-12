// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./ITaxHandler.sol";
import "../utils/ExchangePoolProcessor.sol";

/**
 * @title Exponential tax handler contract
 * @dev This contract allows protocols to collect tax on transactions that count as either sells or liquidity additions
 * to exchange pools. Addresses can be exempted from tax collection, and addresses designated as exchange pools can be
 * added and removed by the owner of this contract. The owner of the contract should be set to a DAO-controlled timelock
 * or at the very least a multisig wallet.
 */
contract ExponentialTaxHandler is ITaxHandler, ExchangePoolProcessor {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev The set of addresses exempt from tax.
    EnumerableSet.AddressSet private _exempted;

    /// @notice The token to account for.
    IERC20 public token;

    /// @notice How much tax to collect in basis points. 10,000 basis points is 100%.
    uint256 public taxBasisPoints;

    /// @notice Emitted when the tax basis points number is updated.
    event TaxBasisPointsUpdated(uint256 oldBasisPoints, uint256 newBasisPoints);

    /// @notice Emitted when an address is added to or removed from the exempted addresses set.
    event TaxExemptionUpdated(address indexed wallet, bool exempted);

    constructor(address tokenAddress) {
        token = IERC20(tokenAddress);
    }

    /**
     * @notice Get number of tokens to pay as tax. This method specifically only check for sell-type transfers to
     * designated exchange pool addresses.
     * @dev There is no easy way to differentiate between a user selling tokens and a user adding liquidity to the pool.
     * In both cases tokens are transferred to the pool. This is an unfortunate case where users have to accept being
     * taxed on liquidity additions. To get around this issue, a separate liquidity addition contract can be deployed.
     * This contract can be exempt from taxes if its functionality is verified to only add liquidity.
     * @param benefactor Address of the benefactor.
     * @param beneficiary Address of the beneficiary.
     * @param amount Number of tokens in the transfer.
     * @return Number of tokens to pay as tax.
     */
    function getTax(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external view override returns (uint256) {
        if (_exempted.contains(benefactor) || _exempted.contains(beneficiary)) {
            return 0;
        }

        // Transactions between regular users (this includes contracts) aren't taxed.
        if (!_exchangePools.contains(benefactor) && !_exchangePools.contains(beneficiary)) {
            return 0;
        }

        // Tax is 3% on buys.
        if (_exchangePools.contains(benefactor)) {
            return (amount * 300) / 10000;
        }

        uint256 priceImpactBasisPoint = token.balanceOf(primaryPool) / 10000;

        if (amount <= priceImpactBasisPoint * 300) {
            return (amount * 300) / 10000;
        } else if (amount <= priceImpactBasisPoint * 1000) {
            return (amount * 900) / 10000;
        } else if (amount <= priceImpactBasisPoint * 2000) {
            return (amount * 2700) / 10000;
        } else {
            return (amount * 8100) / 10000;
        }
    }

    //    /**
    //     * @notice Get impact tier correlating to given token amount.
    //     * @param amount The number of tokens in the transfer.
    //     * @return The impact tier.
    //     */
    //    function getImpactTier(uint256 amount) public view returns (uint256) {
    //        // Calculate what impact selling `amount` would have on the pool. This number is calculated through the following
    //        uint256 priceImpact = amount * 10000 / token.balanceOf(primaryPool);
    //
    //        uint256 poolBalance = token.balanceOf(primaryPool);
    //        uint256 poolBasisPoint = poolBalance / 10000;
    //        uint256 amountInBasisPoints = amount / poolBalance;
    //
    //        return 0;
    //    }

    /**
     * @notice Add address to set of tax-exempted addresses.
     * @param exemption Address to add to set of tax-exempted addresses.
     */
    function addExemption(address exemption) external onlyOwner {
        if (_exempted.add(exemption)) {
            emit TaxExemptionUpdated(exemption, true);
        }
    }

    /**
     * @notice Remove address from set of tax-exempted addresses.
     * @param exemption Address to remove from set of tax-exempted addresses.
     */
    function removeExemption(address exemption) external onlyOwner {
        if (_exempted.remove(exemption)) {
            emit TaxExemptionUpdated(exemption, false);
        }
    }
}
