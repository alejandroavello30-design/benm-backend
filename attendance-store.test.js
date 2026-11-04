import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { createCloudinaryStore } from './attendance-store.js';
import { createAttendance } from './attendance.js';

function fixture() {
    const assets = new Map();
    const uploads = [];
    const cloudinary = {
        api: {
            async resource(id, options) {
                assert.equal(options.type, 'authenticated');
                assert.equal(options.resource_type, 'raw');
                if (!assets.has(id)) throw { http_code: 404 };
                return structuredClone(assets.get(id));
            },
            async resources(options) {
                assert.equal(options.type, 'authenticated');
                assert.equal(options.context, true);
                const rows = [...assets.values()].filter(row => row.public_id.startsWith(options.prefix));
                const offset = Number(options.next_cursor || 0);
                return { resources: structuredClone(rows.slice(offset, offset + 2)), ...(rows.length > offset + 2 ? { next_cursor: String(offset + 2) } : {}) };
            }
        },
        uploader: {
            async upload(data, options) {
                assert.equal(options.type, 'authenticated');
                assert.equal(options.resource_type, 'raw');
                assert.equal(options.overwrite, false);
                assert.ok(data.startsWith('data:application/json;base64,'));
                await new Promise(resolve => setImmediate(resolve)); // Exercise competing writes.
                uploads.push(options);
                const existing = assets.has(options.public_id);
                if (!existing) assets.set(options.public_id, { public_id: options.public_id, type: 'authenticated', resource_type: 'raw',
                    context: { custom: options.context }, secure_url: 'https://example.invalid/private-file' });
                return { existing };
            },
            async destroy(id, options) {
                assert.equal(options.type, 'authenticated');
                assets.delete(id);
                return { result: 'ok' };
            }
        }
    };
    return { cloudinary, assets, uploads };
}
const makeRecord = name => ({ name, date: '2026-11-04', markedAt: '2026-11-04T12:00:00Z', markedBy: 'Jefe', source: 'admin' });

test('authenticated cloud storage preserves first attendance across concurrent writes and restarts', async () => {
    const f = fixture();
    const store = createCloudinaryStore(f.cloudinary);
    const results = await Promise.all(Array.from({ length: 6 }, (_, index) => store.mark({ ...makeRecord('José'), markedAt: `2026-11-04T12:00:0${index}Z` })));
    assert.equal(results.filter(result => !result.duplicate).length, 1);
    assert.ok(results.every(result => result.record.markedAt === results[0].record.markedAt));
    await store.mark(makeRecord('Ana'));
    await store.mark(makeRecord('Luis'));
    const reloaded = createCloudinaryStore(f.cloudinary);
    assert.equal((await reloaded.list('2026-11-04')).length, 3); // Includes second page.
    assert.equal((await reloaded.list('2026-11-04', 'JOSÉ')).length, 1);
    assert.equal((await reloaded.list('2026-11-04', 'Otra persona')).length, 0);
    assert.equal((await reloaded.list('2026-11-03')).length, 0);
    assert.ok([...f.assets.keys()].every(id => !id.includes('José') && id.startsWith('benm/attendance/')));
    assert.equal(JSON.stringify(await reloaded.list('2026-11-04')).includes('secure_url'), false);
    assert.ok(f.uploads.every(options => options.context.record.length < 1024));
});

test('storage probe verifies metadata and removes only its own disposable asset', async () => {
    const f = fixture();
    const store = createCloudinaryStore(f.cloudinary);
    await store.mark(makeRecord('Ana'));
    await store.verify();
    assert.equal(f.assets.size, 1);
    assert.equal((await store.list('2026-11-04'))[0].name, 'Ana');
});

test('cloud storage routes isolate member data and do not confirm failed writes', async () => {
    const f = fixture();
    const store = createCloudinaryStore(f.cloudinary);
    const attendance = createAttendance({ store, secret: 'test-only', now: () => new Date('2026-11-04T12:00:00Z') });
    await store.mark(makeRecord('Ana')); await store.mark(makeRecord('Luis'));
    const app = express(); app.use('/attendance', attendance.router);
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    const endpoint = `http://127.0.0.1:${server.address().port}/attendance`;
    const auth = role => ({ Authorization: `Bearer ${attendance.issueToken('Ana', role)}`, 'Content-Type': 'application/json' });
    try {
        const member = await fetch(endpoint, { headers: auth('member') });
        const body = await member.json();
        assert.deepEqual(body.records.map(record => record.name), ['Ana']);
        const admin = await fetch(endpoint, { headers: auth('admin') });
        assert.equal((await admin.json()).records.length, 2);
        f.cloudinary.uploader.upload = async () => { throw { http_code: 500 }; };
        const failed = await fetch(endpoint, { method: 'POST', headers: auth('admin'), body: JSON.stringify({ name: 'Nueva persona' }) });
        assert.equal(failed.status, 503);
        assert.equal(f.assets.size, 2);
        // Corrupt or wrongly protected storage must fail closed instead of becoming an empty list.
        const resource = [...f.assets.values()][0]; resource.type = 'upload';
        const corrupted = await fetch(endpoint, { headers: auth('member') });
        assert.equal(corrupted.status, 503);
    } finally { await new Promise(resolve => server.close(resolve)); }
});
