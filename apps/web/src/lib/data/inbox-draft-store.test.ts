import { describe, expect, it, vi } from "vitest";
import {
  inboxDraftKey,
  loadInboxDraft,
  persistInboxDraft,
} from "./inbox-draft";
import {
  changedElsewhereVoiceMessage,
  createInboxDraftStore,
  photoDraftsUnavailableMessage,
  type InboxDraftPhotoStorage,
} from "./inbox-draft-store";
import type { InboxPhotoDraft } from "./inbox-photo";
import { createEntryRichText, plainTextDocument } from "./rich-text";
import type {
  BrowserSpeechRecognition,
  BrowserSpeechRecognitionEvent,
} from "./voice-transcript";

const ownerId = "owner-a";
const occurrence = {
  precision: "year" as const,
  start: "2019",
  end: "",
  label: "",
  timezone: "UTC",
};

describe("Shared capture draft", () => {
  it("reads the stored draft lazily and keeps server rendering empty", () => {
    const storage = memoryStorage();
    persistInboxDraft(storage, ownerId, {
      body: "Kept from yesterday",
      bodyRich: null,
      occurredAt: null,
      occurrence,
      title: "",
    });
    storage.getItem.mockClear();
    const { store } = setup({ storage });

    expect(storage.getItem).not.toHaveBeenCalled();
    expect(store.getServerSnapshot()).toMatchObject({
      body: "",
      hasLocalDraft: false,
      isReady: false,
    });
    expect(store.getSnapshot()).toMatchObject({
      body: "Kept from yesterday",
      hasLocalDraft: true,
      isReady: true,
      occurrence,
      photoState: "loading",
    });
    expect(store.getSnapshot()).toBe(store.getSnapshot());
  });

  it("restores an older exact date as an exact occurrence", () => {
    const storage = memoryStorage();
    storage.setItem(
      inboxDraftKey(ownerId),
      JSON.stringify({
        body: "An older draft",
        occurredAt: "2020-02-03T04:05:00.000Z",
        title: "",
        updatedAt: "2020-02-03T04:05:00.000Z",
        version: 2,
      }),
    );
    const { store } = setup({ storage });

    expect(store.getSnapshot().occurrence).toMatchObject({
      precision: "exact",
      start: "2020-02-03T04:05:00",
      timezone: "UTC",
    });
  });

  it("shows every edit to all composers and keeps it on this device", () => {
    const { storage, store } = setup();
    const composers = [vi.fn(), vi.fn()];
    for (const composer of composers) store.subscribe(composer);
    const rich = createEntryRichText(plainTextDocument("A shared thought"))!;

    store.update({ body: rich.text, bodyRich: rich });
    store.update({ occurrence });

    for (const composer of composers) expect(composer).toHaveBeenCalledTimes(2);
    expect(store.getSnapshot()).toMatchObject({
      body: "A shared thought",
      bodyRich: rich,
      hasLocalDraft: true,
      occurrence,
      revision: 2,
    });
    expect(loadInboxDraft(storage, ownerId)).toMatchObject({
      body: "A shared thought",
      bodyRich: rich,
      occurrence,
    });

    // A plain-text change cannot keep formatting written for other text.
    store.update({ body: "Plain words" });
    expect(store.getSnapshot().bodyRich).toBeNull();
    store.update({ body: "", occurrence: null });
    expect(store.getSnapshot().hasLocalDraft).toBe(false);
    expect(loadInboxDraft(storage, ownerId)).toBeNull();
  });

  it("clears the draft everywhere once its capture is queued", async () => {
    const { photoStorage, photosChanged, storage, store } = setup();
    await store.loadPhotos();
    store.update({ body: "Saved once", occurrence });
    await store.addPhotos([photo("photo-1")]);
    photosChanged.mockClear();
    const revision = store.getSnapshot().revision;

    store.clear();

    expect(store.getSnapshot()).toMatchObject({
      body: "",
      bodyRich: null,
      hasLocalDraft: false,
      occurrence: null,
      photos: [],
      revision: revision + 1,
    });
    expect(loadInboxDraft(storage, ownerId)).toBeNull();
    // The queued capture still needs its photo, and other tabs drop it.
    expect(photoStorage.remove).not.toHaveBeenCalled();
    expect(photoStorage.stored.has("photo-1")).toBe(true);
    expect(photosChanged).toHaveBeenCalledTimes(1);
  });

  it("loads stored photos once, leaving out those of queued captures", async () => {
    const queued = new Set(["queued-photo"]);
    const { photoStorage, store } = setup({ queuedPhotoIds: () => queued });
    photoStorage.stored.set("draft-photo", photo("draft-photo"));
    photoStorage.stored.set("queued-photo", photo("queued-photo"));

    await Promise.all([store.loadPhotos(), store.loadPhotos()]);
    await store.loadPhotos();

    expect(photoStorage.load).toHaveBeenCalledTimes(1);
    expect(store.getSnapshot()).toMatchObject({
      hasLocalDraft: true,
      photoState: "ready",
      photos: [{ id: "draft-photo" }],
    });
  });

  it("reports photo drafts unavailable until the draft changes", async () => {
    const { photoStorage, store } = setup();
    photoStorage.load.mockRejectedValueOnce(new Error("blocked"));

    await store.loadPhotos();

    const snapshot = store.getSnapshot();
    expect(snapshot.photoState).toBe("unavailable");
    expect(snapshot.notice).toEqual({
      isError: true,
      message: photoDraftsUnavailableMessage,
      revision: snapshot.revision,
    });
    store.update({ body: "Text still works" });
    expect(store.getSnapshot().revision).not.toBe(snapshot.revision);
  });

  it("keeps added photos before showing them and announces each change", async () => {
    const { photoStorage, photosChanged, store } = setup();
    await store.loadPhotos();

    await store.addPhotos([photo("photo-1"), photo("photo-2")]);
    expect(photoStorage.stored.size).toBe(2);
    expect(store.getSnapshot().photos.map(({ id }) => id)).toEqual([
      "photo-1",
      "photo-2",
    ]);
    await store.removePhoto("photo-1");

    expect(photoStorage.stored.has("photo-1")).toBe(false);
    expect(store.getSnapshot()).toMatchObject({
      hasLocalDraft: true,
      photos: [{ id: "photo-2" }],
    });
    expect(photosChanged).toHaveBeenCalledTimes(2);

    photoStorage.persist.mockRejectedValueOnce(new Error("quota"));
    await expect(store.addPhotos([photo("photo-3")])).rejects.toThrow("quota");
    expect(store.getSnapshot()).toMatchObject({
      photoState: "unavailable",
      photos: [{ id: "photo-2" }],
    });
    expect(photosChanged).toHaveBeenCalledTimes(2);
  });

  it("follows writing that another tab changed or cleared", () => {
    const { storage, store } = setup();
    store.update({ body: "Written here" });
    const listener = vi.fn();
    store.subscribe(listener);

    store.reload();
    expect(listener).not.toHaveBeenCalled();

    persistInboxDraft(storage, ownerId, {
      body: "Written in another tab",
      bodyRich: null,
      occurredAt: null,
      occurrence: null,
      title: "",
    });
    store.reload();
    expect(store.getSnapshot()).toMatchObject({
      body: "Written in another tab",
      hasLocalDraft: true,
    });

    storage.removeItem(inboxDraftKey(ownerId));
    store.reload();
    expect(store.getSnapshot()).toMatchObject({
      body: "",
      hasLocalDraft: false,
    });
    expect(listener).toHaveBeenCalledTimes(2);
  });

  it("drops photos that another tab queued and rereads a stale photo read", async () => {
    const queued = new Set<string>();
    const { photoStorage, store } = setup({ queuedPhotoIds: () => queued });
    photoStorage.stored.set("shared", photo("shared"));
    await store.loadPhotos();
    expect(store.getSnapshot().photos).toHaveLength(1);

    // The other tab queued its capture with this photo.
    queued.add("shared");
    await store.reloadPhotos();
    expect(store.getSnapshot()).toMatchObject({
      hasLocalDraft: false,
      photos: [],
    });

    // A read that started before this tab added a photo must not hide it.
    const slowRead = deferred<InboxPhotoDraft[]>();
    photoStorage.load.mockImplementationOnce(() => slowRead.promise);
    const reread = store.reloadPhotos();
    await store.addPhotos([photo("added")]);
    slowRead.resolve([]);
    await reread;

    // The first load, the queued reload, the stale read, and its reread.
    expect(photoStorage.load).toHaveBeenCalledTimes(4);
    expect(store.getSnapshot().photos.map(({ id }) => id)).toEqual(["added"]);
  });

  it("shares voice capture with every composer", () => {
    const { recognitions, storage, store } = setup();
    store.update({ body: "Before speaking" });

    store.startVoice();
    const session = recognitions[0]!;
    expect(session.start).toHaveBeenCalledTimes(1);
    expect(store.getSnapshot()).toMatchObject({
      voice: "listening",
      voiceNotice: { isError: false },
    });

    session.say("first words");
    expect(store.getSnapshot()).toMatchObject({
      body: "Before speaking\nfirst words",
      bodyRich: null,
      voice: "listening",
      voiceNotice: {
        message: "Listening… Tap Stop when done. Audio is not saved.",
      },
    });
    expect(loadInboxDraft(storage, ownerId)?.body).toBe(
      "Before speaking\nfirst words",
    );

    store.stopVoice();
    expect(store.getSnapshot().voice).toBe("stopping");
    session.onend?.();
    expect(store.getSnapshot()).toMatchObject({
      voice: "idle",
      voiceNotice: { message: "Transcription added to this draft." },
    });

    // Any other edit dismisses the voice message.
    store.update({ body: "Edited" });
    expect(store.getSnapshot().voiceNotice).toBeNull();
  });

  it("ends voice capture when its composer closes or the draft is saved", () => {
    const { recognitions, store } = setup();

    store.startVoice();
    recognitions[0]!.say("kept words");
    store.cancelVoice();
    expect(recognitions[0]!.abort).toHaveBeenCalledTimes(1);
    expect(recognitions[0]!.onresult).toBeNull();
    expect(store.getSnapshot()).toMatchObject({
      body: "kept words",
      voice: "idle",
      voiceNotice: { message: "Transcription added to this draft." },
    });

    store.startVoice();
    store.clear();
    expect(recognitions[1]!.abort).toHaveBeenCalledTimes(1);
    expect(store.getSnapshot()).toMatchObject({
      body: "",
      voice: "idle",
      voiceNotice: null,
    });
  });

  it("stops voice capture rather than overwrite another tab's change", () => {
    const { recognitions, storage, store } = setup();
    store.startVoice();
    recognitions[0]!.say("spoken here");

    persistInboxDraft(storage, ownerId, {
      body: "Typed in another tab",
      bodyRich: null,
      occurredAt: null,
      occurrence: null,
      title: "",
    });
    store.reload();

    expect(recognitions[0]!.abort).toHaveBeenCalledTimes(1);
    expect(store.getSnapshot()).toMatchObject({
      body: "Typed in another tab",
      voice: "idle",
      voiceNotice: { isError: true, message: changedElsewhereVoiceMessage },
    });
  });

  it("explains when voice capture cannot start", () => {
    const unsupported = setup({ speechRecognition: () => null });
    unsupported.store.startVoice();
    expect(unsupported.store.getSnapshot()).toMatchObject({
      voice: "idle",
      voiceNotice: { isError: true },
    });

    const full = setup();
    full.store.update({ body: "x".repeat(50_000) });
    full.store.startVoice();
    expect(full.recognitions).toHaveLength(0);
    expect(full.store.getSnapshot().voiceNotice).toEqual({
      isError: true,
      message: "This note has reached the 50,000 character limit.",
    });
  });
});

type FakeRecognition = BrowserSpeechRecognition & {
  abort: ReturnType<typeof vi.fn>;
  say: (transcript: string) => void;
  start: ReturnType<typeof vi.fn>;
  stop: ReturnType<typeof vi.fn>;
};

function setup({
  queuedPhotoIds = () => new Set<string>(),
  speechRecognition,
  storage = memoryStorage(),
}: {
  queuedPhotoIds?: () => ReadonlySet<string>;
  speechRecognition?: () => null;
  storage?: ReturnType<typeof memoryStorage>;
} = {}) {
  const photoStorage = memoryPhotoStorage();
  const recognitions: FakeRecognition[] = [];
  class Recognition implements BrowserSpeechRecognition {
    continuous = false;
    interimResults = false;
    lang = "";
    onend: (() => void) | null = null;
    onerror: BrowserSpeechRecognition["onerror"] = null;
    onresult: BrowserSpeechRecognition["onresult"] = null;
    abort = vi.fn();
    start = vi.fn();
    stop = vi.fn();
    say(transcript: string) {
      const event: BrowserSpeechRecognitionEvent = {
        results: [[{ transcript }]],
      };
      this.onresult?.(event);
    }
    constructor() {
      recognitions.push(this);
    }
  }
  const store = createInboxDraftStore({
    ownerId,
    photoStorage,
    queuedPhotoIds,
    speechRecognition: speechRecognition ?? (() => Recognition),
    storage,
  });
  const photosChanged = vi.fn();
  store.onPhotosChanged(photosChanged);
  return { photoStorage, photosChanged, recognitions, storage, store };
}

function photo(id: string): InboxPhotoDraft {
  return {
    file: new File(["photo"], `${id}.png`, { type: "image/png" }),
    id,
    mimeType: "image/png",
  };
}

function memoryPhotoStorage() {
  const stored = new Map<string, InboxPhotoDraft>();
  return {
    stored,
    load: vi.fn<InboxDraftPhotoStorage["load"]>(async () => [
      ...stored.values(),
    ]),
    persist: vi.fn<InboxDraftPhotoStorage["persist"]>(async (_, photos) => {
      for (const photo of photos) stored.set(photo.id, photo);
    }),
    remove: vi.fn<InboxDraftPhotoStorage["remove"]>(async (_, ids) => {
      for (const id of ids) stored.delete(id);
    }),
  };
}

function memoryStorage() {
  const values = new Map<string, string>();

  return {
    getItem: vi.fn((key: string) => values.get(key) ?? null),
    removeItem: vi.fn((key: string) => {
      values.delete(key);
    }),
    setItem: vi.fn((key: string, value: string) => {
      values.set(key, value);
    }),
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
