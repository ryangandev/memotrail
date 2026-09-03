import type { InboxPhotoDraft } from "./inbox-photo";

const databaseName = "memotrail-capture";
const databaseVersion = 1;
const photoStoreName = "inbox-photo-drafts";

type StoredInboxPhoto = {
  blob: Blob;
  id: string;
  key: string;
  lastModified: number;
  mimeType: InboxPhotoDraft["mimeType"];
  name: string;
  ownerId: string;
  size: number;
};

export async function loadInboxPhotoDrafts(ownerId: string) {
  const database = await openDatabase();

  try {
    const transaction = database.transaction(photoStoreName, "readonly");
    const index = transaction.objectStore(photoStoreName).index("ownerId");
    const stored = await requestResult<StoredInboxPhoto[]>(
      index.getAll(IDBKeyRange.only(ownerId)),
    );
    await transactionFinished(transaction);

    return stored.flatMap((photo) => {
      if (photo.blob.size !== photo.size || photo.blob.size < 1) {
        return [];
      }

      const file = new File([photo.blob], photo.name, {
        lastModified: photo.lastModified,
        type: photo.mimeType,
      });
      return [{ file, id: photo.id, mimeType: photo.mimeType }];
    });
  } finally {
    database.close();
  }
}

export async function persistInboxPhotoDrafts(
  ownerId: string,
  photos: InboxPhotoDraft[],
) {
  const database = await openDatabase();

  try {
    const transaction = database.transaction(photoStoreName, "readwrite");
    const store = transaction.objectStore(photoStoreName);

    for (const photo of photos) {
      const stored: StoredInboxPhoto = {
        blob: photo.file,
        id: photo.id,
        key: photoKey(ownerId, photo.id),
        lastModified: photo.file.lastModified,
        mimeType: photo.mimeType,
        name: photo.file.name,
        ownerId,
        size: photo.file.size,
      };
      store.put(stored);
    }

    await transactionFinished(transaction);
  } finally {
    database.close();
  }
}

export async function removeInboxPhotoDrafts(
  ownerId: string,
  attachmentIds: string[],
) {
  if (attachmentIds.length === 0) {
    return;
  }

  const database = await openDatabase();

  try {
    const transaction = database.transaction(photoStoreName, "readwrite");
    const store = transaction.objectStore(photoStoreName);
    attachmentIds.forEach((id) => store.delete(photoKey(ownerId, id)));
    await transactionFinished(transaction);
  } finally {
    database.close();
  }
}

function photoKey(ownerId: string, attachmentId: string) {
  return `${ownerId}:${attachmentId}`;
}

function openDatabase() {
  if (typeof indexedDB === "undefined") {
    return Promise.reject(new Error("IndexedDB is unavailable."));
  }

  return new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(databaseName, databaseVersion);

    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(photoStoreName)) {
        const store = database.createObjectStore(photoStoreName, {
          keyPath: "key",
        });
        store.createIndex("ownerId", "ownerId", { unique: false });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () =>
      reject(request.error ?? new Error("IndexedDB failed."));
    request.onblocked = () => reject(new Error("IndexedDB is blocked."));
  });
}

function requestResult<T>(request: IDBRequest<T>) {
  return new Promise<T>((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () =>
      reject(request.error ?? new Error("IndexedDB request failed."));
  });
}

function transactionFinished(transaction: IDBTransaction) {
  return new Promise<void>((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () =>
      reject(transaction.error ?? new Error("IndexedDB transaction failed."));
    transaction.onabort = () =>
      reject(
        transaction.error ?? new Error("IndexedDB transaction was aborted."),
      );
  });
}
