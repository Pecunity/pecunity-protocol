// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 * ┃                                                                       ┃
 * ┃                            🧱  3 B L O C K S  🧱                      ┃
 * ┃                                                                       ┃
 * ┃                 Official Pecunity Protocol Interface                  ┃
 * ┃                 Controlled Token Mechanics & Launch Logic             ┃
 * ┃                                                                       ┃
 * ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
 *
 * @title IPecunity Interface
 * @notice Defines the core functionality of the Pecunity Token (PEC),
 *         developed by 3Blocks. Extends ERC20 with controlled transfer rights
 *         and a one-time launch mechanism to manage pre-launch liquidity
 *         and community distribution phases.
 * @dev This interface is designed for transparency and auditability,
 *      outlining all necessary events, errors, and methods for managing
 *      token transfer permissions before and after launch.
 */
interface IPecunity is IERC20 {
    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Errors         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Thrown when an address attempts to transfer tokens without transfer rights.
    error NotTransferRights();

    /// @notice Thrown when attempting to launch the token after it has already been launched.
    error TokenAlreadyLaucnhed();

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Events         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Emitted when transfer rights are granted to an account.
    /// @param account The address that has been granted permission to transfer before launch.
    event TransferRightsEnabled(address indexed account);

    /// @notice Emitted when transfer rights are revoked from an account.
    /// @param account The address that has had transfer rights removed.
    event TransferRightsDisabled(address indexed account);

    /// @notice Emitted when the token is officially launched and all transfers are unrestricted.
    event TokenLaunch();

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃        Functions       ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Grants transfer rights to a specific account before launch.
    /// @dev Useful for enabling early liquidity partners or operational wallets.
    /// @param account The address to grant transfer rights to.
    function enableTransfer(address account) external;

    /// @notice Revokes transfer rights from a specific account before launch.
    /// @param account The address to remove transfer rights from.
    function disableTransfer(address account) external;

    /// @notice Marks the token as launched, enabling unrestricted transfers.
    /// @dev Can only be executed once. Further calls revert with `TokenAlreadyLaucnhed()`.
    function launch() external;

    /// @notice Returns whether a given account has transfer rights enabled.
    /// @param account The address to query.
    /// @return True if the account can transfer tokens, false otherwise.
    function transferable(address account) external view returns (bool);

    /// @notice Returns whether the token has been officially launched.
    /// @return True if launched, false otherwise.
    function launched() external view returns (bool);
}
