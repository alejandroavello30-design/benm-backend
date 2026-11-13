import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { createGroupAccess } from './group-access.js';
import { createTokenRouter } from './token-route.js';
import { createAttendance } from './attendance.js';

test('separate groups keep their LiveKit rooms and attendance isolated', async () => {
    const code = 'test-branch-member-code';
    const groupAccess = createGroupAccess({ teamCode: 'main-code', adminCode: 'main-admin', defaultLimit: 25,
        configuration: JSON.stringify([{ id: 'sucursal', code, limit: 3 }]) });
    const main = { list: async () => [{ name: 'Registro principal' }] };
    const branch = { list: async () => [{ name: 'Registro sucursal' }] };
    const attendance = createAttendance({ store: main, groupStorage: id => id === 'sucursal' ? branch : null });
    const rooms = [];
    const app = express();
    app.use('/attendance', attendance.router);
    app.use('/token', createTokenRouter({
        roomApi: {
            listRooms: async () => [],
            createRoom: async room => rooms.push(room),
            listParticipants: async () => []
        },
        allowedRooms: new Set(['general']), livekitUrl: 'wss://example.invalid',
        apiKey: 'test-key', apiSecret: 'test-secret-with-at-least-32-characters',
        resolveGroup: groupAccess.resolve, issueAttendanceToken: attendance.issueToken
    }));
    const server = app.listen(0, '127.0.0.1');
    try {
        await new Promise(resolve => server.once('listening', resolve));
        const base = 'http://127.0.0.1:' + server.address().port;
        const login = (accessCode, groupSupport) => fetch(base + '/token?' +
            new URLSearchParams({ name: 'Ana', accessCode, groupSupport }));
        const records = async token => (await (await fetch(base + '/attendance', {
            headers: { Authorization: 'Bearer ' + token }
        })).json()).records;
        assert.equal((await login(code, '')).status, 426);
        const primary = await (await login('main-admin', '')).json();
        const secondary = await (await login(code, '1')).json();
        assert.equal(primary.role, 'admin');
        assert.equal(secondary.role, 'member');
        assert.equal(primary.room, 'general');
        assert.equal(secondary.room, 'benm-group-sucursal:general');
        assert.equal(rooms[1].maxParticipants, 3);
        assert.deepEqual(await records(primary.attendanceToken), [{ name: 'Registro principal' }]);
        assert.deepEqual(await records(secondary.attendanceToken), [{ name: 'Registro sucursal' }]);
    } finally { await new Promise(resolve => server.close(resolve)); }
});
