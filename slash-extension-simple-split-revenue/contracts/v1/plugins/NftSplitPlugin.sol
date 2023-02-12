//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/ISlashSplitPlugin.sol";
import "./interfaces/ISlashSplitFactory.sol";
import "../libs/UniversalERC20.sol";

/**
 * @notice NFT Split plugin contract
 */
contract NftSplitPlugin is OwnableUpgradeable {
    using UniversalERC20 for IERC20Upgradeable;

    struct NftInfo {
        uint256 chainId;
        uint256 tokenId;
        uint16 splitRate;
        address nftAddress;
        address receipt;
    }

    uint8 public constant MAX_SPLITS = 10;
    uint16 public constant RATE_PRECISION = 10000;

    address private _operator;
    address private _factory;

    // NFT info array for the split
    NftInfo[] private _splitNfts;

    event PaymentSplitted(
        address indexed account,
        address indexed token,
        uint256 amount,
        uint16 rate
    );

    /**
     * @notice Initialize plugin
     */
    function initialize(address operator_) public initializer {
        __Ownable_init();

        _operator = operator_;
        _factory = _msgSender();
    }

    /**
     * @notice Update NFT info list
     * @dev Only operator can update NFT info list
     */
    function updateNftInfoList(
        uint256[] memory chainIds_,
        uint256[] memory tokenIds_,
        address[] memory nftAddresses_,
        uint16[] memory splitRates_
    ) external {
        require(_msgSender() == _operator, "Unpermitted");
        require(chainIds_.length == tokenIds_.length, "Length different");
        require(chainIds_.length == nftAddresses_.length, "Length different");
        require(chainIds_.length == splitRates_.length, "Length different");

        uint256 splitCount = nftAddresses_.length;
        require(
            splitCount > 0 && splitCount <= MAX_SPLITS,
            "Invalid split count"
        );

        delete _splitNfts; // Clear split wallets
        uint32 totalRates;
        for (uint256 i = 0; i < splitCount; i++) {
            require(nftAddresses_[i] != address(0), "Invalid nft address");
            _splitNfts.push(
                NftInfo({
                    chainId: chainIds_[i],
                    tokenId: tokenIds_[i],
                    nftAddress: nftAddresses_[i],
                    splitRate: splitRates_[i],
                    receipt: address(0)
                })
            );
            totalRates += splitRates_[i];
        }
        // Sum of rates must be 100% (RATE_PRECISION)
        require(totalRates == RATE_PRECISION, "Invalid split rates");
    }

    /**
     * @notice Update receipt list
     * @dev Only batch contract can do this
     */
    function updateReceiptList(address[] memory receipts_) external {
        require(_msgSender() == viewBachContract(), "Unpermitted");
        require(_splitNfts.length == receipts_.length, "Length different");

        uint256 splitCount = receipts_.length;

        for (uint256 i = 0; i < splitCount; i++) {
            require(receipts_[i] != address(0), "Invalid receipt");
            _splitNfts[i].receipt = receipts_[i];
        }
    }

    /**
     * @notice Update plugin operator
     * @dev Slash owner operator can run this function
     */
    function updateOperator(address operator_) external {
        require(
            _msgSender() == owner() || _msgSender() == _operator,
            "Unpermitted"
        );

        _operator = operator_;
    }

    function viewOperator() external view returns (address) {
        return _operator;
    }

    function viewBachContract() public view returns (address) {
        return ISlashSplitFactory(_factory).viewBatchContract();
    }

    /**
     * @notice View split wallets and rates
     */
    function viewNftInfos() external view returns (NftInfo[] memory) {
        require(
            _msgSender() == _operator || _msgSender() == viewBachContract(),
            "Unpermitted"
        );
        return _splitNfts;
    }

    /**
     * @dev receive payment from SlashCore Contract
     * @param receiveToken_: payment receive token
     * @param amount_: payment receive amount
     */
    function receivePayment(
        address receiveToken_,
        uint256 amount_,
        string memory, /* paymentId: PaymentId generated by the merchant when creating the payment URL */
        string memory /* optional: Optional parameter passed at the payment */
    ) external payable {
        IERC20Upgradeable(receiveToken_).universalTransferFromSenderToThis(
            amount_
        );

        uint256 splitCount = _splitNfts.length;
        uint32 totalRates;
        for (uint256 i = 0; i < splitCount; i++) {
            uint256 splittedAmount = (amount_ * _splitNfts[i].splitRate) /
                RATE_PRECISION;
            IERC20Upgradeable(receiveToken_).universalTransfer(
                _splitNfts[i].receipt,
                splittedAmount
            );
            totalRates += _splitNfts[i].splitRate;

            emit PaymentSplitted(
                _splitNfts[i].receipt,
                receiveToken_,
                splittedAmount,
                _splitNfts[i].splitRate
            );
        }
        // Sum of rates must be 100% (RATE_PRECISION)
        require(totalRates == RATE_PRECISION, "Invalid split configuration");
    }

    /**
     * @dev Check if the contract is Slash Plugin
     *
     * Requirement
     * - Implement this function in the contract
     * - Return true
     */
    function supportSlashExtensionInterface() external pure returns (bool) {
        return true;
    }

    // to recieve ETH
    receive() external payable {}

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param token_: the address of the token to withdraw
     * @param amount_: the number of tokens to withdraw
     * @dev This function is only callable by Slash owner.
     */
    function recoverWrongTokens(address token_, uint256 amount_)
        external
        onlyOwner
    {
        IERC20Upgradeable(token_).universalTransfer(_msgSender(), amount_);
    }
}
