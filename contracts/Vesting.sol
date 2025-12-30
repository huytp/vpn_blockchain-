// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Vesting Contract
 * @dev Manages vesting for Core Team (4 years, 12 month cliff) and Seed Investors (2-3 years)
 */
contract Vesting is Ownable {
    IERC20 public token;

    struct VestingSchedule {
        address beneficiary;
        uint256 totalAmount;
        uint256 released;
        uint256 startTime;
        uint256 duration; // Total vesting duration in seconds
        uint256 cliff; // Cliff period in seconds
        bool revoked;
    }

    mapping(address => VestingSchedule) public vestingSchedules;
    address[] public beneficiaries;

    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration,
        uint256 cliff
    );
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary);

    constructor(address _tokenAddress) Ownable(msg.sender) {
        token = IERC20(_tokenAddress);
    }

    /**
     * @dev Create vesting schedule
     * @param beneficiary Address to receive tokens
     * @param totalAmount Total amount to vest
     * @param startTime Vesting start time (unix timestamp)
     * @param duration Vesting duration in seconds
     * @param cliff Cliff period in seconds (0 = no cliff)
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration,
        uint256 cliff
    ) external onlyOwner {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(totalAmount > 0, "Amount must be > 0");
        require(duration > 0, "Duration must be > 0");
        require(
            vestingSchedules[beneficiary].totalAmount == 0,
            "Vesting schedule already exists"
        );

        vestingSchedules[beneficiary] = VestingSchedule({
            beneficiary: beneficiary,
            totalAmount: totalAmount,
            released: 0,
            startTime: startTime,
            duration: duration,
            cliff: cliff,
            revoked: false
        });

        beneficiaries.push(beneficiary);

        emit VestingScheduleCreated(
            beneficiary,
            totalAmount,
            startTime,
            duration,
            cliff
        );
    }

    /**
     * @dev Release vested tokens
     */
    function release(address beneficiary) external {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(!schedule.revoked, "Vesting revoked");

        uint256 releasable = getReleasableAmount(beneficiary);
        require(releasable > 0, "No tokens to release");

        schedule.released += releasable;
        require(
            token.transfer(beneficiary, releasable),
            "Token transfer failed"
        );

        emit TokensReleased(beneficiary, releasable);
    }

    /**
     * @dev Calculate releasable amount
     */
    function getReleasableAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];

        if (schedule.totalAmount == 0 || schedule.revoked) {
            return 0;
        }

        uint256 currentTime = block.timestamp;

        // Check if cliff period has passed
        if (currentTime < schedule.startTime + schedule.cliff) {
            return 0;
        }

        // Calculate vested amount
        uint256 elapsed = currentTime - schedule.startTime;
        uint256 vested;

        if (elapsed >= schedule.duration) {
            vested = schedule.totalAmount;
        } else {
            vested = (schedule.totalAmount * elapsed) / schedule.duration;
        }

        return vested - schedule.released;
    }

    /**
     * @dev Get vested amount (released + releasable)
     */
    function getVestedAmount(address beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];

        if (schedule.totalAmount == 0 || schedule.revoked) {
            return schedule.released;
        }

        uint256 currentTime = block.timestamp;
        uint256 elapsed = currentTime - schedule.startTime;

        if (elapsed < schedule.cliff) {
            return 0;
        }

        if (elapsed >= schedule.duration) {
            return schedule.totalAmount;
        }

        return (schedule.totalAmount * elapsed) / schedule.duration;
    }

    /**
     * @dev Revoke vesting schedule (only for revoked cases)
     */
    function revoke(address beneficiary) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(!schedule.revoked, "Already revoked");

        schedule.revoked = true;
        emit VestingRevoked(beneficiary);
    }

    /**
     * @dev Batch create vesting schedules
     */
    function batchCreateVestingSchedules(
        address[] calldata _beneficiaries,
        uint256[] calldata _amounts,
        uint256[] calldata _startTimes,
        uint256[] calldata _durations,
        uint256[] calldata _cliffs
    ) external onlyOwner {
        require(
            _beneficiaries.length == _amounts.length &&
            _beneficiaries.length == _startTimes.length &&
            _beneficiaries.length == _durations.length &&
            _beneficiaries.length == _cliffs.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];
            uint256 totalAmount = _amounts[i];
            uint256 startTime = _startTimes[i];
            uint256 duration = _durations[i];
            uint256 cliff = _cliffs[i];

            require(beneficiary != address(0), "Invalid beneficiary");
            require(totalAmount > 0, "Amount must be > 0");
            require(duration > 0, "Duration must be > 0");
            require(
                vestingSchedules[beneficiary].totalAmount == 0,
                "Vesting schedule already exists"
            );

            vestingSchedules[beneficiary] = VestingSchedule({
                beneficiary: beneficiary,
                totalAmount: totalAmount,
                released: 0,
                startTime: startTime,
                duration: duration,
                cliff: cliff,
                revoked: false
            });

            beneficiaries.push(beneficiary);

            emit VestingScheduleCreated(
                beneficiary,
                totalAmount,
                startTime,
                duration,
                cliff
            );
        }
    }
}

