// SPDX-License-Identifier: PropietarioUnico
pragma solidity ^0.8.28;

contract Governance {
    enum ProposalStatus { Pendiente, Aprobada, Rechazada, Ejecutada }

    // 1: tasaInteresInterna
    // 2: tasaInteresExterna
    // 3: porcentajeFondoExterno
    struct Proposal {
        uint256 id;
        uint256 coopId;        
        address token;         
        string descripcion;
        uint256 fechaCreacion;
        uint256 fechaVotacion; 
        ProposalStatus status;
        uint256 votosAFavor;
        uint256 votosEnContra;
        mapping(address => bool) haVotado;  
        uint256 nuevoValor;    
        uint8 tipoPropuesta;   
    }

    uint256 public nextProposalId;
    mapping(uint256 => mapping(uint256 => Proposal)) public propuestas;

    event ProposalCreada(uint256 indexed coopId, uint256 proposalId, string descripcion);
    event VoteCast(uint256 indexed coopId, uint256 proposalId, address votante, bool aFavor);
    event ProposalEjecutada(uint256 indexed coopId, uint256 proposalId, bool resultado);

    // La dirección del contrato DAO, para poder llamarlo y actualizar parámetros
    address public cajaRuralDAO;

    constructor(address _dao) {
        cajaRuralDAO = _dao;
    }

    function crearPropuesta(
        uint256 _coopId,
        address _token,
        string calldata _descripcion,
        uint256 _fechaVotacion,
        uint256 _nuevoValor,
        uint8 _tipoPropuesta
    ) external {
        uint256 proposalId = nextProposalId++;
        Proposal storage prop = propuestas[_coopId][proposalId];

        prop.id = proposalId;
        prop.coopId = _coopId;
        prop.token = _token;
        prop.descripcion = _descripcion;
        prop.fechaCreacion = block.timestamp;
        prop.fechaVotacion = _fechaVotacion;
        prop.status = ProposalStatus.Pendiente;
        prop.nuevoValor = _nuevoValor;
        prop.tipoPropuesta = _tipoPropuesta;

        emit ProposalCreada(_coopId, proposalId, _descripcion);
    }

    function votarPropuesta(uint256 _coopId, uint256 _proposalId, bool _aFavor) external {
        Proposal storage prop = propuestas[_coopId][_proposalId];
        require(block.timestamp <= prop.fechaVotacion, "Votacion finalizada");
        require(!prop.haVotado[msg.sender], "Ya votaste");

        prop.haVotado[msg.sender] = true;
        if (_aFavor) {
            prop.votosAFavor++;
        } else {
            prop.votosEnContra++;
        }

        emit VoteCast(_coopId, _proposalId, msg.sender, _aFavor);
    }

    function ejecutarPropuesta(uint256 _coopId, uint256 _proposalId) external {
        Proposal storage prop = propuestas[_coopId][_proposalId];
        require(block.timestamp > prop.fechaVotacion, "Votacion en curso");
        require(prop.status == ProposalStatus.Pendiente, "Propuesta ya procesada");

        bool aprobado = (prop.votosAFavor > prop.votosEnContra);

        if (aprobado) {
            prop.status = ProposalStatus.Aprobada;
            // Llamar a CajaRuralDAO para actualizar el parámetro según tipoPropuesta
            if (prop.tipoPropuesta == 1) {
                // tasaInteresInterna
                ICajaRuralDAO(cajaRuralDAO).actualizarParametroToken(_coopId, prop.token, "tasaInteresInterna", prop.nuevoValor);
            } else if (prop.tipoPropuesta == 2) {
                // tasaInteresExterna
                ICajaRuralDAO(cajaRuralDAO).actualizarParametroToken(_coopId, prop.token, "tasaInteresExterna", prop.nuevoValor);
            } else if (prop.tipoPropuesta == 3) {
                // porcentajeFondoExterno
                ICajaRuralDAO(cajaRuralDAO).actualizarParametroToken(_coopId, prop.token, "porcentajeFondoExterno", prop.nuevoValor);
            } else {
                // Otros tipos de propuestas se pueden manejar aquí
                revert("Tipo de propuesta no implementado");
            }

            emit ProposalEjecutada(_coopId, _proposalId, true);
        } else {
            prop.status = ProposalStatus.Rechazada;
            emit ProposalEjecutada(_coopId, _proposalId, false);
        }
    }
}

/**
 * @notice Interfaz para llamar a la función de actualización de parámetros del DAO.
 */
interface ICajaRuralDAO {
    function actualizarParametroToken(
        uint256 _coopId,
        address _token,
        string calldata _parametro,
        uint256 _nuevoValor
    ) external;
}
