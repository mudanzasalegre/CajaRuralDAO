// SPDX-License-Identifier: PropietarioUnico
pragma solidity ^0.8.28;

contract AccessControl {
    enum Role { NONE, ADMIN, TESORERO, SECRETARIO, GUARDIA, MIEMBRO }

    mapping(address => Role) public roles;
    address public owner;

    constructor() {
        owner = msg.sender;
        roles[msg.sender] = Role.ADMIN;
    }

    modifier onlyAdmin() {
        require(roles[msg.sender] == Role.ADMIN, "Solo admin");
        _;
    }

    modifier onlyTesorero() {
        require(roles[msg.sender] == Role.TESORERO, "Solo tesorero");
        _;
    }

    modifier onlySecretario() {
        require(roles[msg.sender] == Role.SECRETARIO, "Solo secretario");
        _;
    }

    modifier onlyMiembro() {
        require(
            roles[msg.sender] == Role.MIEMBRO ||
            roles[msg.sender] == Role.TESORERO ||
            roles[msg.sender] == Role.SECRETARIO ||
            roles[msg.sender] == Role.GUARDIA,
            "No es miembro"
        );
        _;
    }

    function asignarRol(address _cuenta, Role _rol) external onlyAdmin {
        roles[_cuenta] = _rol;
    }

    function revocarRol(address _cuenta) external onlyAdmin {
        roles[_cuenta] = Role.NONE;
    }
}
