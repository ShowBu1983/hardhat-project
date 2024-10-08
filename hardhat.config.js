require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version:"0.8.24",
    settings:{
      optimizer: {
        enabled: true,
        runs: 200,
      }
    },
    evmVersion: "istanbul"
  },
  networks:{
    hardhat:{
      ensAddress: null // This disables ENS for local network
    },
    sepolia:{
      // url:"https://eth-sepolia.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY, accounts: [`0x${process.env.PRIVATE_KEY}`],
      url:"https://sepolia.infura.io/v3/"+process.env.INFURA_ID, accounts:[`0x${process.env.PRIVATE_KEY}`],
      ensAddress: null // This disables ENS for Sepolia
    }
  }
};
