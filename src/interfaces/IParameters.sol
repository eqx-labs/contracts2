// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface ISystemParameters {
    function getEpochDuration() external view returns (uint48);
    function getSlashingWindow() external view returns (uint48);
    function isUnsafeRegistrationAllowed() external view returns (bool);
    function getMaxChallengeDuration() external view returns (uint48);
    function getChallengeBond() external view returns (uint256);
    function getBlockhashEvmLookback() external view returns (uint256);
    function getJustificationDelay() external view returns (uint256);
    function getEip4788Window() external view returns (uint256);
    function getSlotTime() external view returns (uint256);
    function getEth2GenesisTimestamp() external view returns (uint256);
    function getBeaconRootsContract() external view returns (address);
    function getMinimumOperatorStake() external view returns (uint256);
}
