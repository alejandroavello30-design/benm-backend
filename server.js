import 'dotenv/config';
import express from 'express';
import crypto from 'node:crypto';
import path from 'node:path';
import multer from 'multer';
import { v2 as cloudinary } from 'cloudinary';
import { AccessToken, LiveKitAPI } from 'livekit-server-sdk';

const app = express();
app.disable('x-powered-by');

const PORT = Number(process.env.PORT || 3000);
const TEAM_ACCESS_CODE = process.env.TEAM_ACCESS_CODE || '';
const ADMIN_ACCESS_CODE = process.env.ADMIN_ACCESS_CODE || '';
const LIVEKIT_URL = process.env.LIVEKIT_URL || '';
const MAX_PARTICIPANTS = Number(process.env.ROOM_MAX_PARTICIPANTS || 25);
const ROOM_DEFAULT = 'general';
const allowedRooms = new Set(['general', 'coordinacion', 'emergencia']);
const emergencyAlerts = new Map();

const CLOUDINARY_CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME || '';
const CLOUDINARY_API_KEY = process.env.CLOUDINARY_API_KEY || '';
const CLOUDINARY_API_SECRET = process.env.CLOUDINARY_API_SECRET || '';
const FILES_TAG = 'benm_files';
const FILES_FOLDER = 'benm/files';

if (!CLOUDINARY_CLOUD_NAME || !CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
    console.warn('Cloudinary no está configurado: /files devolverá 503 hasta configurar CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY y CLOUDINARY_API_SECRET.');
} else {
    cloudinary.config({
        cloud_name: CLOUDINARY_CLOUD_NAME,
        api_key: CLOUDINARY_API_KEY,
        api_secret: CLOUDINARY_API_SECRET,
        secure: true
    });
}

const api = new LiveKitAPI({
    host: LIVEKIT_URL.replace(/^wss:/, 'https:').replace(/^ws:/, 'http:'),
    apiKey: process.env.LIVEKIT_API_KEY,
    secret: process.env.LIVEKIT_API_SECRET,
});

const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024 }
});

function isTeamCode(code) {
    return code === TEAM_ACCESS_CODE || (ADMIN_ACCESS_CODE && code === ADMIN_ACCESS_CODE);
}

function isAdminCode(code) {
    return Boolean(ADMIN_ACCESS_CODE) && code === ADMIN_ACCESS_CODE;
}

app.get('/health', (_req, res) => {
    res.json({
        ok: true,
        service: 'radio-equipo',
        maxParticipants: MAX_PARTICIPANTS,
        files: true,
        cloudinary: Boolean(CLOUDINARY_CLOUD_NAME && CLOUDINARY_API_KEY && CLOUDINARY_API_SECRET)
    });
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
        message: message.slice(0, 180),
        timestamp: Date.now()
    };
    emergencyAlerts.set(roomName, alert);
    res.set('Cache-Control', 'no-store');
    res.json({ ok: true, alert });
});

function requireCloudinary(res) {
    if (!CLOUDINARY_CLOUD_NAME || !CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
        res.status(503).json({ error: 'Almacenamiento de archivos no configurado en Render. Falta configurar Cloudinary.' });
        return false;
    }
    return true;
}

function safeFileName(name) {
    return String(name || 'archivo')
        .replace(/\\/g, '_').replace(/"/g, '_').replace(/[\r\n]/g, '_')
        .replace(/[^A-Za-z0-9._áéíóúÁÉÍÓÚñÑ -]/g, '_')
        .replace(/\.\.+/g, '.')
        .trim().slice(0, 180) || `archivo_${Date.now()}`;
}

function extensionOf(name) {
    const ext = String(name).split('.').pop();
    return ext ? ext.toUpperCase() : 'ARCHIVO';
}

function resourceTypeFor(name, mime) {
    if (String(mime).startsWith('image/')) return 'image';
    if (String(mime).startsWith('video/') || String(mime).startsWith('audio/')) return 'video';
    return 'raw';
}

function assetId(resourceType, publicId) {
    return Buffer.from(`${resourceType}|${publicId}`, 'utf8').toString('base64url');
}

function decodeAssetId(id) {
    try {
        const decoded = Buffer.from(String(id || ''), 'base64url').toString('utf8');
        const sep = decoded.indexOf('|');
        if (sep <= 0) return null;
        const resourceType = decoded.slice(0, sep);
        const publicId = decoded.slice(sep + 1);
        if (!['image', 'video', 'raw'].includes(resourceType) || !publicId.startsWith(`${FILES_FOLDER}/`)) return null;
        return { resourceType, publicId };
    } catch { return null; }
}

function contextValue(resource, key) {
    return resource?.context?.custom?.[key] || resource?.context?.[key] || '';
}

function publicFileInfo(resource) {
    let originalName = contextValue(resource, 'original_name');
    if (!originalName) {
        const base = String(resource.original_filename || resource.public_id.split('/').pop() || 'archivo');
        originalName = resource.resource_type === 'raw' ? base : `${base}${resource.format ? `.${resource.format}` : ''}`;
    }
    return {
        id: assetId(resource.resource_type, resource.public_id),
        name: originalName,
        size: Number(resource.bytes || 0),
        modified: resource.created_at ? Date.parse(resource.created_at) : Date.now(),
        extension: extensionOf(originalName),
        resourceType: resource.resource_type,
        url: resource.secure_url || ''
    };
}

async function listCloudinaryFiles() {
    const all = [];
    for (const resourceType of ['raw', 'image', 'video']) {
        const result = await cloudinary.api.resources_by_tag(FILES_TAG, {
            resource_type: resourceType,
            type: 'upload',
            max_results: 500,
            direction: 'desc',
            context: true
        });
        all.push(...(result.resources || []));
    }
    return all.map(publicFileInfo).sort((a, b) => b.modified - a.modified);
}

async function findCloudinaryResource(id) {
    const decoded = decodeAssetId(id);
    if (!decoded) return null;
    return cloudinary.api.resource(decoded.publicId, {
        resource_type: decoded.resourceType,
        type: 'upload',
        context: true
    });
}

async function uploadToCloudinary(file) {
    const originalName = safeFileName(file.originalname || `archivo_${Date.now()}`);
    const mime = file.mimetype || 'application/octet-stream';
    const resourceType = resourceTypeFor(originalName, mime);
    const ext = resourceType === 'raw' ? path.extname(originalName) : '';
    const base = path.basename(originalName, path.extname(originalName)).replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 100) || 'archivo';
    const publicId = `${FILES_FOLDER}/${Date.now()}_${crypto.randomBytes(4).toString('hex')}_${base}${ext}`;

    return new Promise((resolve, reject) => {
        const stream = cloudinary.uploader.upload_stream({
            resource_type: resourceType,
            type: 'upload',
            public_id: publicId,
            tags: [FILES_TAG],
            context: `original_name=${originalName}|mime=${mime}`
        }, (error, result) => error ? reject(error) : resolve(result));
        stream.end(file.buffer);
    });
}

/* ---------- ARCHIVOS / INSTRUCTIVOS ---------- */

app.get('/files', async (req, res) => {
    const accessCode = String(req.query.accessCode || '');
    if (!isTeamCode(accessCode)) return res.status(401).json({ error: 'Código de equipo incorrecto.' });
    if (!requireCloudinary(res)) return;
    try {
        const files = await listCloudinaryFiles();
        res.set('Cache-Control', 'no-store');
        res.json({ ok: true, role: isAdminCode(accessCode) ? 'admin' : 'member', files });
    } catch (error) {
        console.error('Cloudinary list:', error);
        res.status(502).json({ error: 'No se pudieron consultar los archivos en Cloudinary.' });
    }
});

app.get('/files/:id', async (req, res) => {
    const accessCode = String(req.query.accessCode || '');
    if (!isTeamCode(accessCode)) return res.status(401).json({ error: 'Código de equipo incorrecto.' });
    if (!requireCloudinary(res)) return;
    try {
        const resource = await findCloudinaryResource(req.params.id);
        if (!resource?.secure_url) return res.status(404).json({ error: 'Archivo no encontrado.' });
        res.set('Cache-Control', 'no-store');
        res.redirect(302, resource.secure_url);
    } catch (error) {
        if (error?.http_code === 404) return res.status(404).json({ error: 'Archivo no encontrado.' });
        console.error('Cloudinary get:', error);
        res.status(502).json({ error: 'No se pudo localizar el archivo.' });
    }
});

app.post('/files', (req, res) => {
    upload.single('file')(req, res, async err => {
        if (err) return res.status(400).json({ error: err.message || 'No se pudo recibir el archivo.' });
        const accessCode = String(req.body?.accessCode || '');
        if (!isAdminCode(accessCode)) return res.status(403).json({ error: 'Solo el administrador puede subir archivos.' });
        if (!requireCloudinary(res)) return;
        if (!req.file) return res.status(400).json({ error: 'No se recibió ningún archivo.' });
        try {
            const uploaded = await uploadToCloudinary(req.file);
            res.json({ ok: true, file: publicFileInfo(uploaded) });
        } catch (error) {
            console.error('Cloudinary upload:', error);
            res.status(502).json({ error: 'No se pudo guardar el archivo en Cloudinary.' });
        }
    });
});

app.delete('/files/:id', async (req, res) => {
    const accessCode = String(req.query.accessCode || '');
    if (!isAdminCode(accessCode)) return res.status(403).json({ error: 'Solo el administrador puede eliminar archivos.' });
    if (!requireCloudinary(res)) return;
    try {
        const decoded = decodeAssetId(req.params.id);
        if (!decoded) return res.status(400).json({ error: 'Identificador de archivo inválido.' });
        const result = await cloudinary.uploader.destroy(decoded.publicId, {
            resource_type: decoded.resourceType,
            type: 'upload',
            invalidate: true
        });
        if (result.result !== 'ok' && result.result !== 'not found') return res.status(502).json({ error: 'Cloudinary no pudo eliminar el archivo.' });
        res.json({ ok: true });
    } catch (error) {
        console.error('Cloudinary delete:', error);
        res.status(502).json({ error: 'No se pudo eliminar el archivo.' });
    }
});

/* ---------- TOKEN LIVEKIT ---------- */

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

        if (!isTeamCode(accessCode)) {
            return res.status(401).json({ error: 'Código de equipo incorrecto.' });
        }

        // Create/configure the room before querying participants.
        const rooms = await api.room.listRooms([roomName]);
        if (rooms.length === 0) {
            await api.room.createRoom({
                name: roomName,
                maxParticipants: MAX_PARTICIPANTS,
                emptyTimeout: 10 * 60
            });
        }

        const participants = await api.room.listParticipants(roomName);

        if (participants.some((p) => p.identity === name)) {
            return res.status(409).json({ error: 'Ese nombre ya está conectado.' });
        }

        if (participants.length >= MAX_PARTICIPANTS) {
            return res.status(403).json({ error: `El canal está lleno (${MAX_PARTICIPANTS} integrantes).` });
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
            room: roomName,
            role: isAdminCode(accessCode) ? 'admin' : 'member'
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error interno del servidor.' });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Radio Equipo token server escuchando en http://0.0.0.0:${PORT}`);
});
