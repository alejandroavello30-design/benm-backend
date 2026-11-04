# BENM backend 0.3.15-server.2

Servidor compatible con BENM Android 0.3.14 y 0.3.15. Agrega asistencia diaria, permisos de miembro/administrador y recuperación explícita de una conexión anterior con el mismo nombre. Se conservan los canales General y Coordinación, las alertas y la implementación actual de instructivos de Cloudinary.

## Render y almacenamiento

Mantener el servicio y la dirección actuales. El despliegue usa las variables existentes de LiveKit, códigos de acceso y Cloudinary (`CLOUDINARY_URL` o las tres variables `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`). No se incorporan credenciales al repositorio ni al APK.

La asistencia se guarda automáticamente en el Cloudinary existente como recursos `raw/authenticated`, con un recurso inmutable por nombre y fecha. Los nombres no se incluyen en los identificadores de archivos. El backend consulta los registros por API autenticada; no devuelve URLs de Cloudinary a los teléfonos. La carpeta de datos es independiente de `benm/files`, por lo que no se mezcla con los instructivos.

No hace falta agregar un disco de Render para esta modalidad. Se utiliza la capacidad y las cuotas de la cuenta Cloudinary actual. Los errores de almacenamiento devuelven 503, sin confirmar una marcación que no se pudo guardar.

Opcional: `ATTENDANCE_DIR` selecciona almacenamiento en un disco persistente en lugar de Cloudinary. Este adaptador de archivos requiere un solo proceso servidor propietario del directorio. No cambiar entre ambos adaptadores sin migrar previamente los datos. No utilizar una ruta efímera de Render para conservar asistencias.

`ATTENDANCE_SECRET` es opcional. Si se omite con Cloudinary configurado, la firma de sesiones se deriva en el servidor del secreto existente mediante HMAC y un propósito específico. Los tokens caducan a las 24 horas; reconectar BENM los renueva. Rotar el secreto exige reconectar los clientes. Las claves nunca salen del backend.

## Uso y permisos

- El miembro marca únicamente su propia asistencia del día y consulta su historial.
- El administrador puede marcar por otros miembros, consultar días anteriores y registrar una asistencia retroactiva.
- Se conserva la primera marcación del nombre/día, su hora real y quién la registró. Las fechas usan America/Santiago.
- El APK exporta el listado consultado por el administrador a CSV para Excel.
- La identidad sigue siendo el nombre y código compartido existentes de BENM: usar nombres completos y únicos. No hay padrón para calcular ausentes ni verificación de ubicación o identidad personal.
- Con Android 0.3.15, un nombre en uso ofrece recuperar sesión con confirmación. El backend emite un token con la misma identidad; LiveKit reemplaza la conexión anterior al ingresar realmente. Pedir el token no elimina participantes. La sustitución reutiliza la plaza del mismo nombre aun cuando el canal está lleno.

Después de desplegar, desconectar y volver a conectar el teléfono para recibir el nuevo token de asistencia.

## Verificación

```
npm ci
npm test
npm start
```

Seis pruebas automáticas cubren permisos, duplicados concurrentes, historial, cambio de día de Chile, persistencia tras recrear el adaptador, almacenamiento autenticado, paginación, errores de escritura y recuperación del nombre.

`GET /health` informa la versión, `attendanceReady`, `attendanceStorage` y `attendanceStorageCheck`. Al arrancar con Cloudinary, el servicio escribe, vuelve a leer y elimina un registro ficticio bajo `benm/attendance-probes/<UUID>`, fuera de los listados reales. `attendanceStorageCheck=passed` confirma que ese recorrido y su limpieza terminaron correctamente. La comprobación no marca asistencia de personas reales. Si falla, revisar el servicio antes de dar por operativa la asistencia.

Referencias de los proveedores:

- https://cloudinary.com/documentation/upload_parameters#authenticated_assets
- https://cloudinary.com/documentation/image_upload_api_reference#upload
- https://cloudinary.com/documentation/admin_api#get_resources
- https://docs.livekit.io/intro/basics/rooms-participants-tracks/participants/
