import { describe, expect, it } from "vitest";
import {
  browserSpeechRecognitionConstructor,
  browserVoiceTranscript,
  mergeVoiceTranscript,
  voiceRecognitionErrorMessage,
} from "./voice-transcript";

describe("Web voice transcription", () => {
  it("detects the standard or prefixed browser implementation", () => {
    class Recognition {}

    expect(
      browserSpeechRecognitionConstructor({
        SpeechRecognition: Recognition,
      } as unknown as Window),
    ).toBe(Recognition);
    expect(
      browserSpeechRecognitionConstructor({
        webkitSpeechRecognition: Recognition,
      } as unknown as Window),
    ).toBe(Recognition);
  });

  it("returns no implementation in unsupported browsers", () => {
    expect(browserSpeechRecognitionConstructor({} as Window)).toBeNull();
  });

  it("uses a transcript directly for an empty draft", () => {
    expect(mergeVoiceTranscript("", "A thought worth keeping")).toBe(
      "A thought worth keeping",
    );
  });

  it("adds a transcript after existing draft text", () => {
    expect(mergeVoiceTranscript("Written first", "Spoken next")).toBe(
      "Written first\nSpoken next",
    );
  });

  it("does not duplicate existing whitespace", () => {
    expect(mergeVoiceTranscript("Written first\n", "Spoken next")).toBe(
      "Written first\nSpoken next",
    );
  });

  it("preserves an existing draft for an empty transcript", () => {
    expect(mergeVoiceTranscript("Keep this exactly", "  \n ")).toBe(
      "Keep this exactly",
    );
  });

  it("keeps a merged transcript inside the Entry body limit", () => {
    expect(mergeVoiceTranscript("12345", "67890", 8)).toBe("12345\n67");
  });

  it("collects the leading alternative from every recognition result", () => {
    expect(
      browserVoiceTranscript({
        0: { 0: { transcript: "Why do people " }, length: 1 },
        1: { 0: { transcript: "keep learning?" }, length: 1 },
        length: 2,
      }),
    ).toBe("Why do people keep learning?");
  });

  it("maps permission and offline failures to actionable feedback", () => {
    expect(voiceRecognitionErrorMessage("not-allowed")).toContain(
      "Allow microphone",
    );
    expect(voiceRecognitionErrorMessage("network")).toContain("connection");
  });

  it("keeps an intentional abort quiet", () => {
    expect(voiceRecognitionErrorMessage("aborted")).toBeNull();
  });
});
