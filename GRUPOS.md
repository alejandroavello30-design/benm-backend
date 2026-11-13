# Códigos de grupo en BENM

1. Actualiza el servidor BENM en Render y distribuye la versión Android compatible con grupos.
2. En Render, abre el servicio BENM, entra a Environment y agrega la variable BENM_GROUPS.
3. Pega una lista JSON como la de abajo. Reemplaza el código de ejemplo por uno aleatorio y compártelo solo con los integrantes. Conserva TEAM_ACCESS_CODE y ADMIN_ACCESS_CODE del equipo principal.
4. Guarda los cambios en Render. Cada integrante escribe su nombre y el código de su grupo en el campo Código del equipo de BENM.

[
  {"id":"sucursal-norte","code":"REEMPLAZAR-POR-CODIGO-ALEATORIO","limit":3}
]

Para crear otro grupo, añade otro objeto con id y código distintos. El id se usa para localizar los datos del grupo, así que mantenlo fijo al cambiar el código. Opcionalmente, agrega adminCode con un código diferente para administrar la asistencia y los instructivos de esa sucursal.

Genera un código aleatorio desde el directorio del servidor:

    node -e "console.log(require('node:crypto').randomBytes(18).toString('hex'))"

El límite es de conexiones simultáneas por canal. Un código compartido no reserva cupos para tres personas específicas. Al cambiar el código, las nuevas conexiones usan el nuevo código. Las sesiones y tokens ya emitidos siguen sujetos a su duración normal.

Los grupos usan salas LiveKit y espacios de asistencia, alertas e instructivos separados. La lista editable sigue guardada en cada teléfono. Las versiones anteriores de BENM conservan la compatibilidad con el equipo principal. Los grupos nuevos requieren el cliente Android actualizado.
