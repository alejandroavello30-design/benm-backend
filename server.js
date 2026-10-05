import 'dotenv/config';
import express from 'express';
import crypto from 'node:crypto';
import { AccessToken, LiveKitAPI } from 'livekit-server-sdk';

const app = express();
app.disable('x-powered-by');

const PORT = Number(process.env.PORT || 3000);
const TEAM_ACCESS_CODE = process.env.TEAM_ACCESS_CODE || '';
const LIVEKIT_URL = process.env.LIVEKIT_URL || '';
const MAX_PARTICIPANTS = Number(process.env.ROOM_MAX_PARTICIPANTS || 25);
const ROOM_DEFAULT = 'general';
const allowedRooms = new Set(['general', 'coordinacion', 'emergencia']);
const emergencyAlerts = new Map();

if (!TEAM_ACCESS_CODE || !LIVEKIT_URL || !process.env.LIVEKIT_API_KEY || !process.env.LIVEKIT_API_SECRET) {
    console.error('Faltan variables de entorno. Revisa .env');
    process.exit(1);
}

const api = new LiveKitAPI({
    host: LIVEKIT_URL.replace(/^wss:/, 'https:').replace(/^ws:/, 'http:'),
    apiKey: process.env.LIVEKIT_API_KEY,
    secret: process.env.LIVEKIT_API_SECRET,
});

app.get('/health', (_req, res) => {
    res.json({ ok: true, service: 'radio-equipo', maxParticipants: MAX_PARTICIPANTS });
});

app.get('/emergency', (req, res) => {
    res.set('Cache-Control', 'no-store');
    const roomName = String(req.query.room || ROOM_DEFAULT).trim() || ROOM_DEFAULT;
    const alert = emergencyAlerts.get(roomName);
    res.json({ ok: true, alert: alert || null });
});

app.post('/emergency', express.json(), (req, res) => {
    const sender = String(req.body?.sender || '').trim();
    const roomName = String(req.body?.room || ROOM_DEFAULT).trim() || ROOM_DEFAULT;
    const message = String(req.body?.message || 'EMERGENCIA activada').trim();

    if (!sender || sender.length > 30 || !allowedRooms.has(roomName)) {
        return res.status(400).json({ error: 'Solicitud de emergencia inválida.' });
    }

    const alert = {
        id: crypto.randomUUID(),
        sender,
        room: roomName,
        message: message.slice(0, 120),
        timestamp: Date.now()
    };
    emergencyAlerts.set(roomName, alert);
    res.set('Cache-Control', 'no-store');
    res.json({ ok: true, alert });
});

app.get('/token', async (req, res) => {
    try {
        const name = String(req.query.name || '').trim();
        const accessCode = String(req.query.accessCode || '');
        const roomName = String(req.query.room || ROOM_DEFAULT).trim() || ROOM_DEFAULT;

        if (!allowedRooms.has(roomName)) {
            return res.status(400).json({ error: 'Canal no permitido.' });
        }

        if (!name || name.length > 30) {
            return res.status(400).json({ error: 'Nombre inválido.' });
        }

        if (accessCode !== TEAM_ACCESS_CODE) {
            return res.status(401).json({ error: 'Código de equipo incorrecto.' });
        }

        const participants = await api.room.listParticipants(roomName);

        if (participants.some((p) => p.identity === name)) {
            return res.status(409).json({ error: 'Ese nombre ya está conectado.' });
        }

        if (participants.length >= MAX_PARTICIPANTS) {
            return res.status(403).json({ error: `El canal está lleno (${MAX_PARTICIPANTS} integrantes).` });
        }

        // Create/configure the room on first use. The LiveKit server also
        // enforces maxParticipants at the room level.
        const rooms = await api.room.listRooms([roomName]);
        if (rooms.length === 0) {
            await api.room.createRoom({
                name: roomName,
                maxParticipants: MAX_PARTICIPANTS,
                emptyTimeout: 10 * 60
            });
        }

        const token = new AccessToken(
            process.env.LIVEKIT_API_KEY,
            process.env.LIVEKIT_API_SECRET,
            {
                identity: name,
                name,
                ttl: '2h'
            }
        );

        token.addGrant({
            roomJoin: true,
            room: roomName,
            canPublish: true,
            canSubscribe: true
        });

        const participantToken = await token.toJwt();

        res.json({
            serverUrl: LIVEKIT_URL,
            participantToken,
            room: roomName
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error interno del servidor.' });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Radio Equipo token server escuchando en http://0.0.0.0:${PORT}`);
});
