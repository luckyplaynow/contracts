/**
 *Submitted for verification at polygonscan.com on 2022-02-19
 */

// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LuckyPlayPOAP is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    mapping(uint256 => uint8) public itemMap;
    mapping(uint8 => uint8) public itemCount;
    mapping(uint8 => string) public categoryUrl;

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    constructor() ERC721("Lucky POAP", "Lucky POAP") {}

    function setUrls(string[] memory urls) external onlyOwner {
        for (uint8 i = 0; i < urls.length; i++) {
            categoryUrl[i + 1] = urls[i];
        }
    }

    function mintPOAP(address[] memory addresses, uint8 category)
        external
        onlyOwner
    {
        require(itemCount[category] <= 100, "Item exceeded");
        for (uint8 i = 0; i < addresses.length; i++) {
            if (itemCount[category] < 100) {
                uint256 newItemId = _tokenIds.current();
                _mint(addresses[i], newItemId);
                _tokenIds.increment();
                itemMap[newItemId] = category;
                itemCount[category] += 1;
            }
        }
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return categoryUrl[itemMap[tokenId]];
    }
}
