import hre from "hardhat";

import {
  FLOKI,
  FLOKI__factory,
  StaticTaxHandler,
  StaticTaxHandler__factory,
  TreasuryHandlerAlpha,
  TreasuryHandlerAlpha__factory,
  ZeroTaxHandler,
  ZeroTaxHandler__factory,
} from "../types";

async function main(): Promise<void> {
  const signers = await hre.ethers.getSigners();
  const signer = signers[0];

  const Floki: FLOKI__factory = await hre.ethers.getContractFactory("FLOKI");
  const StaticTaxHandler: StaticTaxHandler__factory = await hre.ethers.getContractFactory("StaticTaxHandler");
  const TreasuryHandlerAlpha: TreasuryHandlerAlpha__factory = await hre.ethers.getContractFactory(
    "TreasuryHandlerAlpha",
  );
  const ZeroTaxHandler: ZeroTaxHandler__factory = await hre.ethers.getContractFactory("ZeroTaxHandler");

  const zeroTaxHandler: ZeroTaxHandler = await ZeroTaxHandler.deploy();
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
