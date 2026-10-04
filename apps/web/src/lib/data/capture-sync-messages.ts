// What a pending capture tells the person when it cannot sync, shared by the
// capture server actions and the photo uploads in the browser. Native
// `InboxController` still names Inbox until it follows Web.

export const rejectedEntryMessage =
  "MemoTrail cannot accept this Entry, so it will not sync. Copy its text to keep it, then discard it.";
export const deletedForeverMessage =
  "This Entry was deleted forever, so MemoTrail will not create it again. Copy its text to keep it, then discard it.";
export const trashedEntryMessage =
  "This Entry is already in Trash, so it will not sync again. Restore it from Trash to keep it, then discard this copy.";

export const rejectedPhotoMessage =
  "This Entry is in your Library, but MemoTrail cannot accept one of its photos, so they will not sync. Discard to remove them from this device.";
export const tooLargePhotoMessage =
  "This Entry is in your Library, but one of its photos is too large for MemoTrail, so they will not sync. Discard to remove them from this device.";
export const unsupportedPhotoMessage =
  "This Entry is in your Library, but one of its photos is a file type MemoTrail does not accept, so they will not sync. Discard to remove them from this device.";
export const missingPhotoMessage =
  "This Entry is in your Library, but one of its photos is no longer on this device, so they will not sync. Discard to remove them from this device.";
export const trashedPhotoMessage =
  "This Entry is in Trash, so its photos will not be attached. Discard to remove them from this device.";

export const offlinePhotoSyncMessage =
  "Photos are saved on this device. MemoTrail will retry when you are online.";
export const photoSessionMessage =
  "Your session expired. Sign in again to sync this Entry's photos.";
