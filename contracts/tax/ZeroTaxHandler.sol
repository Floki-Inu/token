// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.4;

import "./ITaxHandler.sol";

contract ZeroTaxHandler is ITaxHandler {
    function getTax(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external view override returns (uint256) {
        return 0;
    }
}
