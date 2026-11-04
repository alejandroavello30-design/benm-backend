# BENM iPhone 0.3.21 — prueba nativa

Aplicación SwiftUI para iOS 16 o posterior. Usa el servidor y códigos del equipo Android.

Funciones: radio General; alertas; archivos; lista local de 20 filas ampliable, Usuario/Tipo/Sector, correlativo, limpieza confirmada y XLSX; asistencia visible a todos, marcación propia y por administrador; exportación CSV compatible con Excel.

Desconectar conserva nombre y código. Salir/Cambiar usuario los borra. Ambas acciones piden confirmación. El código se guarda en el llavero. La lista pertenece al teléfono y permanece al cambiar de usuario.

## Instalación desde Windows

Necesitas iPhone con iOS 16+, cable, Windows y tu cuenta Apple.

1. Instala AltStore Classic según la guía oficial: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows . Usa sus enlaces de AltServer, iTunes e iCloud.
2. Conecta y desbloquea el iPhone, acepta Confiar y completa la instalación de AltStore mediante AltServer con tu cuenta Apple.
3. Habilita Modo de desarrollador y confía en el perfil si iOS lo solicita.
4. Guarda BENM-iPhone-0.3.21-AltStore.ipa en Archivos del iPhone. En AltStore Classic, My Apps, pulsa + y elige el IPA. AltStore lo firma para ese teléfono.
5. Con cuenta gratuita, renueva la firma antes de siete días mediante AltStore/AltServer. Hay límites de aplicaciones y capacidades. No es una publicación de App Store ni TestFlight.

## Límites

No integra APNs, PushKit ni Push to Talk de Apple. El permiso de audio en segundo plano no garantiza que iOS mantenga la aplicación activa en silencio. Si se fuerza el cierre o iOS suspende su proceso, no recibirá nuevas alertas. Las notificaciones locales solo se generan cuando el proceso recibe una alerta. La recepción fiable con la aplicación cerrada requiere otra fase de desarrollo y capacidades de Apple.

No se ha probado en iPhone físico. Deben comprobarse audio, reconexión y alertas antes de uso operativo.

## Compilación

Abrir BENM.xcodeproj en Xcode. El flujo de GitHub Actions usa macOS, valida el XLSX, compila para iPhone sin firma y empaqueta Payload/BENM.app como IPA. El IPA requiere firma de AltStore o Apple antes de instalar.

## Pruebas en equipo físico pendientes

- Conectar iPhone y Android con nombres diferentes y probar audio en ambas direcciones; soltar o cambiar de app debe apagar el micrófono.
- Confirmar y cancelar Desconectar y Salir; verificar credenciales y lista guardada al reabrir.
- Marcar asistencia como miembro y administrador; comprobar visibilidad desde otro teléfono y exportación.
- Lista: tildes, Tipo/Sector, agregar, exportar, abrir en Excel y limpiar con confirmación.
- Enviar los ocho tipos de alerta; comprobar ubicación de evacuación parcial y deduplicación.
- Abrir archivos; cargar/borrar como administrador.
- Cambiar red, bloquear pantalla y forzar cierre; comprobar los límites indicados arriba.
