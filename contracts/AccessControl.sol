// SPDX-License-Identifier: PropietarioUnico
pragma solidity ^0.8.28;

/**
 * @title AccessControl
 * @notice Control básico de roles para todo el sistema (DAO, LoanManager, Governance, etc.).
 */
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

    /**
     * @notice Asigna un rol a una cuenta (sólo ADMIN).
     */
    function asignarRol(address _cuenta, Role _rol) external onlyAdmin {
        roles[_cuenta] = _rol;
    }

    /**
     * @notice Revoca el rol de una cuenta (sólo ADMIN).
     */
    function revocarRol(address _cuenta) external onlyAdmin {
        roles[_cuenta] = Role.NONE;
    }
}
