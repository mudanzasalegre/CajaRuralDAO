// SPDX-License-Identifier: PropietarioUnico
pragma solidity ^0.8.28;

import "./CajaRuralDAO.sol";

contract LoanManager {
    enum LoanStatus { Pendiente, Aprobado, EnCurso, Finalizado, Impago, Cancelado }
    enum LoanType { Interno, Externo }

    struct Loan {
        uint256 id;
        uint256 coopId;
        address token;
        address solicitante;
        uint256 monto;
        uint256 tasaInteres;  
        uint256 fechaSolicitud;
        uint256 fechaAprobacion;
        uint256 fechaRepago;
        LoanStatus status;
        uint256 montoRepagado;
        LoanType tipo;
    }

    uint256 public nextLoanId;
    mapping(uint256 => mapping(uint256 => Loan)) public loans;  // cooperativa => (loanId => Loan)

    CajaRuralDAO public dao;

    event LoanSolicitado(uint256 indexed coopId, uint256 loanId, address solicitante, address token, uint256 monto, LoanType tipo);
    event LoanAprobado(uint256 indexed coopId, uint256 loanId, uint256 fechaRepago);
    event LoanDesembolsado(uint256 indexed coopId, uint256 loanId);
    event LoanRepagado(uint256 indexed coopId, uint256 loanId, uint256 monto);
    event LoanFinalizado(uint256 indexed coopId, uint256 loanId);
    event LoanMarcadoImpago(uint256 indexed coopId, uint256 loanId);
    event PenalizacionAplicada(uint256 indexed coopId, uint256 loanId, uint256 penalizacion);

    constructor(address _daoAddress) {
        dao = CajaRuralDAO(_daoAddress);
    }

    /**
     * @notice Solicita un préstamo, definiendo token, monto, fecha límite y tipo (interno o externo).
     */
    function solicitarPrestamo(
        uint256 _coopId,
        address _token,
        uint256 _monto,
        uint256 _fechaRepago,
        LoanType _tipo
    ) external {
        // Verifica que el solicitante sea miembro activo
        require(dao.esMiembroActivo(_coopId, msg.sender), "No es miembro activo");

        // Obtiene la config del token (tasa interna/externa, etc.)
        (bool enabled, uint256 tasaInterna, uint256 tasaExterna, , , , ) =
            dao.getTokenData(_coopId, _token);
        require(enabled, "Token no habilitado");

        // Escoge la tasa según el tipo de préstamo
        uint256 tasa = _tipo == LoanType.Interno ? tasaInterna : tasaExterna;

        // Crea el registro del préstamo
        uint256 loanId = nextLoanId++;
        loans[_coopId][loanId] = Loan({
            id: loanId,
            coopId: _coopId,
            token: _token,
            solicitante: msg.sender,
            monto: _monto,
            tasaInteres: tasa,
            fechaSolicitud: block.timestamp,
            fechaAprobacion: 0,
            fechaRepago: _fechaRepago,
            status: LoanStatus.Pendiente,
            montoRepagado: 0,
            tipo: _tipo
        });

        emit LoanSolicitado(_coopId, loanId, msg.sender, _token, _monto, _tipo);
    }

    /**
     * @notice El tesorero de la cooperativa aprueba el préstamo.
     */
    function aprobarPrestamo(uint256 _coopId, uint256 _loanId) external {
        Loan storage loan = loans[_coopId][_loanId];
        require(loan.status == LoanStatus.Pendiente, "No esta pendiente");

        // Solo el tesorero puede aprobar
        address tesorero = dao.getTesorero(_coopId);
        require(msg.sender == tesorero, "Solo tesorero");

        loan.status = LoanStatus.Aprobado;
        loan.fechaAprobacion = block.timestamp;
        emit LoanAprobado(_coopId, _loanId, loan.fechaRepago);
    }

    /**
     * @notice El tesorero de la cooperativa desembolsa el préstamo, descontando fondos del fondo común.
     */
    function desembolsarPrestamo(uint256 _coopId, uint256 _loanId) external {
        Loan storage loan = loans[_coopId][_loanId];
        require(loan.status == LoanStatus.Aprobado, "Prestamo no aprobado");

        address tesorero = dao.getTesorero(_coopId);
        require(msg.sender == tesorero, "Solo tesorero");

        // Verifica que haya fondos suficientes
        (uint256 fondoComun, ) = dao.getFondos(_coopId, loan.token);
        require(fondoComun >= loan.monto, "Fondo insuficiente");

        // Descuenta la cantidad en el DAO
        dao.reducirFondoComun(_coopId, loan.token, loan.monto);

        // Cambia el estado a EnCurso
        loan.status = LoanStatus.EnCurso;

        emit LoanDesembolsado(_coopId, _loanId);
    }

    /**
     * @notice El prestatario repaga el préstamo (en ETH en este ejemplo simplificado).
     * Se calcula el interés acumulado en función del tiempo transcurrido.
     */
    function repagarPrestamo(uint256 _coopId, uint256 _loanId) external payable {
        Loan storage loan = loans[_coopId][_loanId];
        require(loan.status == LoanStatus.EnCurso, "No esta en curso");
        require(msg.sender == loan.solicitante, "Solo solicitante");

        uint256 tiempoTranscurrido = block.timestamp - loan.fechaAprobacion;
        // Interés = principal * tasa * (tiempo / 365d) / 100
        uint256 interesAcumulado = (loan.monto * loan.tasaInteres * tiempoTranscurrido) / (365 days * 100);
        uint256 totalAdeudado = loan.monto + interesAcumulado;

        loan.montoRepagado += msg.value;

        if (loan.montoRepagado >= totalAdeudado) {
            loan.status = LoanStatus.Finalizado;
            emit LoanFinalizado(_coopId, _loanId);
        }
        emit LoanRepagado(_coopId, _loanId, msg.value);
    }

    /**
     * @notice Verifica si se ha superado la fecha límite de repago y, de ser así, marca como impago y aplica penalización.
     */
    function verificarImpago(uint256 _coopId, uint256 _loanId) external {
        Loan storage loan = loans[_coopId][_loanId];
        require(loan.status == LoanStatus.EnCurso, "No esta en curso");

        if (block.timestamp > loan.fechaRepago) {
            loan.status = LoanStatus.Impago;
            // Aplica una penalización (por ejemplo, +5% a la tasa de interés).
            uint256 penalizacion = (loan.monto * 5) / 100;
            loan.tasaInteres += 5;

            emit PenalizacionAplicada(_coopId, _loanId, penalizacion);
            emit LoanMarcadoImpago(_coopId, _loanId);
        }
    }
}
