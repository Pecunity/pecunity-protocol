// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPecunity} from "./interfaces/IPecunity.sol";

/**
 * ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 * ┃                                                                       ┃
 * ┃                            🧱  3 B L O C K S  🧱                      ┃
 * ┃                                                                       ┃
 * ┃                      P E C U N I T Y   T O K E N                      ┃
 * ┃                                                                       ┃
 * ┃        Controlled ERC20 Token with Launch & Transfer Management       ┃
 * ┃                                                                       ┃
 * ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
 *
 * @title Pecunity Token (PEC)
 * @notice Implementation of the Pecunity Token by 3Blocks, extending OpenZeppelin’s ERC20
 *         with additional mechanics for controlled transfer permissions and a one-time launch function.
 * @dev
 * - Before launch, only whitelisted accounts may transfer tokens.
 * - Once launched, transfers are unrestricted globally.
 * - Implements ERC20Burnable and ERC20Permit for flexibility and DeFi compatibility.
 * - Uses OpenZeppelin Ownable for administrative control.
 */
contract Pecunity is ERC20, ERC20Burnable, ERC20Permit, Ownable, IPecunity {
    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         State Vars        ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Tracks whether the token has been officially launched.
    bool private _launched = false;

    /// @notice Maps each account to its transfer rights status before launch.
    mapping(address => bool) private _transferEnabled;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃         Modifiers         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @notice Restricts access to functions that can only be called before the token is launched.
    /// @dev Once `_launched` is true, this modifier prevents further modification of state.
    modifier prelaunch() {
        if (_launched) {
            revert TokenAlreadyLaucnhed();
        }
        _;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃       Constructor         ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Deploys the Pecunity token contract.
     * @param initialOwner The address that will receive the initial supply and own the contract.
     * @param maxSupply The total supply of PEC tokens to mint upon deployment.
     */
    constructor(
        address initialOwner,
        uint256 maxSupply
    ) ERC20("Pecunity", "PEC") ERC20Permit("Pecunity") Ownable(initialOwner) {
        //enable the zero address and the initialOwner
        _enableTransfer(address(0));
        _enableTransfer(initialOwner);

        _mint(initialOwner, maxSupply);
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Public Functions      ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Grants transfer rights to an account before the token is launched.
     * @dev Only callable by the contract owner during the pre-launch phase.
     * @param account The address to grant transfer permission to.
     */
    function enableTransfer(address account) external onlyOwner prelaunch {
        _enableTransfer(account);
    }

    /**
     * @notice Revokes transfer rights from an account before the token is launched.
     * @dev Only callable by the contract owner during the pre-launch phase.
     * @param account The address to revoke transfer permission from.
     */
    function disableTransfer(address account) external onlyOwner prelaunch {
        _transferEnabled[account] = false;
        emit TransferRightsDisabled(account);
    }

    /**
     * @notice Officially launches the token, enabling unrestricted transfers for all users.
     * @dev Can only be executed once by the owner. Once launched, this action cannot be undone.
     */
    function launch() external onlyOwner prelaunch {
        _launched = true;
        emit TokenLaunch();
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Internal Functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Internal ERC20 transfer hook override.
     * @dev Prevents token transfers from non-whitelisted accounts before the official launch.
     * @param from The address sending tokens.
     * @param to The address receiving tokens.
     * @param value The amount of tokens being transferred.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        // Before launch, restrict transfers to authorized accounts only.
        if (!_launched && !_transferEnabled[from]) {
            revert NotTransferRights();
        }
        super._update(from, to, value);
    }

    function _enableTransfer(address account) internal {
        _transferEnabled[account] = true;
        emit TransferRightsEnabled(account);
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    View Functions      ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice Returns whether a specific account currently has transfer rights.
     * @param account The address to check.
     * @return True if the account can transfer tokens, false otherwise.
     */
    function transferable(address account) external view returns (bool) {
        return _transferEnabled[account];
    }

    /**
     * @notice Returns whether the token has been officially launched.
     * @return True if launched and transfers are globally enabled, false otherwise.
     */
    function launched() external view returns (bool) {
        return _launched;
    }
}
