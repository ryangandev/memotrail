// Isolated decoder: no filesystem paths or network locations come from image data.
// The parent terminates this worker on timeout and caps concurrent allocations.
export const imageWorkerSource = String.raw`
const { parentPort, workerData } = require('node:worker_threads');
const sharp = require(workerData.sharpPath);
sharp.cache(false);
sharp.concurrency(1);
(async () => {
  const original = Buffer.from(workerData.bytes);
  const jpeg = original[0] === 255 && original[1] === 216 && original[2] === 255;
  const png = original.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
  const webp = original.toString('ascii',0,4) === 'RIFF' && original.toString('ascii',8,12) === 'WEBP';
  const heif = original.toString('ascii',4,8) === 'ftyp' && ['heic','heix','hevc','hevx','mif1','msf1'].includes(original.toString('ascii',8,12));
  if (!jpeg && !png && !webp && !heif) throw Error('Unsupported image signature');
  const opts = {limitInputPixels: workerData.maxPixels, failOn: 'error'};
  let input = original, raw;
  const metadata = await sharp(original, opts).metadata();
  if (!['jpeg','png','webp','heif'].includes(metadata.format)) throw Error('Unsupported image');
  if (!metadata.width || !metadata.height || metadata.width * metadata.height > workerData.maxPixels) throw Error('Image too large');
  if (metadata.format === 'heif' && metadata.compression === 'hevc') {
    const lib = await require(workerData.heifPath);
    const images = new lib.HeifDecoder().decode(original);
    try {
      const primary = images.find(image => image.is_primary()) || images[0];
      if (!primary) throw Error('No HEIF image');
      const width = primary.get_width(), height = primary.get_height();
      if (width < 1 || height < 1 || width * height > workerData.maxPixels) throw Error('Image too large');
      const decoded = await new Promise((resolve, reject) => {
        primary.display({data:new Uint8ClampedArray(width * height * 4),width,height}, result => result ? resolve(result) : reject(Error('Invalid HEIF')));
      });
      input = Buffer.from(decoded.data.buffer, decoded.data.byteOffset, decoded.data.byteLength);
      raw = {width,height,channels:4};
    } finally { for (const image of images) image.free(); }
  }
  const variants = [];
  for (const [variant, edge, quality] of [['display',1600,82],['thumbnail',400,76]]) {
    let image = sharp(input, raw ? {raw, ...opts} : opts);
    // libheif applies its container transforms; JPEG/TIFF EXIF is handled by sharp.
    if (!raw) image = image.autoOrient();
    const result = await image.resize(edge,edge,{fit:'inside',withoutEnlargement:true}).webp({quality,effort:4}).toBuffer({resolveWithObject:true});
    variants.push({variant,bytes:result.data,width:result.info.width,height:result.info.height});
  }
  parentPort.postMessage({variants});
})().catch(() => parentPort.postMessage({error:'Image preview could not be generated.'}));
`;
