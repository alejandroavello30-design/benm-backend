import { createHash, timingSafeEqual } from 'node:crypto';

const digest = code => createHash('sha256').update(code).digest();

export function createGroupAccess({ teamCode, adminCode, configuration = '', defaultLimit }) {
    const groups = new Map();
    const credentials = [];
    function addCode(code, group, role) {
        if (!code) return;
        if (typeof code !== 'string' || code !== code.trim() || code.length > 128 ||
            credentials.some(entry => timingSafeEqual(entry.hash, digest(code)))) {
            throw new Error('Código de grupo duplicado o inválido.');
        }
        credentials.push({ hash: digest(code), group, role });
    }
    const main = { id: 'principal', limit: defaultLimit };
    groups.set(main.id, main);
    addCode(adminCode, main, 'admin');
    if (teamCode !== adminCode) addCode(teamCode, main, 'member');
    const entries = configuration ? JSON.parse(configuration) : [];
    if (!Array.isArray(entries)) throw new Error('BENM_GROUPS debe ser una lista JSON.');
    for (const entry of entries) {
        if (!entry || typeof entry.id !== 'string' || !/^[a-z0-9][a-z0-9-]{0,39}$/.test(entry.id) || groups.has(entry.id) ||
            typeof entry.code !== 'string' || !/^[A-Za-z0-9_-]{16,128}$/.test(entry.code) ||
            (entry.adminCode != null && (typeof entry.adminCode !== 'string' || !/^[A-Za-z0-9_-]{16,128}$/.test(entry.adminCode)))) {
            throw new Error('Grupo BENM inválido o repetido. Los códigos nuevos deben tener al menos 16 caracteres.');
        }
        const limit = entry.limit ?? defaultLimit;
        if (!Number.isInteger(limit) || limit < 1 || limit > defaultLimit) throw new Error('Límite de grupo inválido.');
        const group = { id: entry.id, limit };
        groups.set(group.id, group);
        addCode(entry.code, group, 'member');
        addCode(entry.adminCode, group, 'admin');
    }
    return {
        groups,
        resolve(code) {
            if (typeof code !== 'string' || !code || code.length > 128) return null;
            const hash = digest(code);
            const match = credentials.find(entry => timingSafeEqual(entry.hash, hash));
            return match ? { ...match.group, role: match.role } : null;
        }
    };
}

export const groupRoom = (id, channel) => id === 'principal' ? channel : `benm-group-${id}:${channel}`;
