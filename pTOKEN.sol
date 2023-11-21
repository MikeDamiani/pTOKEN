//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts@v4.9.3/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable2Step} from "@openzeppelin/contracts@v4.9.3/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@v4.9.3/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts@v4.9.3/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts@v4.9.3/token/ERC20/IERC20.sol";
/**
 * @title pTOKEN, Yield bearing token backed by ERC20
 *
 * @notice The backing / pTOKEN ratio is designed to appreciate for every mints and redeems that occur.
 * @custom:purpose The main purpose of pTOKENs is to generate revenue and contribute to bribing economy of ve(3;3) Dexes while being backed
 *
 * @author Michael Damiani
 */
contract pTOKEN is ERC20Burnable, Ownable2Step, ReentrancyGuard {

    using SafeERC20 for IERC20;

    /**
     * @custom:section                           ** ERRORS **
     */
    error ZeroAddressNotAllowed();
    error MustTradeOverMin();
    error MintAndRedeemFeeNotInRange();
    error TeamFeeNotInRange();

    /**
     * @custom:section                           ** IMMUTABLES **
     */
    IERC20 public immutable _BACKING;

    /**
     * @custom:section                           ** CONSTANTS **
     */
    uint256 private constant _MIN = 1000;
    uint256 private constant _FEE_BASE_1000 = 1000;

    /**
     * @custom:section                           **  STATE VARIABLES **
     */
    uint256 public MINT_AND_REDEEM_FEE = 967; // MINT_AND_REDEEM_FEE is the total amount of Fees, Fees are calculated by taking _FEE_BASE_1000 dividing MINT_AND_REDEEM_FEE and dividing by 100 to get the percentage.
    uint256 public FEES = 35; //FEES include both team profit and liquidity incentives, FEES amount is sent to feeAddress that is a FeeSplitter contract which is going to split the FEES between team wallet/ treasury multisig and Liquidity incentives wallet/ multisig

    uint256 public totalBacking;
    address payable public feeAddress;

    bool public start;

    /**
     * @custom:section                           ** EVENTS **
     */
    event PriceAfterMint(
        uint256 indexed time,
        uint256 indexed recieved,
        uint256 indexed sent
    );
    event PriceAfterRedeem(
        uint256 indexed time,
        uint256 indexed recieved,
        uint256 indexed sent
    );
    event FeeAddressUpdated(address indexed newFeeAddress);
    event TotalBackingFixed(uint256 indexed totalBackingEmergencyFixed);
    event MintAndRedeemFeeUpdated(uint256 MINT_AND_REDEEM_FEE);
    event TeamFeeUpdated(uint256 FEES);

    /**
     * @custom:section                           ** CONSTRUCTOR **
     */
    constructor(address _feeAddress, address _backing) ERC20("pantheon TOKEN", "pTOKEN") Ownable2Step() {
        if (_feeAddress == address(0)) revert ZeroAddressNotAllowed();
        if (_backing == address(0)) revert ZeroAddressNotAllowed();

        feeAddress = payable(_feeAddress);
        _BACKING = IERC20(_backing);
    }

    /**
     * @custom:section                           ** EXTERNAL FUNCTIONS **
     */

    /**
     * @param _value: Fill the contract with the first amount of _BACKING
     * @notice need start = false
     * @notice  this function doesn't have fees, it will mint pTOKEN in a 1:1 ratio with _value
     */
    function fillContract(uint256 _value) external onlyOwner {
        require(!start);
        SafeERC20.safeTransferFrom(_BACKING, msg.sender, address(this), _value);
        _mint(msg.sender, _value);
        transfer(0x000000000000000000000000000000000000dEaD, 1000);

        totalBacking = _BACKING.balanceOf(address(this));
    }

    function setStart() external onlyOwner {    
        start = true;
    }

    /**
     * @param receiver: is the address that will receive the pTOKEN minted
     * @notice This function is used by users that want to mint pTOKEN by depositing the corrisponding amount of Backing + a dynamic fee
     * @notice The Backing / pTOKEN ratio will increase after every mint
     */
    function mint(address receiver, uint256 _amount) external nonReentrant {
        if (_amount < _MIN) revert MustTradeOverMin();

        uint256 pToken = _BACKINGtoPTOKEN(_amount);

        uint256 backingToFeeAddress = _amount / FEES;
        totalBacking += (_amount - backingToFeeAddress);

        SafeERC20.safeTransferFrom(_BACKING, msg.sender, feeAddress, backingToFeeAddress);

        _mint(receiver, (pToken * MINT_AND_REDEEM_FEE) / _FEE_BASE_1000);

        emit PriceAfterMint(block.timestamp, pToken, _amount);
    }

    /**
     * @param _amount: is the amount of pTOKEN that the user want to burn in order to redeem the corrisponding amount of Backing
     * @notice This function is used by users that want to burn their balance of pTOKEN and redeem the corrisponding amount of Backing - dynamic fees from 2% up to 5%
     * @notice The Backing / pTOKEN ratio will increase after every redeem
     */
    function redeem(uint256 _amount) external nonReentrant {
        if (_amount < _MIN) revert MustTradeOverMin();

        uint256 backing = _PTOKENtoBACKING(_amount);

        uint256 backingToFeeAddress = backing / FEES;
        uint256 backingToSender = (backing * MINT_AND_REDEEM_FEE) / _FEE_BASE_1000;
        totalBacking -= (backingToSender + backingToFeeAddress);

        _burn(msg.sender, _amount);

        SafeERC20.safeTransferFrom(_BACKING, address(this), feeAddress, backingToFeeAddress);

        SafeERC20.safeTransferFrom(_BACKING, address(this), msg.sender, backingToSender);

        emit PriceAfterRedeem(block.timestamp, _amount, backing);
    }

    /**
     * @param _address: The Address that will receive the Liquidty Incentives and Team Fee
     * @notice This function will be used to update the feeAddress
     */
    function setFeeAddress(address _address) external onlyOwner {
        _assemblyOwnerNotZero(_address);
        feeAddress = payable(_address);

        emit FeeAddressUpdated(_address);
    }

    /**
     * @param _amount: total fee amount, 1000 / _amount / 100 = total fee percentage
     * @notice this function is used by Owner to modify the total FEE %
     */
    function setMintAndRedeemFee(uint16 _amount) external onlyOwner {
        if(_amount > 980 || _amount < 950) revert MintAndRedeemFeeNotInRange();
        MINT_AND_REDEEM_FEE = _amount;
        emit MintAndRedeemFeeUpdated(_amount);
    }

    /**
     * @param _amount: 
     * @notice Team fee can't be more than 4% and less than 1% 
     * @notice Incentives for liquidity providers are included in the Team fee (FEES)
     */
    function setTeamFee(uint16 _amount) external onlyOwner {
        if(_amount > 100 || _amount < 25) revert TeamFeeNotInRange(); 
        FEES = _amount;
        emit TeamFeeUpdated(_amount);
    }

    /**
     * @notice This function is used to reflect the correct amount of totalBacking in case some unexpected bug occur
     */
    function emergencyFixTotalBacking() external onlyOwner {
        totalBacking = _BACKING.balanceOf(address(this));

        emit TotalBackingFixed(address(this).balance);
    }

    /**
     * @custom:section                           ** INTERNAL FUNCTIONS **
     */

    /**
     * @custom:section                           ** PRIVATE FUNCTIONS **
     */

    /**
     * @param _value: is the amount of backing
     * @notice This function is used inside other function to get the current backing / pTOKEN ratio
     */
    function _PTOKENtoBACKING(uint256 _value) private view returns (uint256) {
        return (_value * totalBacking) / totalSupply();
    }

    /**
     * @param _value: is the amount of pTOKEN
     * @notice This function is used inside other function to get the current pTOKEN / Backing ratio
     */
    function _BACKINGtoPTOKEN(uint256 _value) private view returns (uint256) {
        return (_value * totalSupply()) / (totalBacking);
    }

    /**
     * @param _addr: Is the address used in the functions that call the _assemblyOwnerNotZero function
     * @notice This function is used inside other function to check that the address put as parameter is different from the zero address. It saves gas compared to a if statement + a revert with a custom error
     */
    function _assemblyOwnerNotZero(address _addr) private pure {
        assembly {
            if iszero(_addr) {
                mstore(0x00, "Zero address")
                revert(0x00, 0x20)
            }
        }
    }

    /**
     * @custom:section                           **  EXTERNAL VIEW / PURE FUNCTIONS **
     */

    /**
     * @param _amount: is the amount of backing
     * @notice This function is used inside other function to get the current Mint price of pTOKEN in Backing
     */
    function getMintPrice(uint256 _amount) external view returns (uint256) {
        return
            (_amount * (totalSupply()) * (MINT_AND_REDEEM_FEE)) /
            (totalBacking) /
            (_FEE_BASE_1000);
    }

    /**
     * @param _amount: is the amount of pTOKEN
     * @notice This function is used inside other function to get the current Redeem price of pTOKEN in Backing
     */
    function getRedeemPrice(uint256 _amount) external view returns (uint256) {
        return
            ((_amount * totalBacking) * (MINT_AND_REDEEM_FEE)) /
            (totalSupply()) /
            (_FEE_BASE_1000);
    }

    /**
     * @notice This function is used inside other function to get the total amount of Backing in the contract
     */
    function getTotalBacking() external view returns (uint256) {
        return totalBacking;
    }
}