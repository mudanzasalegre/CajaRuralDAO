# Caja Rural DAO

**Caja Rural DAO** es un sistema de contratos inteligentes en Solidity pensado para crear y gestionar cooperativas de ahorro y préstamo descentralizadas en Ethereum. Permite a cada cooperativa manejar múltiples activos (ETH y tokens ERC20), controlar depósitos y retiros, ofrecer préstamos internos/externos con diferentes tasas de interés y actualizar parámetros clave mediante gobernanza.

---

## Índice de Contratos

1. **AccessControl.sol**  
2. **CajaRuralDAO.sol**  
3. **LoanManager.sol**  
4. **Governance.sol**

A continuación, se explica el propósito de cada contrato, así como el orden de despliegue y la forma en que interactúan entre sí.

---

## 1. AccessControl.sol

Este contrato se encarga de la **gestión de roles** y la **autorización de funciones**.  
- Roles principales: `ADMIN`, `TESORERO`, `SECRETARIO`, `GUARDIA`, `MIEMBRO`.  
- Cualquiera que no tenga un rol válido se considera `NONE` por defecto.  
- Contiene _modifiers_ como `onlyAdmin`, `onlyTesorero` y `onlyMiembro`, que permiten restringir funciones sensibles.  
- El `ADMIN` inicial es el deployer (la cuenta que despliega este contrato), y puede asignar o revocar roles a otras direcciones.

**Orden de despliegue:** Se recomienda **desplegar primero** este contrato, ya que algunos de los demás contratos pueden heredar o usar sus modificadores (p. ej., `CajaRuralDAO`).

---

## 2. CajaRuralDAO.sol

Este contrato es el **núcleo** del sistema. Aquí se definen las cooperativas y sus reglas de operación:

1. **Cooperativas (struct Cooperative):**  
   - Cada una tiene un ID único (`coopId`), un `tesorero`, un `secretario`, dos `guardas`, y una lista de miembros.  
   - También define las configuraciones de tokens disponibles, el porcentaje destinado a obra social, etc.

2. **Miembros (struct Member):**  
   - Cada miembro lleva un registro individual de sus depósitos y retiros por cada token.

3. **Tokens (struct OperacionToken):**  
   - Permite habilitar múltiples tokens (ETH o ERC20) con parámetros propios (tasa de interés interna/externa, fondo común, fondo social).

4. **Funciones principales:**  
   - `crearCooperativa(...)`: Crea una nueva cooperativa, define tesorero/secretario/guardas y el porcentaje de obra social.  
   - `solicitarIngreso(...)`: Un usuario pide unirse a una cooperativa.  
   - `aprobarIngreso(...)`: El tesorero aprueba a un nuevo miembro.  
   - `habilitarToken(...)`: El tesorero habilita un token y define sus parámetros.  
   - `depositar(...)` / `retirarFondos(...)`: Controlan las entradas y salidas de fondos para cada miembro y token.  
   - `getFondos(...)`, `getTokenData(...)`: Proporcionan información sobre el estado de la cooperativa (fondo común, obra social, tasas, etc.).  
   - `reducirFondoComun(...)`: Permite a módulos externos (p. ej. _LoanManager_) descontar fondos cuando se desembolsa un préstamo.  
   - `actualizarParametroToken(...)`: **Sólo** el contrato de gobernanza (dirección `governanceAddress`) puede llamar esta función para cambiar dinámicamente tasas o porcentajes.  

**Orden de despliegue:** Se **despliega después** de `AccessControl`, para que pueda heredar (o usar) sus modificadores y roles. Una vez desplegado, se recomienda configurar el `governanceAddress` llamando a `setGovernanceAddress(...)`.

---

## 3. LoanManager.sol

Este contrato gestiona la **lógica de préstamos** (desde su creación hasta el repago):

1. **Estructura de un Préstamo (struct Loan):**  
   - Contiene datos como el `coopId` al que pertenece, el token usado, el solicitante, el monto, tasas de interés, fechas de aprobación/repago y el estado (Pendiente, Aprobado, EnCurso, etc.).

2. **Flujo de préstamos:**  
   - `solicitarPrestamo(...)`: Un miembro activo solicita un préstamo interno o externo (definido por `LoanType`). Se obtienen las tasas desde `CajaRuralDAO` (función `getTokenData`).  
   - `aprobarPrestamo(...)`: El **tesorero** (verificado leyendo `getTesorero(...)` de la DAO) cambia el estado del préstamo a _Aprobado_.  
   - `desembolsarPrestamo(...)`: El tesorero descuenta fondos del _fondo común_ en la DAO (`reducirFondoComun(...)`) y cambia el estado a _EnCurso_.  
   - `repagarPrestamo(...)`: El solicitante paga en ETH (simple ejemplo), se calcula la parte de interés acumulado en función del tiempo. Si el repago es completo, el préstamo pasa a _Finalizado_.  
   - `verificarImpago(...)`: Si se supera la fecha de repago, se marca como _Impago_ y se aplica penalización (p. ej. aumentar la tasa de interés).

**Orden de despliegue e interacción:**  
- Se despliega **después** de `CajaRuralDAO`, recibiendo en su constructor la dirección del DAO.  
- Llama a funciones de la DAO para verificar fondos, obtener parámetros e identificar al tesorero.

---

## 4. Governance.sol

Este contrato implementa la **gobernanza** para actualizar parámetros en la DAO (por ejemplo, cambiar la tasa interna de un token). Mediante la creación de propuestas y la emisión de votos, los miembros deciden si se aprueban o no:

1. **Propuestas (struct Proposal):**  
   - Contiene el `coopId` afectado, la dirección del token, una descripción, la fecha límite para votar, estado (_Pendiente, Aprobada, Rechazada, Ejecutada_), recuento de votos a favor/en contra, tipo de propuesta (por ejemplo, `1` para cambiar `tasaInteresInterna`).

2. **Flujo de gobernanza:**  
   - `crearPropuesta(...)`: Cualquiera puede proponer un cambio (por ejemplo, aumentar la tasa de interés externa).  
   - `votarPropuesta(...)`: Los usuarios emiten su voto.  
   - `ejecutarPropuesta(...)`: Si los votos a favor superan a los votos en contra, se considera aprobada y se llama a la función `actualizarParametroToken(...)` del DAO (mediante la interfaz `ICajaRuralDAO`). Dicho método en la DAO está restringido para que **solo** la dirección configurada en `governanceAddress` pueda modificar parámetros.

**Orden de despliegue e interacción:**  
- Se despliega **después** de `CajaRuralDAO`.  
- Al desplegarlo, se le pasa la dirección del DAO, y luego, en `CajaRuralDAO`, se llama a `setGovernanceAddress(...)` con la dirección de este contrato de gobernanza para cerrar el ciclo de autorización.

---

## Interacción entre los Contratos

1. **AccessControl**  
   - Define roles y permisos básicos. Los demás contratos pueden heredar este control o simplemente establecer su propia lógica de autorización.

2. **CajaRuralDAO**  
   - Es el **corazón** del sistema, ya que gestiona la información de las cooperativas, los miembros y los tokens.  
   - Presta funciones clave a los demás módulos: por ejemplo, `LoanManager` llama a `reducirFondoComun(...)` para desembolsar un préstamo y a `getFondos(...)` para chequear liquidez.  
   - A su vez, `Governance` llama a `actualizarParametroToken(...)` cuando se aprueban propuestas.

3. **LoanManager**  
   - Maneja la lógica de préstamos (solicitud, aprobación, desembolso, repago, impago).  
   - Recopila la configuración de tasas y el rol de tesorero directamente de la DAO para tomar decisiones.

4. **Governance**  
   - Permite la **creación y votación de propuestas**.  
   - Si la votación finaliza en _aprobada_, el contrato llama a la DAO para actualizar parámetros (p. ej. `tasaInteresInterna`, `tasaInteresExterna`, etc.).

En conjunto, estos contratos ofrecen una **solución robusta y descentralizada** para gestionar cooperativas de ahorro y préstamo en Ethereum, con seguridad basada en roles, préstamos flexibles con tasas dinámicas y la capacidad de cambiar parámetros críticos mediante la votación comunitaria.

