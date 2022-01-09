// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Governance token interface.
 */
interface IGovernanceToken {
    struct Checkpoint {
        // The 32-bit unsigned integer is valid until these estimated dates for these given chains:
        //  - BSC: Sat Dec 23 2428 18:23:11 UTC
        //  - ETH: Tue Apr 18 3826 09:27:12 UTC
        // This assumes that block mining rates don't speed up.
        uint32 blockNumber;
        uint224 votes;
    }

    function getVotesAtBlock(address account, uint32 blockNumber) external view returns (uint224);

    /// @dev Emitted whenever a new delegate is set for an account.
    event DelegateChanged(address delegator, address currentDelegate, address newDelegate);

    /// @dev Emitted when a delegate's vote count changes.
    event DelegateVotesChanged(address delegatee, uint224 oldVotes, uint224 newVotes);
}
