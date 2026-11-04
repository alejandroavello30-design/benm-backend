import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import express from 'express';
import { createAttendance } from './attendance.js';

test('attendance permissions, duplicates, history, persistence and Chile date boundary', async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'benm-test-'));
    let clock = new Date('2026-11-04T02:30:00Z'); // Still November 3 in Santiago.
    const attendance = createAttendance({ directory, secret: 'test-only', now: () => clock });
    const app = express(); app.use('/attendance', attendance.router);
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}/attendance`;
    const member = attendance.issueToken('Ana', 'member');
    const admin = attendance.issueToken('Jefe', 'admin');
    async function call(token, method = 'GET', body, query = '') {
        const response = await fetch(base + query, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) });
        return { status: response.status, body: await response.json() };
    }
    try {
        assert.equal((await call('fake')).status, 401);
        assert.equal((await call(member)).body.today, '2026-11-03');
        assert.equal((await call(member, 'POST', { name: 'Luis' })).status, 403);
        assert.equal((await call(member, 'POST', { date: '2026-11-02' })).status, 403);
        assert.equal((await call(member, 'POST', { date: '2026-11-04' })).status, 400);
        assert.equal((await call(member, 'POST', {})).status, 201);
        assert.equal((await call(member, 'POST', { name: 'ANA' })).body.duplicate, true);
        const concurrent = await Promise.all(Array.from({ length: 8 }, () => call(member, 'POST', {})));
        assert.ok(concurrent.every(result => result.body.duplicate));
        assert.equal((await call(admin, 'POST', { name: 'Luis' })).status, 201);
        assert.equal((await call(member)).body.records.length, 1);
        assert.equal((await call(admin)).body.records.length, 2);
        assert.equal((await call(admin, 'POST', { name: 'Luis', date: '2026-11-02' })).status, 201);
        assert.equal((await call(admin, 'GET', null, '?date=2026-02-30')).status, 400);
        assert.equal((await call(admin, 'GET', null, '?date=../../secret')).status, 400);
        const saved = JSON.parse(fs.readFileSync(path.join(directory, '2026-11-03.json')));
        assert.equal(saved.length, 2);
        assert.equal(saved[1].markedBy, 'Jefe');
        const restarted = createAttendance({ directory, secret: 'test-only', now: () => clock });
        app.use('/restarted', restarted.router);
        const restored = await fetch(base.replace('/attendance', '/restarted'), { headers: { Authorization: `Bearer ${admin}` } });
        assert.equal((await restored.json()).records.length, 2);
        clock = new Date('2026-11-04T03:30:00Z');
        assert.equal((await call(member)).body.today, '2026-11-04');
        assert.equal((await call(member)).body.records.length, 0);
        assert.equal((await call(member, 'POST', {})).status, 201);
        assert.equal((await call(member, 'GET', null, '?date=2026-11-03')).body.records.length, 1);
        clock = new Date('2026-11-06T03:30:00Z');
        assert.equal((await call(member)).status, 401);
    } finally {
        await new Promise(resolve => server.close(resolve));
        fs.rmSync(directory, { recursive: true, force: true });
    }
});

test('missing durable storage refuses writes', async () => {
    const attendance = createAttendance({ secret: 'test-only' });
    const app = express(); app.use('/attendance', attendance.router);
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    try {
        const response = await fetch(`http://127.0.0.1:${server.address().port}/attendance`, { headers: { Authorization: `Bearer ${attendance.issueToken('Ana', 'member')}` } });
        assert.equal(response.status, 503);
    } finally { await new Promise(resolve => server.close(resolve)); }
});
