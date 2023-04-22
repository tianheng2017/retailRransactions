const Shop = artifacts.require("Shop")

module.exports = async function(deployer, network, accounts) {
    // 部署合约
    await deployer.deploy(Shop, { from: accounts[0] });
}
