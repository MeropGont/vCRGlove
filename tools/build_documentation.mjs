import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);
const date = args[args.indexOf('--date') + 1];
if (!args.includes('--date') || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error('Usage: node tools/build_documentation.mjs --date YYYY-MM-DD [--check]');
}
const runtime = path.resolve(path.dirname(process.execPath), '../..');
const modules = process.env.CODEX_NODE_MODULES ?? path.join(runtime, 'node/node_modules');
const python = process.env.CODEX_PYTHON ?? path.join(runtime, 'python/bin/python3');
const require = createRequire(import.meta.url);
const {marked} = await import(pathToFileURL(require.resolve('marked', {paths: [modules]})).href);
const files = ['README.md', 'docs/README.md', 'docs/DEVELOPMENT_GUIDE.md',
    'docs/DATA_FORMATS.md', 'docs/RELEASE_CHECKLIST.md', 'Testing/vCRGlove_testing_checklist.md'];
const hash = createHash('sha256');
const chapters = [];
for (const file of files) {
    const text = await fs.readFile(path.join(root, file), 'utf8');
    hash.update(file + '\0' + text + '\0');
    chapters.push({file, tokens: marked.lexer(text)});
}
const sourceHash = hash.digest('hex');
const output = path.join(root, 'docs/vCRGlove_Handbook.pdf');
const renderer = path.join(root, 'tools/render_documentation.py');
let directory;
try {
    let options;
    if (args.includes('--check')) {
        options = [renderer, '--check', output, sourceHash];
    } else {
        directory = await fs.mkdtemp(path.join(os.tmpdir(), 'vcr-handbook-'));
        const manifest = path.join(directory, 'chapters.json');
        await fs.writeFile(manifest, JSON.stringify({date, sourceHash, chapters}));
        options = [renderer, manifest, output];
    }
    const result = spawnSync(python, options, {stdio: 'inherit'});
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`PDF renderer failed (${result.status})`);
} finally {
    if (directory) await fs.rm(directory, {recursive: true, force: true});
}
