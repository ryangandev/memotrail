import { Readable, Writable } from "node:stream";
import yauzl from "yauzl";
import { importLimits } from "./limits";

/** Why an archive could not be read, as a stable code the page turns into words. */
export type ImportErrorCode =
  | "unsupported_archive"
  | "encrypted_archive"
  | "too_many_files"
  | "archive_too_large"
  | "compression_ratio"
  | "file_too_large"
  | "storage_unavailable"
  | "too_large"
  | "empty_import"
  | "too_many_entries"
  | "too_many_photos"
  | "unsupported_source";

export class ImportError extends Error {
  constructor(
    public code: ImportErrorCode,
    message?: string,
  ) {
    super(message ?? code);
  }
}

/** Where the bytes of a ZIP come from: a Storage object read by ranges, or memory. */
export type RangeSource = {
  size: number;
  /** Bytes from start up to, not including, end. */
  read(start: number, end: number): Promise<Buffer>;
};

export function bufferSource(buffer: Buffer): RangeSource {
  return {
    read: async (start, end) => buffer.subarray(start, end),
    size: buffer.length,
  };
}

const blockSize = 4 * 1024 * 1024;
const cachedBlocks = 8;

/**
 * A random access reader for yauzl over ranged reads. Only the end of the file (the central
 * directory) and the members a scan asks for are fetched, in blocks of a few megabytes that
 * many small notes share, so memory stays flat however large the archive is.
 */
class BlockCachedReader extends yauzl.RandomAccessReader {
  private blocks = new Map<number, Promise<Buffer>>();
  constructor(private source: RangeSource) {
    super();
  }

  private block(index: number): Promise<Buffer> {
    const existing = this.blocks.get(index);
    if (existing) {
      // Most recently used goes last.
      this.blocks.delete(index);
      this.blocks.set(index, existing);
      return existing;
    }
    const start = index * blockSize;
    const end = Math.min(start + blockSize, this.source.size);
    const loading = this.source.read(start, end);
    this.blocks.set(index, loading);
    loading.catch(() => this.blocks.delete(index));
    while (this.blocks.size > cachedBlocks) {
      const oldest = this.blocks.keys().next().value;
      if (oldest === undefined) break;
      this.blocks.delete(oldest);
    }
    return loading;
  }

  _readStreamForRange(start: number, end: number): Readable {
    let position = start;
    const block = (index: number) => this.block(index);
    return new Readable({
      read() {
        if (position >= end) {
          this.push(null);
          return;
        }
        const index = Math.floor(position / blockSize);
        block(index).then(
          (data) => {
            const offset = position - index * blockSize;
            const slice = data.subarray(
              offset,
              Math.min(data.length, offset + (end - position)),
            );
            if (slice.length === 0) {
              this.destroy(new Error("The archive ended early."));
              return;
            }
            position += slice.length;
            this.push(slice);
          },
          (error) => this.destroy(error),
        );
      },
    });
  }
}

export type ZipMember = {
  /** Slash separated, Unicode normalized (NFC), with no leading slash. */
  path: string;
  /** The nested ZIP the member lives in, when the export is a ZIP of ZIPs. */
  container?: string;
  size: number;
  compressedSize: number;
  modified: Date | null;
  /** Position in its archive, so reads can go in file order and share cached blocks. */
  offset: number;
};

type Container = {
  zip: yauzl.ZipFile;
  entries: Map<string, yauzl.Entry>;
};

const ignoredNames = new Set([".ds_store", "thumbs.db", "desktop.ini"]);

function cleanPath(name: string): string | null {
  const normalized = name.replaceAll("\\", "/").normalize("NFC");
  const segments = normalized
    .split("/")
    .filter((segment) => segment !== "" && segment !== ".");
  if (segments.length === 0 || segments.includes("..")) return null;
  return segments.join("/");
}

function ignoredMember(path: string) {
  const segments = path.split("/");
  const name = segments.at(-1)!.toLowerCase();
  return (
    segments[0] === "__MACOSX" ||
    ignoredNames.has(name) ||
    name.startsWith("._")
  );
}

function openYauzl(
  input: Buffer | { reader: BlockCachedReader; size: number },
): Promise<yauzl.ZipFile> {
  const options = {
    autoClose: false,
    decodeStrings: true,
    lazyEntries: true,
    validateEntrySizes: true,
  };
  return new Promise((resolve, reject) => {
    const done = (error: Error | null, zip?: yauzl.ZipFile) =>
      error || !zip
        ? reject(new ImportError("unsupported_archive", error?.message))
        : resolve(zip);
    if (Buffer.isBuffer(input)) yauzl.fromBuffer(input, options, done);
    else yauzl.fromRandomAccessReader(input.reader, input.size, options, done);
  });
}

function listEntries(zip: yauzl.ZipFile): Promise<yauzl.Entry[]> {
  return new Promise((resolve, reject) => {
    const entries: yauzl.Entry[] = [];
    zip.on("entry", (entry: yauzl.Entry) => {
      entries.push(entry);
      if (entries.length > importLimits.maxZipMembers) {
        reject(new ImportError("too_many_files"));
        return;
      }
      zip.readEntry();
    });
    zip.once("end", () => resolve(entries));
    zip.once("error", (error) =>
      reject(new ImportError("unsupported_archive", error.message)),
    );
    zip.readEntry();
  });
}

const contentExtension = /\.(md|markdown|txt|html?|csv|json)$/i;

/**
 * An export ZIP read in place. Opening lists the members of the central directory and
 * applies the safety rules; reading a member decompresses only that member, with a cap.
 */
export class ZipArchive {
  readonly members: ZipMember[] = [];
  private containers = new Map<string, Container>();
  private byKey = new Map<string, ZipMember>();

  static async open(input: Buffer | RangeSource): Promise<ZipArchive> {
    const archive = new ZipArchive();
    const root = Buffer.isBuffer(input)
      ? input
      : { reader: new BlockCachedReader(input), size: input.size };
    await archive.addContainer("", root);
    await archive.expandNested();
    return archive;
  }

  private async addContainer(
    name: string,
    input: Buffer | { reader: BlockCachedReader; size: number },
  ) {
    const zip = await openYauzl(input);
    zip.on("error", () => {});
    let entries: yauzl.Entry[];
    try {
      entries = await listEntries(zip);
    } catch (error) {
      zip.close();
      throw error;
    }
    const container: Container = { entries: new Map(), zip };
    this.containers.set(name, container);
    let declared = 0;
    for (const entry of entries) {
      const path = cleanPath(entry.fileName);
      if (!path || entry.fileName.endsWith("/")) continue;
      // The high bits of the external attributes hold the Unix file type; 0xA000 is a symlink.
      if (((entry.externalFileAttributes >>> 16) & 0xf000) === 0xa000) continue;
      if (ignoredMember(path)) continue;
      if (entry.isEncrypted()) throw new ImportError("encrypted_archive");
      declared += entry.uncompressedSize;
      if (declared > importLimits.maxUncompressedBytes)
        throw new ImportError("archive_too_large");
      if (
        entry.uncompressedSize > importLimits.ratioCheckMinBytes &&
        entry.uncompressedSize / Math.max(entry.compressedSize, 1) >
          importLimits.maxCompressionRatio
      )
        throw new ImportError("compression_ratio");
      if (container.entries.has(path)) continue;
      container.entries.set(path, entry);
      const member: ZipMember = {
        compressedSize: entry.compressedSize,
        ...(name ? { container: name } : {}),
        modified: safeDate(entry),
        offset: entry.relativeOffsetOfLocalHeader,
        path,
        size: entry.uncompressedSize,
      };
      this.members.push(member);
      this.byKey.set(memberKey(member.path, name), member);
    }
    if (this.members.length > importLimits.maxZipMembers)
      throw new ImportError("too_many_files");
  }

  /** An export of part ZIPs holds nothing but ZIPs; those are opened one level deep. */
  private async expandNested() {
    const top = this.members.filter((member) => !member.container);
    const zips = top.filter((member) => /\.zip$/i.test(member.path));
    if (
      zips.length === 0 ||
      top.some((member) => contentExtension.test(member.path))
    )
      return;
    for (const member of zips) {
      if (member.size > importLimits.maxNestedZipBytes)
        throw new ImportError("archive_too_large");
      const bytes = await this.readBuffer(
        member,
        importLimits.maxNestedZipBytes,
      );
      await this.addContainer(member.path, bytes);
    }
    // The nested archives replace the ZIPs that held them.
    const kept = this.members.filter(
      (member) => member.container || !zips.includes(member),
    );
    this.members.length = 0;
    this.members.push(...kept);
  }

  find(path: string, container?: string): ZipMember | undefined {
    return this.byKey.get(memberKey(path.normalize("NFC"), container ?? ""));
  }

  /** The member's decompressed bytes, refusing more than maxBytes. */
  async readBuffer(member: ZipMember, maxBytes: number): Promise<Buffer> {
    if (member.size > maxBytes) throw new ImportError("file_too_large");
    const chunks: Buffer[] = [];
    let total = 0;
    await this.pipe(member, (chunk) => {
      total += chunk.length;
      if (total > maxBytes) throw new ImportError("file_too_large");
      chunks.push(chunk);
    });
    return Buffer.concat(chunks);
  }

  async readText(member: ZipMember, maxBytes: number): Promise<string> {
    const bytes = await this.readBuffer(member, maxBytes);
    // A byte order mark would end up in the first heading.
    const start =
      bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf ? 3 : 0;
    return bytes.toString("utf8", start);
  }

  /** The first bytes of a member, for telling a photo from a renamed file. */
  async readHead(member: ZipMember, bytes: number): Promise<Buffer> {
    const chunks: Buffer[] = [];
    let total = 0;
    const stop = new Error("enough");
    try {
      await this.pipe(member, (chunk) => {
        chunks.push(chunk);
        total += chunk.length;
        if (total >= bytes) throw stop;
      });
    } catch (error) {
      if (error !== stop) throw error;
    }
    return Buffer.concat(chunks).subarray(0, bytes);
  }

  /** Streams a member into a callback. The callback throwing stops the read. */
  private pipe(
    member: ZipMember,
    onChunk: (chunk: Buffer) => void,
  ): Promise<void> {
    const container = this.containers.get(member.container ?? "");
    const entry = container?.entries.get(member.path);
    if (!container || !entry) throw new ImportError("unsupported_archive");
    return new Promise((resolve, reject) => {
      container.zip.openReadStream(entry, (error, stream) => {
        if (error || !stream) {
          reject(new ImportError("unsupported_archive", error?.message));
          return;
        }
        const sink = new Writable({
          write(chunk: Buffer, _encoding, callback) {
            try {
              onChunk(chunk);
              callback();
            } catch (thrown) {
              callback(thrown as Error);
            }
          },
        });
        stream.on("error", (streamError) => {
          sink.destroy();
          reject(streamError);
        });
        stream.pipe(sink);
        sink.on("finish", resolve);
        sink.on("error", (sinkError) => {
          stream.destroy();
          reject(sinkError);
        });
      });
    });
  }

  close() {
    for (const container of this.containers.values()) container.zip.close();
    this.containers.clear();
  }
}

function memberKey(path: string, container: string) {
  return `${container}\u0000${path}`;
}

function safeDate(entry: yauzl.Entry): Date | null {
  try {
    const date = entry.getLastModDate();
    return Number.isFinite(date.getTime()) ? date : null;
  } catch {
    return null;
  }
}

/** The bytes a ZIP starts with. A file that does not is not a ZIP. */
export function looksLikeZip(head: Uint8Array) {
  return (
    head.length >= 4 &&
    head[0] === 0x50 &&
    head[1] === 0x4b &&
    (head[2] === 0x03 || head[2] === 0x05 || head[2] === 0x07) &&
    (head[3] === 0x04 || head[3] === 0x06 || head[3] === 0x08)
  );
}
