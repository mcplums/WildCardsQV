const WildCardsQV = artifacts.require("../contracts/WildCardsQV.sol");

var loyaltyTokenAddress = "0x000000000000000000000000000000000000dEaD";
var wildCardTokenAddress = "0x000000000000000000000000000000000000dEaD";

module.exports = function (deployer) {
  deployer.deploy(WildCardsQV, loyaltyTokenAddress,wildCardTokenAddress);
};
