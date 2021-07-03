const KUSD = artifacts.require("KUSD");

module.exports = function (deployer) {
  deployer.deploy(KUSD);
};
