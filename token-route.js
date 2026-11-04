import express from 'express';
import { AccessToken } from 'livekit-server-sdk';

export function createTokenRouter({ roomApi, allowedRooms, maxParticipants, livekitUrl, apiKey, apiSecret, isTeamCode, isAdminCode, issueAttendanceToken }) {
    const router = express.Router();
    router.get('/', async (req, res) => {
        res.set('Cache-Control', 'no-store');
        try {
            const name = String(req.query.name || '').trim();
            const accessCode = String(req.query.accessCode || '');
            const roomName = String(req.query.room || 'general').trim() || 'general';
            const recoverSession = req.query.recoverSession === 'true';
            if (!allowedRooms.has(roomName)) return res.status(400).json({ error: 'Canal no permitido.' });
            if (!name || name.length > 30) return res.status(400).json({ error: 'Nombre inválido.' });
            if (!isTeamCode(accessCode)) return res.status(401).json({ error: 'Código de equipo incorrecto.' });

            const rooms = await roomApi.listRooms([roomName]);
            if (rooms.length === 0) await roomApi.createRoom({ name: roomName, maxParticipants, emptyTimeout: 10 * 60 });
            const participants = await roomApi.listParticipants(roomName);
            const existing = participants.some(participant => participant.identity === name);
            if (existing && !recoverSession) return res.status(409).json({
                code: 'NAME_IN_USE', recoverySupported: true,
                error: 'Tu nombre sigue conectado. Puedes recuperar la sesión y cerrar la conexión anterior.'
            });
            // A replacement uses the same slot. LiveKit replaces the old connection
            // only when the new client actually joins with the SAME identity.
            if (!existing && participants.length >= maxParticipants) return res.status(403).json({ error: `El canal está lleno (${maxParticipants} integrantes).` });
            const token = new AccessToken(apiKey, apiSecret, { identity: name, name, ttl: '2h' });
            token.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true });
            const role = isAdminCode(accessCode) ? 'admin' : 'member';
            res.json({ serverUrl: livekitUrl, participantToken: await token.toJwt(), room: roomName, role,
                attendanceToken: issueAttendanceToken(name, role) });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: 'Error interno del servidor.' });
        }
    });
    return router;
}
