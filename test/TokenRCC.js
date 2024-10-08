const { expect } = require("chai"); 
const hardhat = require("hardhat"); 
// const web3 = require("@nomic");

describe("TokenRCC", function () { 
    let tokenRCCContract; 
    before(async () => { 
        // ⽣成合约实例并且复⽤ 
        tokenRCCContract = await hardhat.ethers.deployContract("TokenRCC", [1000000]); 
    }); 

    it("mint 1M worth of tokens", async () => {
        let [owner] = await hardhat.ethers.getSigners();
        console.log("address : ", owner.address);
        const amount = ethers.parseUnits("1000000", 18);
        // let balance = await tokenRCCContract.balanceOf(signers[0].address);
        // balance = hardhat.web3.utils.fromWei(balance);
        // console.log("balance:",balance);
        // assert.equal(balance, 1000000, "Initial supply of token is 1000000");
        expect(await tokenRCCContract.balanceOf(owner.address)).to.equal(amount);
      });
});