// SPDX-License-Identifier: PropietarioUnico
pragma solidity ^0.8.28;

import "./AccessControl.sol";

/**
 * @title IERC20
 * @notice Interfaz mínima para interactuar con tokens ERC20.
 */
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

/**
 * @title CajaRuralDAO
 * @notice Contrato base para la gestión de cooperativas de ahorro y préstamo (Caja Rural DAO).
 * Permite que cada cooperativa opere con múltiples tokens (ETH y ERC20) y lleve un control de depósitos, retiros y fondos.
 */
contract CajaRuralDAO is AccessControl {
    
    /* ========== ESTRUCTURAS ========== */
    
    /**
     * @notice Datos operativos para cada token admitido en la cooperativa.
     * @param enabled Indica si el token está habilitado para operar.
     * @param tasaInteresInterna Tasa de interés anual para préstamos internos (en porcentaje).
     * @param tasaInteresExterna Tasa de interés anual para préstamos externos (en porcentaje).
     * @param porcentajeFondoExterno Porcentaje del fondo destinado a préstamos externos.
     * @param fondoComun Acumulado de fondos disponibles en el fondo común para este token.
     * @param fondoObraSocial Acumulado de fondos destinados a obra social para este token.
     * @param depositosTotales Total de depósitos realizados con este token.
     */
    struct OperacionToken {
        bool enabled;
        uint256 tasaInteresInterna;
        uint256 tasaInteresExterna;
        uint256 porcentajeFondoExterno;
        uint256 fondoComun;
        uint256 fondoObraSocial;
        uint256 depositosTotales;
    }
    
    /**
     * @notice Registro individual de cada miembro, por token.
     * @dev Se usan mappings para llevar el total depositado y lo ya retirado por cada token.
     */
    struct Member {
        address cuenta;
        mapping(address => uint256) totalDepositos; // token => monto depositado total
        mapping(address => uint256) retirado;       // token => monto ya retirado
        bool activo;
    }
    
    /**
     * @notice Representa una cooperativa de ahorro y préstamo.
     * @dev Contiene datos generales, roles, lista de miembros y la configuración de cada token.
     */
    struct Cooperative {
        uint256 id;
        string nombre;
        address creador;
        address tesorero;
        address secretario;
        address[2] guardas;
        address[] listaMiembros; // Listado de direcciones de miembros
        mapping(address => Member) miembros; // Mapping de miembros registrados
        mapping(address => OperacionToken) tokens; // Mapping de tokens admitidos
        address[] tokenList; // Lista de tokens habilitados (para iterar, si es necesario)
        uint256 porcentajeObraSocial; // % de cada depósito destinado a obra social (por ejemplo, 10 = 10%)
    }
    
    /* ========== VARIABLES DE ESTADO ========== */
    
    uint256 public nextCoopId; // ID incremental para cada cooperativa
    mapping(uint256 => Cooperative) internal cooperativas; // Mapping de cooperativas por ID

    /* ========== EVENTOS ========== */
    
    event CooperativeCreada(uint256 indexed coopId, string nombre, address creador);
    event MiembroSolicitado(uint256 indexed coopId, address miembro);
    event MiembroAprobado(uint256 indexed coopId, address miembro);
    event TokenHabilitado(uint256 indexed coopId, address token, uint256 tasaInterna, uint256 tasaExterna, uint256 fondoExterno);
    event DepositoRealizado(uint256 indexed coopId, address miembro, address token, uint256 monto);
    event RetiroRealizado(uint256 indexed coopId, address miembro, address token, uint256 monto);

    /* ========== MODIFICADORES ========== */
    
    /**
     * @notice Verifica que la cooperativa exista.
     */
    modifier cooperativeExists(uint256 _coopId) {
        require(_coopId < nextCoopId, "Cooperativa inexistente");
        _;
    }
    
    /* ========== FUNCIONES DE GESTIÓN DE COOPERATIVAS ========== */
    
    /**
     * @notice Crea una nueva cooperativa.
     * @param _nombre Nombre de la cooperativa.
     * @param _porcentajeObraSocial Porcentaje destinado a obra social (0-100).
     * @param _tesorero Dirección asignada como tesorero.
     * @param _secretario Dirección asignada como secretario.
     * @param _guardas Array de 2 direcciones asignadas como guardias.
     * @return coopId El ID de la cooperativa creada.
     */
    function crearCooperativa(
        string calldata _nombre,
        uint256 _porcentajeObraSocial,
        address _tesorero,
        address _secretario,
        address[2] calldata _guardas
    ) external returns (uint256 coopId) {
        require(_porcentajeObraSocial <= 100, "Porcentaje de obra social invalido");
        coopId = nextCoopId;
        nextCoopId++;

        Cooperative storage coop = cooperativas[coopId];
        coop.id = coopId;
        coop.nombre = _nombre;
        coop.creador = msg.sender;
        coop.porcentajeObraSocial = _porcentajeObraSocial;
        coop.tesorero = _tesorero;
        coop.secretario = _secretario;
        coop.guardas = _guardas;

        // Registrar al creador como miembro activo
        coop.listaMiembros.push(msg.sender);
        Member storage miembro = coop.miembros[msg.sender];
        miembro.cuenta = msg.sender;
        miembro.activo = true;

        emit CooperativeCreada(coopId, _nombre, msg.sender);
    }
    
    /**
     * @notice Permite que un usuario solicite ingresar a una cooperativa.
     * @param _coopId ID de la cooperativa.
     */
    function solicitarIngreso(uint256 _coopId) external cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        // Verifica que la cuenta aún no esté registrada.
        require(coop.miembros[msg.sender].cuenta == address(0), "Solicitud previa o ya es miembro");
        coop.listaMiembros.push(msg.sender);
        Member storage miembro = coop.miembros[msg.sender];
        miembro.cuenta = msg.sender;
        miembro.activo = false; // Pendiente de aprobación
        emit MiembroSolicitado(_coopId, msg.sender);
    }
    
    /**
     * @notice El tesorero aprueba la solicitud de ingreso de un miembro.
     * @param _coopId ID de la cooperativa.
     * @param _miembro Dirección del miembro a aprobar.
     */
    function aprobarIngreso(uint256 _coopId, address _miembro) external cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        require(msg.sender == coop.tesorero, "Solo el tesorero puede aprobar");
        Member storage miembro = coop.miembros[_miembro];
        require(!miembro.activo, "Miembro ya aprobado");
        miembro.activo = true;
        emit MiembroAprobado(_coopId, _miembro);
    }
    
    /* ========== GESTIÓN DE TOKENS ========== */
    
    /**
     * @notice Habilita un token para operar en la cooperativa.
     * @param _coopId ID de la cooperativa.
     * @param _token Dirección del contrato ERC20 (usar address(0) para ETH).
     * @param _tasaInteresInterna Tasa de interés interna (en porcentaje anual).
     * @param _tasaInteresExterna Tasa de interés externa (en porcentaje anual).
     * @param _porcentajeFondoExterno Porcentaje del fondo destinado a préstamos externos.
     */
    function habilitarToken(
        uint256 _coopId,
        address _token,
        uint256 _tasaInteresInterna,
        uint256 _tasaInteresExterna,
        uint256 _porcentajeFondoExterno
    ) external cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        // Solo el tesorero puede habilitar tokens.
        require(msg.sender == coop.tesorero, "Solo el tesorero puede habilitar tokens");
        OperacionToken storage op = coop.tokens[_token];
        op.enabled = true;
        op.tasaInteresInterna = _tasaInteresInterna;
        op.tasaInteresExterna = _tasaInteresExterna;
        op.porcentajeFondoExterno = _porcentajeFondoExterno;
        // Inicializamos acumulados en cero.
        op.fondoComun = 0;
        op.fondoObraSocial = 0;
        op.depositosTotales = 0;
        // Si el token no estaba habilitado antes, se añade a la lista.
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
        emit TokenHabilitado(_coopId, _token, _tasaInteresInterna, _tasaInteresExterna, _porcentajeFondoExterno);
    }
    
    /* ========== FUNCIONES DE DEPÓSITO Y RETIRO ========== */
    
    /**
     * @notice Permite a un miembro realizar un depósito en la cooperativa para un token dado.
     * Si _token es address(0), se opera en ETH (msg.value debe coincidir con _monto).
     * Si se trata de un token ERC20, se requiere que el usuario haya aprobado previamente el monto.
     * @param _coopId ID de la cooperativa.
     * @param _token Dirección del token (address(0) para ETH).
     * @param _monto Monto a depositar.
     */
    function depositar(
        uint256 _coopId,
        address _token,
        uint256 _monto
    ) external payable onlyMiembro cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        OperacionToken storage op = coop.tokens[_token];
        require(op.enabled, "Token no habilitado en esta cooperativa");
        
        Member storage miembro = coop.miembros[msg.sender];
        require(miembro.activo, "Miembro no activo");
        if (_token == address(0)) {
            // Operación en ETH
            require(msg.value == _monto && _monto > 0, "Monto en ETH invalido");
        } else {
            // Operación en ERC20: se usa transferFrom
            IERC20 tokenContract = IERC20(_token);
            require(tokenContract.transferFrom(msg.sender, address(this), _monto), "Transferencia ERC20 fallida");
        }
        
        // Actualizar registros: total depositado y acumulados en el token.
        miembro.totalDepositos[_token] += _monto;
        op.depositosTotales += _monto;
        
        // Distribuir el depósito entre fondo social y fondo común.
        uint256 montoObra = (_monto * coop.porcentajeObraSocial) / 100;
        uint256 montoComun = _monto - montoObra;
        op.fondoObraSocial += montoObra;
        op.fondoComun += montoComun;
        
        emit DepositoRealizado(_coopId, msg.sender, _token, _monto);
    }
    
    /**
     * @notice Permite a un miembro retirar fondos, limitando la cantidad a lo que haya aportado.
     * El miembro solo puede retirar hasta: totalDepositos - retirado para ese token.
     * Además, se verifica que el fondo común tenga liquidez suficiente.
     * @param _coopId ID de la cooperativa.
     * @param _token Dirección del token (address(0) para ETH).
     * @param _monto Monto a retirar.
     */
    function retirarFondos(
        uint256 _coopId,
        address _token,
        uint256 _monto
    ) external onlyMiembro cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        OperacionToken storage op = coop.tokens[_token];
        require(op.enabled, "Token no habilitado");
        
        Member storage miembro = coop.miembros[msg.sender];
        require(miembro.activo, "No es miembro activo");
        
        uint256 saldoDisponible = miembro.totalDepositos[_token] - miembro.retirado[_token];
        require(_monto <= saldoDisponible, "Monto supera lo aportado");
        require(op.fondoComun >= _monto, "Fondo comun insuficiente");
        
        // Actualizar registros
        miembro.retirado[_token] += _monto;
        op.fondoComun -= _monto;
        
        // Transferir fondos según el token
        if (_token == address(0)) {
            payable(msg.sender).transfer(_monto);
        } else {
            IERC20 tokenContract = IERC20(_token);
            require(tokenContract.transfer(msg.sender, _monto), "Transferencia ERC20 fallida");
        }
        
        emit RetiroRealizado(_coopId, msg.sender, _token, _monto);
    }
    
    /* ========== CONSULTAS ========== */
    
    /**
     * @notice Devuelve los fondos acumulados (fondo común y fondo de obra social) para un token en la cooperativa.
     * @param _coopId ID de la cooperativa.
     * @param _token Dirección del token.
     * @return fondoComun Monto acumulado en el fondo común.
     * @return fondoObraSocial Monto acumulado en el fondo de obra social.
     */
    function getFondos(uint256 _coopId, address _token) external view cooperativeExists(_coopId) returns (uint256 fondoComun, uint256 fondoObraSocial) {
        Cooperative storage coop = cooperativas[_coopId];
        OperacionToken storage op = coop.tokens[_token];
        return (op.fondoComun, op.fondoObraSocial);
    }
    
    /**
     * @notice Consulta si una cuenta es miembro activo de la cooperativa.
     * @param _coopId ID de la cooperativa.
     * @param _cuenta Dirección a consultar.
     * @return bool Verdadero si es miembro activo, falso en caso contrario.
     */
    function esMiembroActivo(uint256 _coopId, address _cuenta) external view cooperativeExists(_coopId) returns (bool) {
        Cooperative storage coop = cooperativas[_coopId];
        return coop.miembros[_cuenta].activo;
    }
    
    /* ========== FUNCIONES INTERNAS ========== */
    
    /**
     * @notice Función interna para reducir el fondo común tras el desembolso de un préstamo.
     * @param _coopId ID de la cooperativa.
     * @param _token Dirección del token.
     * @param _monto Monto a reducir.
     */
    function reducirFondoComun(uint256 _coopId, address _token, uint256 _monto) external cooperativeExists(_coopId) {
        Cooperative storage coop = cooperativas[_coopId];
        OperacionToken storage op = coop.tokens[_token];
        require(op.fondoComun >= _monto, "Fondo comun insuficiente");
        op.fondoComun -= _monto;
        // Se puede emitir un evento adicional aquí si se desea.
    }
}
