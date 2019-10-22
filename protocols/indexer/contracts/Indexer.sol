/*
  Copyright 2019 Swap Holdings Ltd.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/

pragma solidity 0.5.12;
pragma experimental ABIEncoderV2;

import "@airswap/indexer/contracts/interfaces/IIndexer.sol";
import "@airswap/indexer/contracts/interfaces/ILocatorWhitelist.sol";
import "@airswap/index/contracts/Index.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
  * @title Indexer: A Collection of Index contracts by Token Pair
  */
contract Indexer is IIndexer, Ownable {

  // Token to be used for staking (ERC-20)
  IERC20 public stakeToken;

  // Mapping of signer token to sender token to index
  mapping (address => mapping (address => Index)) public indexes;

  // Mapping of token address to boolean
  mapping (address => bool) public blacklist;

  // The whitelist contract for checking whether a peer is whitelisted
  address public locatorWhitelist;

  /**
    * @notice Contract Constructor
    *
    * @param _stakeToken address
    * @param _locatorWhitelist address
    */
  constructor(
    address _stakeToken,
    address _locatorWhitelist
  ) public {
    stakeToken = IERC20(_stakeToken);
    locatorWhitelist = _locatorWhitelist;
  }

  /**
    * @notice Create an Index (List of Locators for a Token Pair)
    * @dev Deploys a new Index contract and stores the address
    *
    * @param _signerToken address
    * @param _senderToken address
    */
  function createIndex(
    address _signerToken,
    address _senderToken
  ) external returns (address) {

    // If the Index does not exist, create it.
    if (indexes[_signerToken][_senderToken] == Index(0)) {
      // Create a new Index contract for the token pair.
      indexes[_signerToken][_senderToken] = new Index();
      emit CreateIndex(_signerToken, _senderToken);
    }

    // Return the address of the Index contract.
    return address(indexes[_signerToken][_senderToken]);
  }

  /**
    * @notice Add a Token to the Blacklist
    * @param _tokens address[]
    */
  function addToBlacklist(
    address[] calldata _tokens
  ) external onlyOwner {
    for (uint256 i = 0; i < _tokens.length; i++) {
      if (!blacklist[_tokens[i]]) {
        blacklist[_tokens[i]] = true;
        emit AddToBlacklist(_tokens[i]);
      }
    }
  }

  /**
    * @notice Remove a Token from the Blacklist
    * @param _tokens address[]
    */
  function removeFromBlacklist(
    address[] calldata _tokens
  ) external onlyOwner {
    for (uint256 i = 0; i < _tokens.length; i++) {
      if (blacklist[_tokens[i]]) {
        blacklist[_tokens[i]] = false;
        emit RemoveFromBlacklist(_tokens[i]);
      }
    }
  }

  /**
    * @notice Set an Intent to Trade
    * @dev Requires approval to transfer staking token for sender
    *
    * @param _signerToken address
    * @param _senderToken address
    * @param _amount uint256
    * @param _locator bytes32
    */
  function setIntent(
    address _signerToken,
    address _senderToken,
    uint256 _amount,
    bytes32 _locator
  ) external {

    // Ensure the locator is whitelisted, if relevant
    if (locatorWhitelist != address(0)) {
      require(ILocatorWhitelist(locatorWhitelist).has(_locator),
      "LOCATOR_NOT_WHITELISTED");
    }

    // Ensure both of the tokens are not blacklisted.
    require(!blacklist[_signerToken] && !blacklist[_senderToken],
      "PAIR_IS_BLACKLISTED");

    // Ensure the index exists.
    require(indexes[_signerToken][_senderToken] != Index(0),
      "INDEX_DOES_NOT_EXIST");

    // Only transfer for staking if amount is set.
    if (_amount > 0) {

      // Transfer the _amount for staking.
      require(stakeToken.transferFrom(msg.sender, address(this), _amount),
        "UNABLE_TO_STAKE");
    }

    emit Stake(msg.sender, _signerToken, _senderToken, _amount);

    // Set the locator on the index.
    indexes[_signerToken][_senderToken].setLocator(msg.sender, _amount, _locator);
  }

  /**
    * @notice Unset an Intent to Trade
    * @dev Users are allowed unstake from blacklisted indexes
    *
    * @param _signerToken address
    * @param _senderToken address
    */
  function unsetIntent(
    address _signerToken,
    address _senderToken
  ) external {

    // Ensure the index exists.
    require(indexes[_signerToken][_senderToken] != Index(0),
      "INDEX_DOES_NOT_EXIST");

    // Get the locator for the sender.
    Index.Locator memory locator = indexes[_signerToken][_senderToken].getLocator(msg.sender);

    // Ensure the locator exists.
    require(locator.user == msg.sender,
      "LOCATOR_DOES_NOT_EXIST");

    // Unset the locator on the index.
    //No need to require() because a check is done above that reverts if there are no locators
    indexes[_signerToken][_senderToken].unsetLocator(msg.sender);

    if (locator.score > 0) {
      // Return the staked tokens.
      // Need to revert when false is returned
      require(stakeToken.transfer(msg.sender, locator.score));
    }

    emit Unstake(msg.sender, _signerToken, _senderToken, locator.score);
  }

  /**
    * @notice Get the locators of those trading a token pair
    * @dev Users are allowed unstake from blacklisted indexes
    *
    * @param _signerToken address
    * @param _senderToken address
    * @param _startAddress address The address to start from in the list of intents
    * @param _count uint256 The total number of intents to return
    * @return locators address[]
    */
  function getIntents(
    address _signerToken,
    address _senderToken,
    address _startAddress,
    uint256 _count
  ) external view returns (
    bytes32[] memory locators
  ) {

    // Ensure neither token is blacklisted.
    if (!blacklist[_signerToken] && !blacklist[_senderToken]) {

      // Ensure the index exists.
      if (indexes[_signerToken][_senderToken] != Index(0)) {

        // Return an array of locators for the index.
        return indexes[_signerToken][_senderToken].fetchLocators(_startAddress, _count);

      }
    }
    return new bytes32[](0);
  }
}
