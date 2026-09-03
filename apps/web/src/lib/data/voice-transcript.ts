import { entryBodyLimit } from "./inbox-input";

export type BrowserSpeechRecognitionAlternative = {
  transcript: string;
};

export type BrowserSpeechRecognitionResult = {
  readonly length: number;
  readonly [index: number]: BrowserSpeechRecognitionAlternative;
};

export type BrowserSpeechRecognitionEvent = {
  readonly results: {
    readonly length: number;
    readonly [index: number]: BrowserSpeechRecognitionResult;
  };
};

export type BrowserSpeechRecognitionErrorEvent = {
  readonly error: string;
};

export type BrowserSpeechRecognition = {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onend: (() => void) | null;
  onerror: ((event: BrowserSpeechRecognitionErrorEvent) => void) | null;
  onresult: ((event: BrowserSpeechRecognitionEvent) => void) | null;
  abort(): void;
  start(): void;
  stop(): void;
};

export type BrowserSpeechRecognitionConstructor =
  new () => BrowserSpeechRecognition;

type BrowserWithSpeechRecognition = Window & {
  SpeechRecognition?: BrowserSpeechRecognitionConstructor;
  webkitSpeechRecognition?: BrowserSpeechRecognitionConstructor;
};

export function browserSpeechRecognitionConstructor(
  browser: Window,
): BrowserSpeechRecognitionConstructor | null {
  const candidate = browser as BrowserWithSpeechRecognition;
  return (
    candidate.SpeechRecognition ?? candidate.webkitSpeechRecognition ?? null
  );
}

export function browserVoiceTranscript(
  results: BrowserSpeechRecognitionEvent["results"],
) {
  let transcript = "";

  for (let index = 0; index < results.length; index += 1) {
    transcript += results[index]?.[0]?.transcript ?? "";
  }

  return transcript.trim();
}

export function mergeVoiceTranscript(
  existingText: string,
  transcript: string,
  limit = entryBodyLimit,
) {
  if (limit <= 0) {
    return "";
  }

  const spokenText = transcript.trim();
  if (!spokenText) {
    return existingText.slice(0, limit);
  }

  const separator = !existingText || /\s$/u.test(existingText) ? "" : "\n";
  return `${existingText}${separator}${spokenText}`.slice(0, limit);
}

export function voiceRecognitionErrorMessage(error: string): string | null {
  switch (error) {
    case "aborted":
      return null;
    case "audio-capture":
      return "No microphone is available for voice capture.";
    case "network":
      return "Voice capture needs a connection in this browser. Try again when online.";
    case "no-speech":
      return "No speech was recognized. Try again and speak near the microphone.";
    case "not-allowed":
    case "service-not-allowed":
      return "Allow microphone and speech access in this browser to use voice capture.";
    default:
      return "Voice capture stopped unexpectedly. Your existing draft is still safe.";
  }
}
