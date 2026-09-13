// Check only the shipped Next route trace, without access to workspace dependencies.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  copyFile,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readlink,
  symlink,
} from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const app = fileURLToPath(new URL("..", import.meta.url));
const repository = resolve(app, "../..");
for (const route of ["image", "metadata"]) {
  const tracePath = join(
    app,
    `.next/server/app/api/media/${route}/route.js.nft.json`,
  );
  const trace = JSON.parse(await readFile(tracePath, "utf8"));
  const stage = await mkdtemp(join(tmpdir(), `memotrail-${route}-trace-`));
  for (const name of trace.files) {
    const source = resolve(dirname(tracePath), name);
    const local = relative(repository, source);
    assert(
      !local.startsWith(`..${sep}`) &&
        !local.split(sep).some((part) => part.startsWith(".env")),
    );
    const destination = join(stage, local);
    await mkdir(dirname(destination), { recursive: true });
    if ((await lstat(source)).isSymbolicLink()) {
      const link = await readlink(source);
      const target = relative(repository, resolve(dirname(source), link));
      assert(!target.startsWith(`..${sep}`));
      await symlink(
        relative(dirname(destination), join(stage, target)),
        destination,
      );
    } else {
      await copyFile(source, destination);
    }
  }
  const stagedApp = join(stage, relative(repository, app));
  const runtimeEntry = trace.files.find((name) =>
    name.endsWith("/media-runtime/index.cjs"),
  );
  assert(runtimeEntry, "Media runtime must remain an external traced module.");
  const entry = join(
    stage,
    relative(repository, resolve(dirname(tracePath), runtimeEntry)),
  );
  const require = createRequire(entry);
  const { sharpPath, exifrPath, heifPath } = require(entry).decoderPaths();
  const paths = [sharpPath, exifrPath, heifPath];
  const script = `
    const { Worker } = require('node:worker_threads');
    const worker = new Worker(\`
      const {parentPort,workerData}=require('node:worker_threads');
      (async()=>{
        const sharp=require(workerData[0]);
        const exifr=require(workerData[1]);
        const heif=await require(workerData[2]);
        if(typeof exifr.parse!=='function'||typeof heif.HeifDecoder!=='function')throw Error('Decoder missing');
        const bytes=await sharp({create:{width:2,height:3,channels:3,background:'#316652'}}).webp().toBuffer();
        const image=await sharp(bytes).metadata();
        if(image.width!==2||image.height!==3)throw Error('Preview invalid');
        parentPort.postMessage('passed');
      })().catch((error)=>{parentPort.postMessage({error:error.message});process.exitCode=1;});
    \`,{eval:true,env:{},execArgv:[],workerData:JSON.parse(process.argv[1])});
    let passed=false;
    worker.on('message',(message)=>{if(message==='passed')passed=true;else console.error(message.error);});
    worker.on('error',()=>{process.exitCode=1;});
    worker.on('exit',(code)=>{if(code||!passed)process.exitCode=1;});
  `;
  execFileSync(process.execPath, ["-e", script, JSON.stringify(paths)], {
    cwd: stagedApp,
    env: {},
    stdio: "inherit",
    timeout: 30_000,
  });
  console.log(
    `PASS: ${route} trace resolves and runs credential-free image dependencies outside the checkout.`,
  );
}
