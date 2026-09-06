/* eslint-disable require-jsdoc, max-len */
const test = require("node:test");
const assert = require("node:assert/strict");

const visionPath = require.resolve("@google-cloud/vision");
const originalVision = require.cache[visionPath];
const videoPath = require.resolve("@google-cloud/video-intelligence");
const originalVideo = require.cache[videoPath];
const speechPath = require.resolve("@google-cloud/speech");
const originalSpeech = require.cache[speechPath];
const languagePath = require.resolve("@google-cloud/language");
const originalLanguage = require.cache[languagePath];

let seenVisionSafeSearchURIs = [];
let shouldFailGcsSafeSearch = false;
let videoAnnotateCalls = 0;

require.cache[visionPath] = {
  exports: {
    ImageAnnotatorClient: class {
      async safeSearchDetection(request) {
        const uri = request && request.image && request.image.source && request.image.source.imageUri;
        seenVisionSafeSearchURIs.push(uri);

        if (shouldFailGcsSafeSearch && typeof uri === "string" && uri.startsWith("gs://")) {
          throw new Error("Permission denied for gs://");
        }

        return [{
          safeSearchAnnotation: {
            adult: "LIKELY",
            racy: "VERY_UNLIKELY",
            violence: "VERY_UNLIKELY",
          },
        }];
      }
      async textDetection() {
        return [{fullTextAnnotation: {text: ""}}];
      }
    },
  },
};
require.cache[videoPath] = {
  exports: {
    VideoIntelligenceServiceClient: class {
      async annotateVideo() {
        videoAnnotateCalls += 1;
        return [{
          promise: async () => [{annotationResults: [{explicitAnnotation: {frames: []}, speechTranscriptions: []}]}],
        }];
      }
    },
  },
};
require.cache[speechPath] = {exports: {
  SpeechClient: class {
    async recognize() {
      return [{
        results: [{
          alternatives: [{transcript: "Hello world from a valid spoken sample."}],
        }],
      }];
    }
  },
}};
require.cache[languagePath] = {
  exports: {
    LanguageServiceClient: class {
      async moderateText() {
        return [{moderationCategories: []}];
      }
    },
  },
};

delete require.cache[require.resolve("./index.js")];
const moderation = require("./index.js");

const samplePhoto = {
  contentType: "photo",
  title: "Sunset walk",
  body: "A normal photo from my day",
  mediaURLs: ["https://storage.googleapis.com/example-bucket/photos/normal.jpg"],
};

test("photo posts with likely-but-not-very-likely adult content are not auto-rejected", async () => {
  seenVisionSafeSearchURIs = [];
  shouldFailGcsSafeSearch = false;
  videoAnnotateCalls = 0;

  const result = await moderation.evaluateModeration(samplePhoto);
  assert.notEqual(result.status, "rejected");
  assert.notEqual(result.status, "review_required");
  assert.equal(videoAnnotateCalls, 0);
});

test("photo-video posts with only photo URLs do not invoke video moderation", async () => {
  seenVisionSafeSearchURIs = [];
  shouldFailGcsSafeSearch = false;
  videoAnnotateCalls = 0;

  const result = await moderation.evaluateModeration({
    contentType: "photo/video",
    title: "Gallery post",
    body: "Photo only in a mixed type post",
    mediaURLs: ["https://storage.googleapis.com/example-bucket/photos/cover.jpg"],
  });

  assert.equal(result.status, "approved");
  assert.equal(videoAnnotateCalls, 0);
});

test("image moderation falls back to original URL when gs URI scan fails", async () => {
  seenVisionSafeSearchURIs = [];
  shouldFailGcsSafeSearch = true;
  videoAnnotateCalls = 0;

  const result = await moderation.evaluateModeration({
    contentType: "photo",
    title: "Fallback test",
    body: "Use HTTPS fallback if gs URI fails",
    mediaURLs: [
      "https://firebasestorage.googleapis.com/v0/b/example-bucket.appspot.com/o/posts%2F123%2Fphotos%2Fimage.jpg?alt=media&token=fake-token",
    ],
  });

  assert.equal(result.status, "approved");
  assert.equal(
      seenVisionSafeSearchURIs.some((uri) => typeof uri === "string" && uri.startsWith("gs://")),
      true,
  );
  assert.equal(
      seenVisionSafeSearchURIs.some((uri) => typeof uri === "string" && uri.startsWith("https://firebasestorage.googleapis.com/")),
      true,
  );
  assert.equal(result.reasonCodes.includes("image_api_unavailable"), false);
});

test("benign audio posts are not forced into review when transcription is unavailable", async () => {
  seenVisionSafeSearchURIs = [];
  shouldFailGcsSafeSearch = false;
  videoAnnotateCalls = 0;

  const speechClient = require("@google-cloud/speech");
  const originalClient = speechClient.SpeechClient;
  speechClient.SpeechClient = class {
    async recognize() {
      throw new Error("Speech API unavailable");
    }
  };

  try {
    const result = await moderation.evaluateModeration({
      contentType: "audio",
      title: "Hello",
      body: "hello there",
      mediaURLs: ["gs://example-bucket/audio/hello.m4a"],
      locationName: "Tokyo, Japan",
    });

    assert.equal(result.status, "approved");
    assert.equal(result.reasonCodes.includes("media_scan_incomplete_review"), false);
  } finally {
    speechClient.SpeechClient = originalClient;
  }
});

const contentTypeCases = [
  {
    name: "text",
    payload: {contentType: "text", title: "Morning note", body: "Coffee and a quick walk before work.", locationName: "Tokyo, Japan"},
  },
  {
    name: "poll",
    payload: {
      contentType: "poll",
      title: "Best neighborhood coffee?",
      body: "Pick a favorite.",
      locationName: "Brooklyn, NY",
      pollOptions: ["DUMBO", "Williamsburg"],
    },
  },
  {
    name: "link",
    payload: {
      contentType: "link",
      title: "Map article",
      body: "Great routes nearby.",
      sourceURL: "https://example.com/local-guide",
      locationName: "Paris, France",
    },
  },
  {
    name: "video",
    payload: {
      contentType: "video",
      title: "Quick walk-through",
      body: "Short clip from the block.",
      mediaURLs: ["https://storage.googleapis.com/example-bucket/videos/walk.mp4"],
      locationName: "Berlin, Germany",
    },
  },
  {
    name: "audio",
    payload: {
      contentType: "audio",
      title: "Voice note",
      body: "A short audio update.",
      mediaURLs: ["gs://example-bucket/audio/voice-note.m4a"],
      locationName: "London, UK",
    },
  },
  {
    name: "song",
    payload: {
      contentType: "song",
      title: "Favorite track",
      body: "Playing this all day.",
      mediaURLs: ["gs://example-bucket/audio/favorite-track.mp3"],
      locationName: "Madrid, Spain",
    },
  },
  {
    name: "guide",
    payload: {
      contentType: "guide",
      title: "Three-stop city walk",
      body: "Start at coffee, then museum, then river.",
      locationName: "Seoul, South Korea",
    },
  },
  {
    name: "work",
    payload: {
      contentType: "work",
      title: "Design role",
      body: "Remote product designer wanted.",
      locationName: "Toronto, Canada",
    },
  },
  {
    name: "for sale",
    payload: {
      contentType: "for sale",
      title: "Vintage bike",
      body: "Lightly used commuter bike for sale.",
      locationName: "Austin, TX",
    },
  },
  {
    name: "live route",
    payload: {
      contentType: "live route",
      title: "Sunset route",
      body: "Coffee to river walk.",
      locationName: "Lisbon, Portugal",
    },
  },
];

for (const entry of contentTypeCases) {
  test(`${entry.name} posts remain approval-safe in moderation`, async () => {
    seenVisionSafeSearchURIs = [];
    shouldFailGcsSafeSearch = false;
    videoAnnotateCalls = 0;

    const result = await moderation.evaluateModeration(entry.payload);
    assert.equal(result.status, "approved");
    assert.equal(result.reasonCodes.includes("text_policy_reject"), false);
    assert.equal(result.reasonCodes.includes("link_policy_reject"), false);
  });
}

test.after(() => {
  if (originalVision) {
    require.cache[visionPath] = originalVision;
  } else {
    delete require.cache[visionPath];
  }
  if (originalVideo) {
    require.cache[videoPath] = originalVideo;
  } else {
    delete require.cache[videoPath];
  }
  if (originalSpeech) {
    require.cache[speechPath] = originalSpeech;
  } else {
    delete require.cache[speechPath];
  }
  if (originalLanguage) {
    require.cache[languagePath] = originalLanguage;
  } else {
    delete require.cache[languagePath];
  }
});
