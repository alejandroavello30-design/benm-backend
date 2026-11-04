import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const attendanceIdentity = name => name.normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('es');

export function createFileStore(directory) {
    const file = date => path.join(directory, `${date}.json`);
    function list(date) {
        try { return JSON.parse(fs.readFileSync(file(date), 'utf8')); }
        catch (error) { if (error.code === 'ENOENT') return []; throw error; }
    }
    return {
        list,
        mark(record) {
            // Synchronous read/rename keeps this adapter atomic within one process.
            const records = list(record.date);
            const existing = records.find(row => attendanceIdentity(row.name) === attendanceIdentity(record.name));
            if (existing) return { duplicate: true, record: existing };
            records.push(record);
            fs.mkdirSync(directory, { recursive: true });
            fs.writeFileSync(`${file(record.date)}.tmp`, JSON.stringify(records), { mode: 0o600 });
            fs.renameSync(`${file(record.date)}.tmp`, file(record.date));
            return { duplicate: false, record };
        }
    };
}

// Each person/day is an immutable authenticated asset. No public delivery URLs
// or Cloudinary credentials are returned to the app. Concurrent servers cannot
// overwrite the first record because every upload uses overwrite:false.
export function createCloudinaryStore(cloudinary, prefix = 'benm/attendance') {
    const options = { resource_type: 'raw', type: 'authenticated', context: true };
    const idFor = (date, name) => `${prefix}/${date}/${crypto.createHash('sha256').update(attendanceIdentity(name)).digest('hex')}.json`;
    function decode(resource, date) {
        const encoded = resource?.context?.custom?.record || resource?.context?.record;
        if (!encoded || resource.type !== 'authenticated' || resource.resource_type !== 'raw') throw Error('Invalid attendance asset');
        const record = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
        if (record.date !== date || typeof record.name !== 'string' || !record.name || record.name.length > 30 ||
            typeof record.markedBy !== 'string' || !['admin', 'member'].includes(record.source) ||
            !Number.isFinite(Date.parse(record.markedAt)) || resource.public_id !== idFor(date, record.name)) throw Error('Invalid attendance record');
        // Only the defined audit fields leave the storage layer.
        return { name: record.name, date: record.date, markedAt: record.markedAt, markedBy: record.markedBy, source: record.source };
    }
    async function find(date, name) {
        try { return decode(await cloudinary.api.resource(idFor(date, name), options), date); }
        catch (error) { if (error.http_code === 404) return null; throw error; }
    }
    return {
        async list(date, name) {
            if (name) { const record = await find(date, name); return record ? [record] : []; }
            const records = [];
            let cursor;
            do {
                const result = await cloudinary.api.resources({ ...options, prefix: `${prefix}/${date}/`, max_results: 500, ...(cursor ? { next_cursor: cursor } : {}) });
                records.push(...(result.resources || []).map(resource => decode(resource, date)));
                cursor = result.next_cursor;
            } while (cursor);
            return records.sort((a, b) => a.name.localeCompare(b.name, 'es'));
        },
        async mark(record) {
            const existing = await find(record.date, record.name);
            if (existing) return { duplicate: true, record: existing };
            let upload;
            try {
                upload = await cloudinary.uploader.upload(`data:application/json;base64,${Buffer.from(JSON.stringify(record)).toString('base64')}`, {
                    resource_type: 'raw', type: 'authenticated', public_id: idFor(record.date, record.name),
                    overwrite: false, context: { record: Buffer.from(JSON.stringify(record)).toString('base64url') }
                });
            } catch (error) {
                if (error.http_code !== 409) throw error;
                upload = { existing: true };
            }
            const canonical = await find(record.date, record.name);
            if (!canonical) throw Error('Attendance upload could not be confirmed');
            return { duplicate: Boolean(upload.existing), record: canonical };
        },
        async verify() {
            // Disposable diagnostic asset, outside all attendance and file lists.
            const probePrefix = `benm/attendance-probes/${crypto.randomUUID()}`;
            const probe = createCloudinaryStore(cloudinary, probePrefix);
            const record = { name: 'BENM_PROBE', date: '1970-01-01', markedAt: new Date().toISOString(), markedBy: 'BENM_PROBE', source: 'admin' };
            const id = `${probePrefix}/${record.date}/${crypto.createHash('sha256').update(attendanceIdentity(record.name)).digest('hex')}.json`;
            try {
                await probe.mark(record);
                const duplicate = await probe.mark({ ...record, markedAt: new Date().toISOString() });
                const records = await probe.list(record.date);
                if (!duplicate.duplicate || records.length !== 1 || records[0].markedAt !== record.markedAt) throw Error('Storage check failed');
            } finally {
                const removed = await cloudinary.uploader.destroy(id, { resource_type: 'raw', type: 'authenticated', invalidate: true });
                if (!['ok', 'not found'].includes(removed.result)) throw Error('Storage probe cleanup could not be confirmed');
            }
        }
    };
}
