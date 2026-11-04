import crypto from 'node:crypto';
import { createFileStore, attendanceIdentity as identity } from './attendance-store.js';
import express from 'express';

// One server process owns this store. Mount ATTENDANCE_DIR on a persistent disk.
export function createAttendance({ directory, store, secret, now = () => new Date() }) {
    const router = express.Router();
    const storage = store || (directory ? createFileStore(directory) : null);
    const key = secret || crypto.randomBytes(32);
    const today = () => new Intl.DateTimeFormat('en-CA', {
        timeZone: 'America/Santiago', year: 'numeric', month: '2-digit', day: '2-digit'
    }).format(now());
    const sign = value => crypto.createHmac('sha256', key).update(value).digest('base64url');
    function issueToken(name, role) {
        const body = Buffer.from(JSON.stringify({ name, role, expires: now().getTime() + 24 * 3600000 })).toString('base64url');
        return `${body}.${sign(body)}`;
    }
    router.use(express.json({ limit: '8kb' }));
    router.use((req, res, next) => {
        res.set('Cache-Control', 'no-store');
        try {
            const [body, signature] = String(req.headers.authorization || '').replace(/^Bearer /, '').split('.');
            const expected = sign(body || '');
            if (!signature || signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) throw Error();
            const session = JSON.parse(Buffer.from(body, 'base64url').toString());
            if (!session.name || session.expires <= now().getTime()) throw Error();
            req.attendanceSession = session;
        } catch {
            return res.status(401).json({ error: 'Vuelve a conectar BENM para renovar el acceso a asistencia.' });
        }
        if (!storage) return res.status(503).json({ error: 'El administrador debe configurar el almacenamiento persistente de asistencia.' });
        next();
    });
    function dateParam(value) {
        const date = value || today();
        if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(Date.parse(`${date}T12:00:00Z`)) || new Date(`${date}T12:00:00Z`).toISOString().slice(0, 10) !== date || date > today()) return null;
        return date;
    }
    router.get('/', async (req, res) => {
        const date = dateParam(req.query.date);
        if (!date) return res.status(400).json({ error: 'Fecha inválida o futura.' });
        try {
            const session = req.attendanceSession;
            const records = await storage.list(date);
            res.json({ date, today: today(), role: session.role, records });
        } catch { res.status(503).json({ error: 'No se pudo leer la asistencia. Intenta nuevamente.' }); }
    });
    router.post('/', async (req, res) => {
        const session = req.attendanceSession;
        const date = dateParam(req.body.date);
        const name = String(req.body.name || session.name).trim().replace(/\s+/g, ' ');
        if (!date || !name || name.length > 30 || /[\x00-\x1f]/.test(name)) return res.status(400).json({ error: 'Nombre o fecha inválidos.' });
        if (session.role !== 'admin' && (date !== today() || identity(name) !== identity(session.name))) return res.status(403).json({ error: 'Solo puedes marcar tu propia asistencia de hoy.' });
        try {
            const record = { name, date, markedAt: now().toISOString(), markedBy: session.name, source: session.role === 'admin' ? 'admin' : 'member' };
            const result = await storage.mark(record);
            res.status(result.duplicate ? 200 : 201).json({ ok: true, ...result });
        } catch { res.status(503).json({ error: 'No se pudo guardar la asistencia. No se registró la confirmación; intenta nuevamente.' }); }
    });
    return { router, issueToken };
}
