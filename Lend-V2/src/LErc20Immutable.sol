// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "./LErc20.sol";

/**
 * @title Compound's LErc20Immutable Contract
 * @notice LTokens which wrap an EIP-20 underlying and are immutable
 * @author Compound
 */
contract LErc20Immutable is LErc20 {
    /**
     * @notice Construct a new money market
     * @param underlying_ The address of the underlying asset
     * @param lendtroller_ The address of the Lendtroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     * @param admin_ Address of the administrator of this token
     */
    constructor(
        address underlying_,
        LendtrollerInterface lendtroller_,
        InterestRateModel interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address payable admin_
    ) {
        // Creator of the contract is admin during initialization
        admin = payable(msg.sender);

        // Initialize the market
        initialize(
            underlying_, lendtroller_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, decimals_
        );

        // Set the proper admin now that initialization is done
        admin = admin_;
    }
}
