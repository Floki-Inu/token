// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.4;

/**
 * @title Transfer handler interface
 * @dev Lorem ipsum dolor sit amet.
 */
interface ITaxHandler {
    /**
     * @dev Handle transfer functionality with any designated exchange(s).
     */
    function getTax(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external view returns (uint256);
}
