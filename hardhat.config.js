require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: "./contracts",
    artifacts: "./artifacts",
    cache: "./cache",
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    polygonAmoy: {
      url: (() => {
        let url = process.env.TATUM_POLYGON_AMOY_URL || "https://polygon-amoy.gateway.tatum.io";
        // Add API key to URL if provided (Tatum gateway format)
        if (process.env.TATUM_API_KEY && !url.includes(process.env.TATUM_API_KEY)) {
          // Some gateways use ?apikey= or /apikey/ format
          const separator = url.includes('?') ? '&' : '?';
          url = `${url}${separator}apikey=${process.env.TATUM_API_KEY}`;
        }
        return url;
      })(),
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      timeout: 60000,
      gas: "auto",
      gasPrice: "auto",
    },
  },
};
