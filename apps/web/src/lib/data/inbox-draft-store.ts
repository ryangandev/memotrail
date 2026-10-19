import { entryBodyLimit } from "./inbox-input";
import {
  clearInboxDraft,
  persistInboxDraft,
  readInboxDraft,
  type DraftStorage,
} from "./inbox-draft";
import type { InboxPhotoDraft } from "./inbox-photo";
import { occurrenceDraft, type OccurrenceDraft } from "./occurrence";
import type { EntryRichText } from "./rich-text";
import {
  browserVoiceTranscript,
  mergeVoiceTranscript,
  voiceRecognitionErrorMessage,
  type BrowserSpeechRecognition,
  type BrowserSpeechRecognitionConstructor,
} from "./voice-transcript";

/** The writing and date of the capture being composed. */
export type InboxDraftValues = {
  body: string;
  bodyRich: EntryRichText | null;
  occurrence: OccurrenceDraft | null;
  title: string;
};

export type InboxDraftNotice = {
  isError: boolean;
  message: string;
};

export type InboxDraftVoiceState = "idle" | "listening" | "stopping";

export type InboxDraftSnapshot = InboxDraftValues & {
  /** False until this browser's draft has been read. */
  isReady: boolean;
  /** Whether this device keeps the draft: stored writing or a photo. */
  hasLocalDraft: boolean;
  photos: readonly InboxPhotoDraft[];
  /** Photos are read separately; "unavailable" means this browser cannot keep them. */
  photoState: "loading" | "ready" | "unavailable";
  /**
   * Increases whenever the writing, date, or photos change, so a composer can
   * dismiss a message that described an earlier draft.
   */
  revision: number;
  /** A problem with the draft itself, shown until the draft next changes. */
  notice: (InboxDraftNotice & { revision: number }) | null;
  voice: InboxDraftVoiceState;
  voiceNotice: InboxDraftNotice | null;
};

/** Where photo drafts live; queued captures keep their photos there too. */
export type InboxDraftPhotoStorage = {
  load: (ownerId: string) => Promise<InboxPhotoDraft[]>;
  persist: (ownerId: string, photos: InboxPhotoDraft[]) => Promise<void>;
  remove: (ownerId: string, photoIds: string[]) => Promise<void>;
};

export type InboxDraftStore = {
  /** Keeps photos on this device first, then adds them to the draft. */
  addPhotos: (photos: InboxPhotoDraft[]) => Promise<void>;
  /** Ends voice capture without waiting for its last words. */
  cancelVoice: () => void;
  /** Empties the draft once its capture is queued; queued photos stay stored. */
  clear: () => void;
  getServerSnapshot: () => InboxDraftSnapshot;
  getSnapshot: () => InboxDraftSnapshot;
  /** Reads photo drafts the first time; later calls share that read. */
  loadPhotos: () => Promise<void>;
  /** Runs after this tab adds, removes, or queues draft photos. */
  onPhotosChanged: (listener: () => void) => () => void;
  /** Rereads the writing and date after another tab changed them. */
  reload: () => void;
  /** Rereads photo drafts after another tab changed them. */
  reloadPhotos: () => Promise<void>;
  removePhoto: (photoId: string) => Promise<void>;
  startVoice: () => void;
  stopVoice: () => void;
  subscribe: (listener: () => void) => () => void;
  update: (changes: Partial<InboxDraftValues>) => void;
};

export const photoDraftsUnavailableMessage =
  "Photo drafts are unavailable in this browser. Text capture still works.";
export const unrestoredDraftMessage =
  "Some of your saved draft could not be restored. The original stays on this device.";
export const unreadableDraftMessage =
  "Your saved draft could not be read. The original stays on this device.";
export const changedElsewhereVoiceMessage =
  "Voice capture stopped because this draft changed in another tab.";

const emptyValues: InboxDraftValues = {
  body: "",
  bodyRich: null,
  occurrence: null,
  title: "",
};

const serverSnapshot: InboxDraftSnapshot = {
  ...emptyValues,
  hasLocalDraft: false,
  isReady: false,
  notice: null,
  photoState: "loading",
  photos: [],
  revision: 0,
  voice: "idle",
  voiceNotice: null,
};

/**
 * Owns one person's capture draft in this browser tab, so every composer
 * shows and edits the same writing, date, photos, and voice capture. The
 * writing is kept in `storage` and the photos in `photoStorage`; changes that
 * other tabs make are reread through `reload` and `reloadPhotos`.
 */
export function createInboxDraftStore({
  language = () => "en-US",
  ownerId,
  photoStorage,
  queuedPhotoIds,
  speechRecognition = () => null,
  storage,
  timezone = () => "UTC",
}: {
  language?: () => string;
  ownerId: string;
  photoStorage: InboxDraftPhotoStorage;
  /** Stored photos that belong to queued captures rather than to the draft. */
  queuedPhotoIds: () => ReadonlySet<string>;
  speechRecognition?: () => BrowserSpeechRecognitionConstructor | null;
  storage: DraftStorage;
  timezone?: () => string;
}): InboxDraftStore {
  let snapshot = serverSnapshot;
  let isLoaded = false;
  let hasStoredWriting = false;
  let hasReadPhotos = false;
  let photoRead: Promise<void> | null = null;
  // Counts photo changes, so a slower read cannot undo a newer change.
  let photoGeneration = 0;
  let recognition: BrowserSpeechRecognition | null = null;
  let voiceBaseline = "";
  let voiceHadTranscript = false;
  let voiceFailed = false;
  let voiceRequestedStop = false;
  const listeners = new Set<() => void>();
  const photoListeners = new Set<() => void>();

  function publish(changes: Partial<InboxDraftSnapshot>) {
    snapshot = { ...snapshot, ...changes };
    for (const listener of listeners) listener();
  }

  function currentValues(): InboxDraftValues {
    const { body, bodyRich, occurrence, title } = snapshot;
    return { body, bodyRich, occurrence, title };
  }

  function readValues(): {
    isComplete: boolean;
    values: InboxDraftValues | null;
  } {
    const { draft, isComplete } = readInboxDraft(storage, ownerId);
    if (!draft) return { isComplete, values: null };

    return {
      isComplete,
      values: {
        body: draft.body,
        bodyRich: draft.bodyRich ?? null,
        occurrence:
          draft.occurrence ??
          (draft.occurredAt
            ? occurrenceDraft({
                datePrecision: "exact",
                occurredAt: new Date(draft.occurredAt).toISOString(),
                occurredEnd: null,
                occurredLabel: null,
                occurredTimezone: timezone(),
              })
            : null),
        title: draft.title,
      },
    };
  }

  function ensureLoaded() {
    if (isLoaded) return;
    isLoaded = true;
    const { isComplete, values: stored } = readValues();
    hasStoredWriting = Boolean(stored);
    snapshot = {
      ...snapshot,
      ...(stored ?? emptyValues),
      hasLocalDraft: hasStoredWriting,
      isReady: true,
      // The unreadable part stays in storage and is kept aside before the
      // first change replaces it.
      notice: isComplete
        ? null
        : {
            isError: true,
            message: stored ? unrestoredDraftMessage : unreadableDraftMessage,
            revision: snapshot.revision,
          },
    };
  }

  /** Publishes a changed draft; only a voice transcript keeps the voice message. */
  function change(
    changes: Partial<InboxDraftSnapshot>,
    { keepVoiceNotice = false } = {},
  ) {
    const photos = changes.photos ?? snapshot.photos;
    publish({
      ...changes,
      hasLocalDraft: hasStoredWriting || photos.length > 0,
      revision: snapshot.revision + 1,
      ...(keepVoiceNotice ? {} : { voiceNotice: null }),
    });
  }

  function writeValues(values: InboxDraftValues, keepVoiceNotice = false) {
    hasStoredWriting = persistInboxDraft(storage, ownerId, {
      ...values,
      occurredAt: null,
    });
    change(values, { keepVoiceNotice });
  }

  /** Publishes this tab's own photo change and tells other tabs about it. */
  function changePhotos(changes: Partial<InboxDraftSnapshot>) {
    photoGeneration += 1;
    change(changes);
    for (const listener of photoListeners) listener();
  }

  function startPhotoRead() {
    hasReadPhotos = true;
    const read = readPhotos().finally(() => {
      if (photoRead === read) photoRead = null;
    });
    photoRead = read;
    return read;
  }

  async function readPhotos(): Promise<void> {
    ensureLoaded();
    const generation = photoGeneration;
    // Read the queue first: a capture leaves it only after its photos left
    // storage, so a stored photo missing from this list is a draft photo.
    const queued = queuedPhotoIds();
    let stored: InboxPhotoDraft[];
    try {
      stored = await photoStorage.load(ownerId);
    } catch {
      if (snapshot.photoState === "loading")
        publish({
          notice: {
            isError: true,
            message: photoDraftsUnavailableMessage,
            revision: snapshot.revision,
          },
          photoState: "unavailable",
        });
      return;
    }
    // The photos changed during the read, so it may be stale.
    if (generation !== photoGeneration) return readPhotos();

    const draftIds = new Set(
      stored.filter(({ id }) => !queued.has(id)).map(({ id }) => id),
    );
    const kept = snapshot.photos.filter(({ id }) => draftIds.has(id));
    const keptIds = new Set(kept.map(({ id }) => id));
    // Keep the order this tab already shows and add new photos after it.
    const photos = [
      ...kept,
      ...stored.filter(({ id }) => draftIds.has(id) && !keptIds.has(id)),
    ];
    const changes: Partial<InboxDraftSnapshot> =
      snapshot.photoState === "loading" ? { photoState: "ready" } : {};
    if (
      photos.length !== snapshot.photos.length ||
      photos.some((photo, index) => photo !== snapshot.photos[index])
    )
      change({ ...changes, photos });
    else if (changes.photoState) publish(changes);
  }

  function finishVoice(voiceNotice: InboxDraftNotice | null) {
    if (recognition) {
      recognition.onend = null;
      recognition.onerror = null;
      recognition.onresult = null;
      recognition.abort();
      recognition = null;
    }
    publish({ voice: "idle", voiceNotice });
  }

  function startVoice() {
    ensureLoaded();
    const Recognition = speechRecognition();
    if (!Recognition) {
      publish({
        voiceNotice: {
          isError: true,
          message:
            "Voice capture is unavailable in this browser. Text and photo capture still work.",
        },
      });
      return;
    }

    if (recognition) return;
    if (snapshot.body.length >= entryBodyLimit) {
      publish({
        voiceNotice: {
          isError: true,
          message: "This note has reached the 50,000 character limit.",
        },
      });
      return;
    }

    const session = new Recognition();
    session.continuous = true;
    session.interimResults = true;
    session.lang = language();
    voiceBaseline = snapshot.body;
    voiceHadTranscript = false;
    voiceFailed = false;
    voiceRequestedStop = false;

    session.onresult = (event) => {
      const transcript = browserVoiceTranscript(event.results);
      if (!transcript) return;

      voiceHadTranscript = true;
      const body = mergeVoiceTranscript(voiceBaseline, transcript);
      writeValues(
        {
          ...currentValues(),
          body,
          bodyRich: body === snapshot.body ? snapshot.bodyRich : null,
        },
        true,
      );
    };

    session.onerror = (event) => {
      const message = voiceRecognitionErrorMessage(event.error);
      if (!message && voiceRequestedStop) return;

      voiceFailed = Boolean(message);
      if (message) publish({ voiceNotice: { isError: true, message } });
    };

    session.onend = () => {
      if (recognition === session) recognition = null;
      publish({
        voice: "idle",
        ...(voiceFailed
          ? {}
          : {
              voiceNotice: {
                isError: false,
                message: voiceHadTranscript
                  ? "Transcription added to this draft."
                  : "Voice capture stopped before any words were recognized.",
              },
            }),
      });
    };

    recognition = session;
    try {
      session.start();
      publish({
        voice: "listening",
        voiceNotice: {
          isError: false,
          message: "Listening… Tap Stop when done. Audio is not saved.",
        },
      });
    } catch {
      recognition = null;
      publish({
        voice: "idle",
        voiceNotice: {
          isError: true,
          message:
            "Voice capture could not start. Check browser permissions and try again.",
        },
      });
    }
  }

  return {
    async addPhotos(photos) {
      ensureLoaded();
      try {
        await photoStorage.persist(ownerId, photos);
      } catch (error) {
        publish({ photoState: "unavailable" });
        throw error;
      }
      const known = new Set(snapshot.photos.map(({ id }) => id));
      changePhotos({
        photos: [
          ...snapshot.photos,
          ...photos.filter(({ id }) => !known.has(id)),
        ],
      });
    },
    cancelVoice() {
      if (!recognition) return;
      finishVoice(
        voiceHadTranscript
          ? { isError: false, message: "Transcription added to this draft." }
          : null,
      );
    },
    clear() {
      ensureLoaded();
      if (recognition) finishVoice(null);
      clearInboxDraft(storage, ownerId);
      hasStoredWriting = false;
      // The photos now belong to the queued capture, which keeps them stored.
      if (snapshot.photos.length > 0)
        changePhotos({ ...emptyValues, photos: [] });
      else change(emptyValues);
    },
    getServerSnapshot: () => serverSnapshot,
    getSnapshot() {
      ensureLoaded();
      return snapshot;
    },
    loadPhotos() {
      if (hasReadPhotos) return photoRead ?? Promise.resolve();
      return startPhotoRead();
    },
    onPhotosChanged(listener) {
      photoListeners.add(listener);
      return () => photoListeners.delete(listener);
    },
    reload() {
      // A draft not read yet is read in full on first use.
      if (!isLoaded) return;
      const { values: stored } = readValues();
      hasStoredWriting = Boolean(stored);
      const values = stored ?? emptyValues;
      if (sameValues(values, currentValues())) {
        const hasLocalDraft = hasStoredWriting || snapshot.photos.length > 0;
        if (hasLocalDraft !== snapshot.hasLocalDraft)
          publish({ hasLocalDraft });
        return;
      }
      if (!recognition) {
        change(values);
        return;
      }
      // Its next transcript would write over the other tab's change.
      finishVoice({ isError: true, message: changedElsewhereVoiceMessage });
      change(values, { keepVoiceNotice: true });
    },
    reloadPhotos() {
      if (!photoRead) return startPhotoRead();
      // The read in progress may predate the other tab's change.
      photoGeneration += 1;
      return photoRead;
    },
    async removePhoto(photoId) {
      await photoStorage.remove(ownerId, [photoId]);
      changePhotos({
        photos: snapshot.photos.filter(({ id }) => id !== photoId),
      });
    },
    startVoice,
    stopVoice() {
      if (!recognition) return;
      voiceRequestedStop = true;
      publish({
        voice: "stopping",
        voiceNotice: {
          isError: false,
          message: "Finishing transcription… Audio was not saved.",
        },
      });
      recognition.stop();
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    update(changes) {
      ensureLoaded();
      const current = currentValues();
      const body = changes.body ?? current.body;
      writeValues({
        ...current,
        ...changes,
        body,
        // A plain-text change, such as a transcript, drops stale formatting.
        bodyRich:
          changes.bodyRich !== undefined
            ? changes.bodyRich
            : body === current.body
              ? current.bodyRich
              : null,
      });
    },
  };
}

function sameValues(left: InboxDraftValues, right: InboxDraftValues) {
  return (
    left.title === right.title &&
    left.body === right.body &&
    JSON.stringify(left.bodyRich) === JSON.stringify(right.bodyRich) &&
    JSON.stringify(left.occurrence) === JSON.stringify(right.occurrence)
  );
}
