// SPDX-License-Identifier: PropietarioUnico
pragma solidity ^0.8.28;

import "./AccessControl.sol";

interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
}

/**
 * @title CajaRuralDAO
 * @notice Contrato base para la gestión de cooperativas de ahorro y préstamo (Caja Rural DAO).
 */
contract CajaRuralDAO is AccessControl {
    address public governanceAddress; //
    /* ========== ESTRUCTURAS ========== */

    struct OperacionToken {
        bool enabled;
        uint256 tasaInteresInterna; // Tasa de interés para préstamos internos (porcentaje anual)
        uint256 tasaInteresExterna; // Tasa de interés para préstamos externos (porcentaje anual)
        uint256 porcentajeFondoExterno;
        uint256 fondoComun;
        uint256 fondoObraSocial;
        uint256 depositosTotales;
    }

    struct Member {
        address cuenta;
        mapping(address => uint256) totalDepositos; // token => monto depositado
        mapping(address => uint256) retirado; // token => monto ya retirado
        bool activo;
    }

    struct Cooperative {
        uint256 id;
        string nombre;
        address creador;
        address tesorero;
        address secretario;
        address[2] guardas;
        address[] listaMiembros;
        mapping(address => Member) miembros;
        mapping(address => OperacionToken) tokens;
        address[] tokenList;
        uint256 porcentajeObraSocial; // % de cada depósito que va a fondo social
    }

    /* ========== VARIABLES DE ESTADO ========== */

    uint256 public nextCoopId; // ID incremental para las cooperativas
    mapping(uint256 => Cooperative) internal cooperativas;

    /* ========== EVENTOS ========== */

    event CooperativeCreada(
        uint256 indexed coopId,
        string nombre,
        address creador
    );
    event MiembroSolicitado(uint256 indexed coopId, address miembro);
    event MiembroAprobado(uint256 indexed coopId, address miembro);
    event TokenHabilitado(
        uint256 indexed coopId,
        address token,
        uint256 tasaInterna,
        uint256 tasaExterna,
        uint256 fondoExterno
    );
    event DepositoRealizado(
        uint256 indexed coopId,
        address miembro,
        address token,
        uint256 monto
    );
    event RetiroRealizado(
        uint256 indexed coopId,
        address miembro,
        address token,
        uint256 monto
    );
    event ParametroActualizado(
        uint256 indexed coopId,
        address token,
        string parametro,
        uint256 nuevoValor
    );

    /* ========== MODIFICADORES ========== */

    modifier cooperativeExists(uint256 _coopId) {
        require(_coopId < nextCoopId, "Cooperativa inexistente");
        _;
    }

    /* ========== FUNCIONES PRINCIPALES ========== */
    /**
     * @notice Asigna la dirección del contrato de gobernanza.
     */
    function setGovernanceAddress(address _gov) external onlyAdmin {
        governanceAddress = _gov;
    }

    /**
     * @notice Crea una nueva cooperativa.
     */
    function crearCooperativa(
        string calldata _nombre,
        uint256 _porcentajeObraSocial,
        address _tesorero,
        address _secretario,
        address[2] calldata _guardas
    ) external returns (uint256 coopId) {
        require(
            _porcentajeObraSocial <= 100,
            "Porcentaje de obra social invalido"
        );
        coopId = nextCoopId++;
        Cooperative storage coop = cooperativas[coopId];

        coop.id = coopId;
        coop.nombre = _nombre;
        coop.creador = msg.sender;
        coop.porcentajeObraSocial = _porcentajeObraSocial;
        coop.tesorero = _tesorero;
        coop.secretario = _secretario;
        coop.guardas = _guardas;

        // El creador se registra como miembro activo
        coop.listaMiembros.push(msg.sender);
        Member storage miembro = coop.miembros[msg.sender];
        miembro.cuenta = msg.sender;
        miembro.activo = true;

        emit CooperativeCreada(coopId, _nombre, msg.sender);
    }

    /**
     * @notice Permite que un usuario solicite ingreso a una cooperativa.
     */
    function solicitarIngreso(uint256 _coopId)
        external
        cooperativeExists(_coopId)
    {
        Cooperative storage coop = cooperativas[_coopId];
        require(
            coop.miembros[msg.sender].cuenta == address(0),
            "Ya es miembro o solicitado"
        );

        coop.listaMiembros.push(msg.sender);
        Member storage miembro = coop.miembros[msg.sender];
        miembro.cuenta = msg.sender;
        miembro.activo = false;
        emit MiembroSolicitado(_coopId, msg.sender);
    }

    /**
     * @notice El tesorero aprueba la solicitud de ingreso de un miembro.
     */
    function aprobarIngreso(uint256 _coopId, address _miembro)
        external
        cooperativeExists(_coopId)
    {
        Cooperative storage coop = cooperativas[_coopId];
        require(msg.sender == coop.tesorero, "Solo el tesorero puede aprobar");
        Member storage m = coop.miembros[_miembro];
        require(!m.activo, "Miembro ya aprobado");
        m.activo = true;
        emit MiembroAprobado(_coopId, _miembro);
    }

    /* ========== GESTIÓN DE TOKENS ========== */

    /**
     * @notice Habilita un token para operar en la cooperativa.
     */
    function habilitarToken(
        uint256 _coopId,
        address _token,
        uint256 _tasaInteresInterna,
        uint256 _tasaInteresExterna,
        uint256 _porcentajeFondoExterno
    ) external cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        require(msg.sender == coop.tesorero, "Solo tesorero");

        OperacionToken storage op = coop.tokens[_token];
        op.enabled = true;
        op.tasaInteresInterna = _tasaInteresInterna;
        op.tasaInteresExterna = _tasaInteresExterna;
        op.porcentajeFondoExterno = _porcentajeFondoExterno;
        op.fondoComun = 0;
        op.fondoObraSocial = 0;
        op.depositosTotales = 0;

        bool exists = false;
        for (uint256 i = 0; i < coop.tokenList.length; i++) {
            if (coop.tokenList[i] == _token) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            coop.tokenList.push(_token);
        }

        emit TokenHabilitado(
            _coopId,
            _token,
            _tasaInteresInterna,
            _tasaInteresExterna,
            _porcentajeFondoExterno
        );
    }

    /**
     * @notice Permite a la gobernanza (o al tesorero) actualizar parámetros del token.
     * Ejemplo: cambiar la tasa interna, externa, o el porcentaje de fondo externo.
     */
    function actualizarParametroToken(
        uint256 _coopId,
        address _token,
        string calldata _parametro,
        uint256 _nuevoValor
    ) external cooperativeExists(_coopId) {
        require(msg.sender == governanceAddress, "Solo gobernanza autorizada");

        OperacionToken storage op = cooperativas[_coopId].tokens[_token];
        require(op.enabled, "Token no habilitado");

        bytes32 paramHash = keccak256(abi.encodePacked(_parametro));

        if (paramHash == keccak256("tasaInteresInterna")) {
            op.tasaInteresInterna = _nuevoValor;
        } else if (paramHash == keccak256("tasaInteresExterna")) {
            op.tasaInteresExterna = _nuevoValor;
        } else if (paramHash == keccak256("porcentajeFondoExterno")) {
            op.porcentajeFondoExterno = _nuevoValor;
        } else {
            revert("Parametro no valido");
        }

        emit ParametroActualizado(_coopId, _token, _parametro, _nuevoValor);
    }

    /* ========== DEPÓSITO Y RETIRO ========== */

    function depositar(
        uint256 _coopId,
        address _token,
        uint256 _monto
    ) external payable onlyMiembro cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        OperacionToken storage op = coop.tokens[_token];
        require(op.enabled, "Token no habilitado");

        Member storage m = coop.miembros[msg.sender];
        require(m.activo, "Miembro no activo");

        if (_token == address(0)) {
            // ETH
            require(msg.value == _monto && _monto > 0, "ETH invalido");
        } else {
            // ERC20
            IERC20 tokenContract = IERC20(_token);
            require(
                tokenContract.transferFrom(msg.sender, address(this), _monto),
                "Transferencia fallida"
            );
        }

        m.totalDepositos[_token] += _monto;
        op.depositosTotales += _monto;

        uint256 montoObra = (_monto * coop.porcentajeObraSocial) / 100;
        uint256 montoComun = _monto - montoObra;
        op.fondoObraSocial += montoObra;
        op.fondoComun += montoComun;

        emit DepositoRealizado(_coopId, msg.sender, _token, _monto);
    }

    function retirarFondos(
        uint256 _coopId,
        address _token,
        uint256 _monto
    ) external onlyMiembro cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        OperacionToken storage op = coop.tokens[_token];
        require(op.enabled, "Token no habilitado");

        Member storage m = coop.miembros[msg.sender];
        require(m.activo, "No es miembro activo");

        uint256 saldoDisponible = m.totalDepositos[_token] - m.retirado[_token];
        require(_monto <= saldoDisponible, "Excede lo aportado");
        require(op.fondoComun >= _monto, "Fondo comun insuficiente");

        m.retirado[_token] += _monto;
        op.fondoComun -= _monto;

        if (_token == address(0)) {
            payable(msg.sender).transfer(_monto);
        } else {
            IERC20 tokenContract = IERC20(_token);
            require(
                tokenContract.transfer(msg.sender, _monto),
                "Transferencia fail"
            );
        }

        emit RetiroRealizado(_coopId, msg.sender, _token, _monto);
    }

    /* ========== CONSULTAS ========== */

    function getFondos(uint256 _coopId, address _token)
        external
        view
        cooperativeExists(_coopId)
        returns (uint256 fondoComun, uint256 fondoObraSocial)
    {
        OperacionToken storage op = cooperativas[_coopId].tokens[_token];
        return (op.fondoComun, op.fondoObraSocial);
    }

    function getTokenData(uint256 _coopId, address _token)
        external
        view
        cooperativeExists(_coopId)
        returns (
            bool enabled,
            uint256 tasaInteresInterna,
            uint256 tasaInteresExterna,
            uint256 porcentajeFondoExterno,
            uint256 fondoComun,
            uint256 fondoObraSocial,
            uint256 depositosTotales
        )
    {
        OperacionToken storage op = cooperativas[_coopId].tokens[_token];
        return (
            op.enabled,
            op.tasaInteresInterna,
            op.tasaInteresExterna,
            op.porcentajeFondoExterno,
            op.fondoComun,
            op.fondoObraSocial,
            op.depositosTotales
        );
    }

    function esMiembroActivo(uint256 _coopId, address _cuenta)
        external
        view
        cooperativeExists(_coopId)
        returns (bool)
    {
        return cooperativas[_coopId].miembros[_cuenta].activo;
    }

    /**
     * @notice Devuelve la dirección del Tesorero de la cooperativa (para que LoanManager u otros puedan verificar).
     */
    function getTesorero(uint256 _coopId)
        external
        view
        cooperativeExists(_coopId)
        returns (address)
    {
        return cooperativas[_coopId].tesorero;
    }

    /* ========== FUNCIONES INTERNAS ========== */

    function reducirFondoComun(
        uint256 _coopId,
        address _token,
        uint256 _monto
    ) external cooperativeExists(_coopId) {
        OperacionToken storage op = cooperativas[_coopId].tokens[_token];
        require(op.fondoComun >= _monto, "Fondo comun insuficiente");
        op.fondoComun -= _monto;
    }
}
