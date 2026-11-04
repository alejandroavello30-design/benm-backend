import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import express from 'express';
import { createTokenRouter } from './token-route.js';

test('recovering a name requires authentication and explicit opt-in, and preserves its identity', async () => {
    let participants = [{ identity: 'Ana' }, { identity: 'Luis' }];
    let apiCalls = 0;
    let created = 0;
    let hasRoom = true;
    const secret = 'test-secret-with-at-least-32-characters';
    const roomApi = {
        listRooms: async () => { apiCalls++; return hasRoom ? [{}] : []; },
        createRoom: async () => { created++; },
        listParticipants: async () => participants
    };
    const app = express();
    app.use('/token', createTokenRouter({ roomApi, allowedRooms: new Set(['general', 'coordinacion']),
        maxParticipants: 2, livekitUrl: 'wss://example.invalid', apiKey: 'test-key', apiSecret: secret,
        isTeamCode: code => ['member-code', 'admin-code'].includes(code), isAdminCode: code => code === 'admin-code',
        issueAttendanceToken: (name, role) => `${name}:${role}` }));
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    async function request(params) {
        const query = new URLSearchParams({ name: 'Ana', accessCode: 'member-code', room: 'general', ...params });
        const response = await fetch(`http://127.0.0.1:${server.address().port}/token?${query}`);
        return { status: response.status, body: await response.json() };
    }
    try {
        assert.equal((await request({ accessCode: 'wrong', recoverSession: 'true' })).status, 401);
        assert.equal(apiCalls, 0);
        assert.equal((await request({ room: 'emergencia' })).status, 400);
        const conflict = await request({});
        assert.equal(conflict.status, 409);
        assert.equal(conflict.body.code, 'NAME_IN_USE');
        assert.equal((await request({ recoverSession: 'false' })).status, 409);
        const recovered = await request({ recoverSession: 'true' });
        assert.equal(recovered.status, 200); // Same slot even when room is full.
        const [header, payload, signature] = recovered.body.participantToken.split('.');
        assert.equal(signature, crypto.createHmac('sha256', secret).update(`${header}.${payload}`).digest('base64url'));
        const claims = JSON.parse(Buffer.from(payload, 'base64url').toString());
        assert.equal(claims.sub, 'Ana');
        assert.equal(claims.video.room, 'general');
        assert.equal(recovered.body.attendanceToken, 'Ana:member');
        assert.equal(participants.length, 2); // Issuing a token never removes anyone.
        assert.equal((await request({ name: 'Pedro', recoverSession: 'true' })).status, 403);
        participants = [];
        hasRoom = false;
        const normal = await request({ accessCode: 'admin-code' });
        assert.equal(normal.status, 200);
        assert.equal(normal.body.role, 'admin');
        assert.equal(created, 1);
    } finally { await new Promise(resolve => server.close(resolve)); }
});
