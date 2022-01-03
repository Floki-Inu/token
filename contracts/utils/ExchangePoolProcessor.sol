// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract ExchangePoolProcessor is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal _exchangePools;
    address public primaryPool;

    function addExchangePool(address exchangePool) external onlyOwner {
        _exchangePools.add(exchangePool);
    }

    function removeExchangePool(address exchangePool) external onlyOwner {
        _exchangePools.remove(exchangePool);
    }

    function setPrimaryPool(address exchangePool) external onlyOwner {
        require(
            _exchangePools.contains(exchangePool),
            "ExchangePoolProcessor:setPrimaryPool:INVALID_POOL - Given address is not registered as exchange pool."
        );
        require(
            primaryPool != exchangePool,
            "ExchangePoolProcessor:setPrimaryPool:ALREADY_SET - This address is already the primary pool address."
        );

        primaryPool = exchangePool;
    }
}
