// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./ITaxHandler.sol";
import "../utils/ExchangePoolProcessor.sol";

contract StaticTaxHandler is ITaxHandler, ExchangePoolProcessor {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _exempted;
    IERC20 public token;
    uint256 public taxBasisPoints;

    event TaxBasisPointsUpdated(uint256 oldBasisPoints, uint256 newBasisPoints);
    event TaxExemptionUpdated(address indexed wallet, bool exempted);

    constructor(address tokenAddress) {
        token = IERC20(tokenAddress);
        taxBasisPoints = 300;
    }

    function getTax(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external view override returns (uint256) {
        if (_exempted.contains(benefactor) || _exempted.contains(beneficiary)) {
            return 0;
        }

        // Transactions between regular users (this includes contract) aren't taxed.
        if (!_exchangePools.contains(benefactor) && _exchangePools.contains(beneficiary)) {
            return 0;
        }

        return (amount * taxBasisPoints) / 10000;
    }

    function setTaxBasisPoints(uint256 newBasisPoints) external onlyOwner {
        uint256 oldBasisPoints = taxBasisPoints;
        taxBasisPoints = newBasisPoints;

        emit TaxBasisPointsUpdated(oldBasisPoints, newBasisPoints);
    }

    function addExemption(address exemption) external onlyOwner {
        if (_exempted.add(exemption)) {
            emit TaxExemptionUpdated(exemption, true);
        }
    }

    function removeExemption(address exemption) external onlyOwner {
        if (_exempted.remove(exemption)) {
            emit TaxExemptionUpdated(exemption, false);
        }
    }
}
