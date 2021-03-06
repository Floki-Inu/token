import hre from "hardhat";

import {
  FLOKI,
  FLOKI__factory,
  ExponentialTaxHandler,
  ExponentialTaxHandler__factory,
  TreasuryHandlerAlpha,
  TreasuryHandlerAlpha__factory,
  ZeroTaxHandler,
  ZeroTaxHandler__factory,
  ZeroTreasuryHandler,
  ZeroTreasuryHandler__factory,
} from "../types";

async function main(): Promise<void> {
  const name = "NHAM-Test-05";
  const routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

  const signers = await hre.ethers.getSigners();
  const signer = signers[0];

  const Floki: FLOKI__factory = await hre.ethers.getContractFactory("FLOKI");
  const ExponentialTaxHandler: ExponentialTaxHandler__factory = await hre.ethers.getContractFactory(
    "ExponentialTaxHandler",
  );
  const TreasuryHandlerAlpha: TreasuryHandlerAlpha__factory = await hre.ethers.getContractFactory(
    "TreasuryHandlerAlpha",
  );
  const ZeroTaxHandler: ZeroTaxHandler__factory = await hre.ethers.getContractFactory("ZeroTaxHandler");
  const ZeroTreasuryHandler: ZeroTreasuryHandler__factory = await hre.ethers.getContractFactory("ZeroTreasuryHandler");

  const zeroTaxHandler: ZeroTaxHandler = await ZeroTaxHandler.deploy();
  const zeroTreasuryHandler: ZeroTreasuryHandler = await ZeroTreasuryHandler.deploy();

  const floki: FLOKI = await Floki.deploy(name, name, zeroTaxHandler.address, zeroTreasuryHandler.address);
  const exponentialTaxHandler: ExponentialTaxHandler = await ExponentialTaxHandler.deploy(floki.address);
  const treasuryHandlerAlpha: TreasuryHandlerAlpha = await TreasuryHandlerAlpha.deploy(
    signer.address,
    floki.address,
    routerAddress,
    2000,
    300,
  );

  await floki.setTaxHandler(exponentialTaxHandler.address);
  await floki.setTreasuryHandler(treasuryHandlerAlpha.address);
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
