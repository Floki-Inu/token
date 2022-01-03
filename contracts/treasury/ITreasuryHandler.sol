// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface ITreasuryHandler {
    function beforeTransferHandler(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external;

    function afterTransferHandler(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external;
}
