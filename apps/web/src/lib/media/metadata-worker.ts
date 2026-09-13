import { Worker } from "node:worker_threads";
import { createRequire } from "node:module";
import "sharp";
import "exifr";
import { MEDIA_MAX_BYTES, MEDIA_MAX_PIXELS } from "./contracts";
import { normalizePhotoMetadata, type PhotoMetadata } from "./photo-metadata";
const runtimeRequire = createRequire(`${process.cwd()}/package.json`);
const source = String.raw`
const {parentPort,workerData}=require('node:worker_threads');
(async()=>{
  const sharp=require(workerData.sharpPath);
  const exifr=require(workerData.exifrPath);
  const bytes=Buffer.from(workerData.bytes);
  const jpeg=bytes[0]===255&&bytes[1]===216&&bytes[2]===255;
  const png=bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
  const webp=bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP';
  const heif=bytes.toString('ascii',4,8)==='ftyp'&&['heic','heix','hevc','hevx','mif1','msf1'].includes(bytes.toString('ascii',8,12));
  if(!jpeg&&!png&&!webp&&!heif)throw Error('Unsupported signature');
  const metadata=await sharp(bytes,{limitInputPixels:workerData.maxPixels}).metadata();
  if(!['jpeg','png','webp','heif'].includes(metadata.format)) throw Error('Unsupported image');
  if(!metadata.exif) return parentPort.postMessage({tags:{}});
  if(metadata.exif.length>1024*1024) throw Error('Metadata too large');
  const exif=metadata.exif;
  const tiff=exif.subarray(0,6).equals(Buffer.from([69,120,105,102,0,0]))?exif.subarray(6):exif;
  const tags=await exifr.parse(tiff,{reviveValues:false,translateValues:false,
    pick:['DateTimeOriginal','OffsetTimeOriginal','SubSecTimeOriginal','GPSLatitude','GPSLatitudeRef','GPSLongitude','GPSLongitudeRef'],
    ifd1:false,interop:false,makerNote:false,userComment:false,xmp:false,icc:false,iptc:false});
  parentPort.postMessage({tags:tags||{}});
})().catch(()=>parentPort.postMessage({error:true}));
`;
export async function readPhotoMetadata(
  bytes: Uint8Array,
  timeout = 5_000,
): Promise<PhotoMetadata> {
  if (!bytes.length || bytes.length > MEDIA_MAX_BYTES)
    throw new Error("Invalid photo");
  return new Promise((resolve, reject) => {
    const worker = new Worker(source, {
      eval: true,
      env: {},
      execArgv: [],
      resourceLimits: { maxOldGenerationSizeMb: 64 },
      workerData: {
        bytes,
        maxPixels: MEDIA_MAX_PIXELS,
        sharpPath: runtimeRequire.resolve("sharp"),
        exifrPath: runtimeRequire.resolve("exifr"),
      },
    });
    let finished = false;
    const finish = (tags?: Record<string, unknown>) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      void worker.terminate();
      if (tags) resolve(normalizePhotoMetadata(tags));
      else reject(new Error("Photo metadata unavailable"));
    };
    const timer = setTimeout(() => finish(), timeout);
    worker.once("error", () => finish());
    worker.once("exit", () => finish());
    worker.once("message", (message) =>
      finish(message.error ? undefined : message.tags),
    );
  });
}
