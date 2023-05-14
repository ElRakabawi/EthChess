// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Play {
    
    address public owner;
    address public stationLabs;

    uint[5] public BetsPreset = [
        1 ether,
        5 ether,
        20 ether,
        40 ether,
        100 ether
    ];

    struct player {
        bytes32 Alias;
        uint score;
    }

    mapping(address => bool) public betPlaced;
    mapping(address => uint[5]) public petPresetValue;
    mapping(address => player) public playerAliases;

    constructor(
        address _deployer,
        address _stationLabs

    ){
        owner = _deployer;
        stationLabs = _stationLabs;

    }

    modifier onlyGameMaster {
        require(msg.sender == owner);
        _;
    }

    function changeBetsPresets(uint _index, uint _value) public onlyGameMaster {
        BetsPreset[_index] = _value;
    }

}