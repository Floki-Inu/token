// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IGovernanceToken {
    struct Checkpoint {
        // The 32-bit unsigned integer is valid until these estimated dates for these given chains:
        //  - BSC: Sat Dec 23 2428 18:23:11 UTC
        //  - ETH: Tue Apr 18 3826 09:27:12 UTC
        // This assumes that block mining rates don't speed up.
        uint32 blockNumber;
        uint224 votes;
    }

    event DelegateChanged(address delegator, address currentDelegate, address newDelegate);
    event DelegateVotesChanged(address delegatee, uint224 oldVotes, uint224 newVotes);
}
