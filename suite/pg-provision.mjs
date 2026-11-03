// Native mode only: create (or drop) the Workbench's PostgreSQL role and database.
// Connection settings come from the environment (PGHOST, PGPORT, PGUSER, PGPASSWORD for the administrator;
// WB_DIR, WB_ROLE, WB_DB, WB_ROLE_PASSWORD). Nothing is printed except a one-line JSON result.
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(path.join(process.env.WB_DIR || '.', 'package.json'));
const { Client } = require('pg');
const mode = process.argv[2];
const role = process.env.WB_ROLE || '';
const db = process.env.WB_DB || '';
const name = /^[a-z_][a-z0-9_]{0,40}$/;
if (!['create', 'drop'].includes(mode) || !name.test(role) || !name.test(db)) {
  console.error('usage: pg-provision.mjs create|drop (WB_ROLE / WB_DB must be simple lower-case names)');
  process.exit(2);
}
const ident = (value) => '"' + value + '"';
const admin = new Client({
  host: process.env.PGHOST || '127.0.0.1',
  port: Number(process.env.PGPORT || 5432),
  user: process.env.PGUSER || 'postgres',
  password: process.env.PGPASSWORD,
  database: 'postgres',
});
try {
  await admin.connect();
  if (mode === 'create') {
    const password = process.env.WB_ROLE_PASSWORD || '';
    if (!/^[A-Za-z0-9_-]{24,}$/.test(password)) throw new Error('WB_ROLE_PASSWORD must be a generated random value');
    const literal = "'" + password + "'";
    const existingRole = await admin.query('SELECT 1 FROM pg_roles WHERE rolname=$1', [role]);
    await admin.query(`${existingRole.rowCount ? 'ALTER' : 'CREATE'} ROLE ${ident(role)} LOGIN PASSWORD ${literal}`);
    const existingDb = await admin.query('SELECT 1 FROM pg_database WHERE datname=$1', [db]);
    if (!existingDb.rowCount) await admin.query(`CREATE DATABASE ${ident(db)} OWNER ${ident(role)}`);
    console.log(JSON.stringify({ ok: true, role_existed: Boolean(existingRole.rowCount), database_existed: Boolean(existingDb.rowCount) }));
  } else {
    await admin.query(`DROP DATABASE IF EXISTS ${ident(db)} WITH (FORCE)`);
    await admin.query(`DROP ROLE IF EXISTS ${ident(role)}`);
    console.log(JSON.stringify({ ok: true }));
  }
} catch (error) {
  // Error codes only: never echo connection strings or passwords.
  console.error(JSON.stringify({ ok: false, code: error.code || error.name || 'error' }));
  process.exitCode = 1;
} finally {
  await admin.end().catch(() => {});
}
