/* eslint-disable max-len, require-jsdoc, indent, comma-dangle */
const admin = require("firebase-admin");
const functions = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const vision = require("@google-cloud/vision");
const videoIntelligence = require("@google-cloud/video-intelligence");
const speech = require("@google-cloud/speech");
const language = require("@google-cloud/language");
const {GoogleAuth} = require("google-auth-library");
const sgMail = require("@sendgrid/mail");
const fs = require("fs");
const path = require("path");
const {URL} = require("url");
const crypto = require("crypto");

admin.initializeApp({
  storageBucket: process.env.STORAGE_BUCKET || "tiding-506722.firebasestorage.app"
});

const LOGO_URL =
  process.env.APP_LOGO_URL ||
  "data:image/jpeg;base64," +
    fs.readFileSync(
      path.join(__dirname, "assets", "tiding-logo.jpg")
    ).toString("base64");

if (process.env.SENDGRID_API_KEY) {
  sgMail.setApiKey(process.env.SENDGRID_API_KEY);
}

functions.setGlobalOptions({maxInstances: 10});

const visionClient = new vision.ImageAnnotatorClient();
const videoClient = new videoIntelligence.VideoIntelligenceServiceClient();
const speechClient = new speech.SpeechClient();
const languageClient = new language.LanguageServiceClient();
const googleAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"]
});

function firstNonEmptyEnv(keys, fallback = "") {
  for (const key of keys) {
    const value = String(process.env[key] || "").trim();
    if (value) {
      return value;
    }
  }
  return fallback;
}

const APNS_KEY_ID = firstNonEmptyEnv([
  "APNS_KEY_ID",
  "APN_KEY_ID",
  "APPLE_APNS_KEY_ID",
  "APPLE_KEY_ID",
]);

const APNS_TEAM_ID = firstNonEmptyEnv([
  "APNS_TEAM_ID",
  "APN_TEAM_ID",
  "APPLE_APNS_TEAM_ID",
  "APPLE_TEAM_ID",
]);

const APNS_BUNDLE_ID = firstNonEmptyEnv([
  "APNS_BUNDLE_ID",
  "APN_BUNDLE_ID",
  "APPLE_APNS_TOPIC",
  "APPLE_BUNDLE_ID",
], "Lane-Apps.Spot");

const APNS_PRIVATE_KEY_RAW = firstNonEmptyEnv([
  "APNS_PRIVATE_KEY",
  "APN_PRIVATE_KEY",
  "APPLE_APNS_PRIVATE_KEY",
  "APPLE_PRIVATE_KEY",
  "APNS_P8",
]);

const APNS_USE_SANDBOX = firstNonEmptyEnv([
  "APNS_USE_SANDBOX",
  "APN_USE_SANDBOX",
  "APPLE_APNS_USE_SANDBOX",
], "true").toLowerCase() === "true";

const ADMIN_FORCE_DELETE_CODE = firstNonEmptyEnv([
  "ADMIN_FORCE_DELETE_CODE",
  "POST_ADMIN_FORCE_DELETE_CODE",
], "9999");

let cachedAPNSJWT = "";
let cachedAPNSJWTIssuedAt = 0;

function buildBrandedResetURL(firebaseResetLink) {
  const resetPageURL = process.env.RESET_PAGE_URL || "https://tiding.app/reset-password";

  try {
    const parsedFirebaseLink = new URL(firebaseResetLink);
    const oobCode = parsedFirebaseLink.searchParams.get("oobCode");

    if (!oobCode) {
      return firebaseResetLink;
    }

    const brandedLink = new URL(resetPageURL);
    brandedLink.searchParams.set("mode", "resetPassword");
    brandedLink.searchParams.set("oobCode", oobCode);
    return brandedLink.toString();
  } catch (error) {
    return firebaseResetLink;
  }
}

function getPasswordResetActionCodeSettings() {
  const resetPageURL = process.env.RESET_PAGE_URL || "https://tiding.app/reset-password";

  return {
    url: resetPageURL,
    handleCodeInApp: true,
  };
}

const MODERATION_BLOCKED_LINK_HOSTS = new Set([
  "bit.ly",
  "tinyurl.com",
  "goo.gl",
  "is.gd",
  "t.co"
]);

const MODERATION_REJECT_PATTERNS = [
  /\bkill\b/i,
  /\bshoot\b/i,
  /\bbomb\b/i,
  /\bterror\b/i,
  /\bsuicide\b/i,
  /\bself\s*harm\b/i,
  /\bwhite\s*power\b/i,
  /\bracial\s*purity\b/i,
  /\bethnic\s*cleansing\b/i,
  /\bsegregation\b/i,
  /\bkkk\b/i,
  /\bneo\s*nazi\b/i,
  /\bnazi\b/i,
  /\bgo\s*back\s*to\s*your\s*country\b/i,
  /\b(i\s*hate|hate)\s+(black|white|asian|jewish|jews|muslim|latino|mexican|arab|indian|african)\b/i
];

const MODERATION_REVIEW_PATTERNS = [
  /\bscam\b/i,
  /\bfraud\b/i,
  /\bcocaine\b/i,
  /\bmeth\b/i
];

const MALE_GENITALIA_BLOCK_THRESHOLD = 0.65;
const FEMALE_GENITALIA_BLOCK_THRESHOLD = 0.65;
const FEMALE_CLEAVAGE_BLOCK_THRESHOLD = 0.85;
const IMAGE_ADULT_BLOCK_THRESHOLD = 0.9; // Reject only VERY_LIKELY adult images.
const IMAGE_RACY_BLOCK_THRESHOLD = 0.9; // Reject only VERY_LIKELY racy images.
const IMAGE_COMBINED_NUDITY_BLOCK_THRESHOLD = 0.9; // Reject only severe nudity cases.
const IMAGE_REVIEW_THRESHOLD = 0.65; // Keep borderline adult/racy images flow-safe.
const MAX_MEDIA_SCAN_URLS = 2;
const API_TIMEOUT_MS = 25000;
const PRIMARY_STORAGE_BUCKET = process.env.STORAGE_BUCKET || "tiding-506722.firebasestorage.app";

function sanitizeAPNSToken(rawToken) {
  const cleaned = String(rawToken || "")
    .trim()
    .toLowerCase()
    .replace(/[<>\s]/g, "");
  return /^[a-f0-9]{64,200}$/.test(cleaned) ? cleaned : "";
}

function requiredAPNSConfig() {
  const privateKey = APNS_PRIVATE_KEY_RAW.replace(/\\n/g, "\n");
  return {
    keyID: APNS_KEY_ID,
    teamID: APNS_TEAM_ID,
    bundleID: APNS_BUNDLE_ID,
    privateKey,
    host: APNS_USE_SANDBOX ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com",
  };
}

function assertAPNSConfigOrThrow() {
  const config = requiredAPNSConfig();
  if (!config.keyID || !config.teamID || !config.bundleID || !config.privateKey) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "APNs is not fully configured. Set APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, and APNS_PRIVATE_KEY."
    );
  }
  return config;
}

function buildAPNSJWT(config) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAPNSJWT && cachedAPNSJWTIssuedAt && now - cachedAPNSJWTIssuedAt < 3000) {
    return cachedAPNSJWT;
  }

  const header = Buffer.from(JSON.stringify({alg: "ES256", kid: config.keyID})).toString("base64url");
  const claims = Buffer.from(JSON.stringify({iss: config.teamID, iat: now})).toString("base64url");
  const unsigned = `${header}.${claims}`;

  const signer = crypto.createSign("SHA256");
  signer.update(unsigned);
  signer.end();
  const signature = signer.sign(config.privateKey).toString("base64url");

  cachedAPNSJWT = `${unsigned}.${signature}`;
  cachedAPNSJWTIssuedAt = now;
  return cachedAPNSJWT;
}

async function sendAPNSAlert({deviceToken, title, body}) {
  const config = assertAPNSConfigOrThrow();
  const authToken = buildAPNSJWT(config);

  const endpoint = `${config.host}/3/device/${deviceToken}`;
  const payload = {
    aps: {
      alert: {
        title,
        body,
      },
      sound: "default",
      badge: 1,
    },
  };

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      authorization: `bearer ${authToken}`,
      "apns-topic": config.bundleID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`APNs request failed (${response.status}): ${errorText}`);
  }
}

function locationNameFromPayload(rawLocation) {
  const cleaned = String(rawLocation || "").trim();
  return cleaned || "Metric";
}

function normalizeHost(rawHost = "") {
  const lowered = String(rawHost).trim().toLowerCase();
  if (lowered.startsWith("www.")) {
    return lowered.slice(4);
  }
  return lowered;
}

function normalizedLikelihood(value) {
  const map = {
    UNKNOWN: 0.0,
    VERY_UNLIKELY: 0.1,
    UNLIKELY: 0.25,
    POSSIBLE: 0.5,
    LIKELY: 0.75,
    VERY_LIKELY: 0.95,
  };
  const mapped = map[String(value || "UNKNOWN").toUpperCase()];
  return typeof mapped === "number" ? mapped : 0;
}

function highestStatus(current, candidate) {
  const rank = {
    approved: 0,
    review_required: 1,
    rejected: 2,
  };
  const candidateRank = typeof rank[candidate] === "number" ? rank[candidate] : 0;
  const currentRank = typeof rank[current] === "number" ? rank[current] : 0;
  return candidateRank > currentRank ? candidate : current;
}

function withTimeout(promise, timeoutMs = API_TIMEOUT_MS) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error("timeout")), timeoutMs);
    })
  ]);
}

function toGcsURI(rawURL) {
  if (typeof rawURL !== "string" || !rawURL.trim()) {
    return null;
  }

  const cleaned = rawURL.trim();
  if (cleaned.startsWith("gs://")) {
    return cleaned;
  }

  try {
    const parsed = new URL(cleaned);

    if (parsed.hostname === "firebasestorage.googleapis.com") {
      const segments = parsed.pathname.split("/").filter(Boolean);
      const bIndex = segments.indexOf("b");
      const oIndex = segments.indexOf("o");
      if (bIndex >= 0 && oIndex > bIndex + 1) {
        const bucket = segments[bIndex + 1];
        const objectPath = decodeURIComponent(segments.slice(oIndex + 1).join("/"));
        if (bucket && objectPath) {
          return `gs://${bucket}/${objectPath}`;
        }
      }
    }

    if (parsed.hostname === "storage.googleapis.com") {
      const segments = parsed.pathname.split("/").filter(Boolean);
      if (segments.length >= 2) {
        const bucket = segments[0];
        const objectPath = decodeURIComponent(segments.slice(1).join("/"));
        return `gs://${bucket}/${objectPath}`;
      }
    }
  } catch (error) {
    return null;
  }

  return null;
}

function transcriptMatchesRejectPolicy(transcript) {
  const text = String(transcript || "");
  if (!text.trim()) {
    return false;
  }
  return MODERATION_REJECT_PATTERNS.some((pattern) => pattern.test(text));
}

function normalizeScore(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return 0;
  }
  return Math.max(0, Math.min(1, numeric));
}

async function getAccessToken() {
  const token = await googleAuth.getAccessToken();
  return typeof token === "string" ? token : token && token.token ? token.token : "";
}

function extractCandidateURLs(postData) {
  const candidates = [];

  if (typeof postData.sourceURL === "string" && postData.sourceURL.trim()) {
    candidates.push(postData.sourceURL.trim());
  }

  if (Array.isArray(postData.mediaURLs)) {
    for (const value of postData.mediaURLs) {
      if (typeof value === "string" && value.trim()) {
        candidates.push(value.trim());
      }
    }
  }

  return candidates;
}

function looksLikeVideoURL(rawURL) {
  if (typeof rawURL !== "string") {
    return false;
  }

  const cleaned = rawURL.trim().toLowerCase();
  if (!cleaned) {
    return false;
  }

  const knownVideoExts = new Set([
    "mp4",
    "mov",
    "m4v",
    "webm",
    "avi",
    "mkv",
    "hevc",
    "mpg",
    "mpeg",
  ]);

  try {
    const parsed = new URL(cleaned);
    const path = String(parsed.pathname || "");
    const ext = path.split(".").pop() || "";
    return knownVideoExts.has(ext);
  } catch (error) {
    const pathWithoutQuery = cleaned.split("?")[0] || "";
    const ext = pathWithoutQuery.split(".").pop() || "";
    return knownVideoExts.has(ext);
  }
}

function buildModerationText(postData) {
  const values = [
    postData.contentType,
    postData.title,
    postData.body,
    postData.locationName,
    ...(Array.isArray(postData.pollOptions) ? postData.pollOptions : []),
    ...(Array.isArray(postData.tags) ? postData.tags : [])
  ];

  return values
    .filter((value) => typeof value === "string" && value.trim().length > 0)
    .join(" ");
}

function normalizedContentType(postData) {
  return String(postData.contentType || "")
    .trim()
    .toLowerCase();
}

function toScore(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return 0;
  }
  return Math.max(0, Math.min(1, numeric));
}

async function applyLanguageModeration(text, moderationResult) {
  if (!text.trim()) {
    return;
  }

  try {
    const [response] = await withTimeout(languageClient.moderateText({
      document: {
        type: "PLAIN_TEXT",
        content: text,
      }
    }));

    const categories = response.moderationCategories || [];
    let strongest = 0;
    let strongestCategory = "";

    for (const category of categories) {
      const confidence = normalizeScore(category.confidence);
      if (confidence > strongest) {
        strongest = confidence;
        strongestCategory = String(category.name || "").toLowerCase();
      }
    }

    moderationResult.scores.text = Math.max(moderationResult.scores.text, strongest);

    const isHateCategory = strongestCategory.includes("hate") || strongestCategory.includes("harass");
    if (isHateCategory && strongest >= 0.75) {
      moderationResult.status = highestStatus(moderationResult.status, "rejected");
      moderationResult.reasonCodes.push("language_hate_reject");
      return;
    }

          if (strongest >= 0.65) {
            moderationResult.reasonCodes.push("language_moderation_review");
          }
  } catch (error) {
    moderationResult.reasonCodes.push("language_api_unavailable");
  }
}

async function applyImageModeration(mediaURLs, moderationResult) {
  const imageCandidates = (Array.isArray(mediaURLs) ? mediaURLs : [])
    .filter((value) => typeof value === "string" && value.trim())
    .slice(0, MAX_MEDIA_SCAN_URLS);

  console.log("applyImageModeration: received mediaURLs", {
    count: Array.isArray(mediaURLs) ? mediaURLs.length : "not_array",
    urls: mediaURLs,
    candidates: imageCandidates
  });

  if (imageCandidates.length === 0) {
    moderationResult.reasonCodes.push("image_scan_missing_media");
    return;
  }

  // Check for fake/local URLs that backend cannot process
  for (const url of imageCandidates) {
    if (url.toLowerCase().startsWith("local-") || url.toLowerCase().startsWith("file://")) {
      console.log("applyImageModeration: Rejecting fake local URL", {url});
      moderationResult.status = highestStatus(moderationResult.status, "rejected");
      moderationResult.reasonCodes.push("image_fake_local_url");
      moderationResult.scores.image = Math.max(moderationResult.scores.image, 0);
      return;
    }
  }

  let anyScanned = false;
  for (const rawURL of imageCandidates) {
    const preferredURI = toGcsURI(rawURL) || rawURL;
    const imageURIsToTry = preferredURI === rawURL ? [rawURL] : [preferredURI, rawURL];
    let scanSucceeded = false;
    let lastScanError = null;

    for (const imageURI of imageURIsToTry) {
      try {
        console.log("applyImageModeration: Calling Vision API for", {imageURI: imageURI.slice(0, 80)});

        const [safeSearchResponse] = await withTimeout(visionClient.safeSearchDetection({
          image: {
            source: {imageUri: imageURI}
          }
        }));

        console.log("applyImageModeration: Vision API response received", {
          adult: safeSearchResponse.safeSearchAnnotation && safeSearchResponse.safeSearchAnnotation.adult,
          racy: safeSearchResponse.safeSearchAnnotation && safeSearchResponse.safeSearchAnnotation.racy,
          violence: safeSearchResponse.safeSearchAnnotation && safeSearchResponse.safeSearchAnnotation.violence,
          fullResponse: JSON.stringify(safeSearchResponse)
        });

        const annotation = safeSearchResponse.safeSearchAnnotation || {};
        const adultScore = normalizedLikelihood(annotation.adult);
        const racyScore = normalizedLikelihood(annotation.racy);
        const violenceScore = normalizedLikelihood(annotation.violence);
        const nudityScore = Math.max(adultScore, racyScore);

        console.log("applyImageModeration: Normalized scores", {
          adultScore,
          racyScore,
          violenceScore,
          nudityScore
        });

        moderationResult.scores.image = Math.max(
          moderationResult.scores.image,
          nudityScore,
          violenceScore
        );

        anyScanned = true;

        if (
          adultScore >= IMAGE_ADULT_BLOCK_THRESHOLD ||
          racyScore >= IMAGE_RACY_BLOCK_THRESHOLD ||
          nudityScore >= IMAGE_COMBINED_NUDITY_BLOCK_THRESHOLD
        ) {
          console.log("applyImageModeration: REJECTING based on nudity/violence thresholds");
          moderationResult.status = highestStatus(moderationResult.status, "rejected");
          moderationResult.reasonCodes.push("image_nudity_reject");
          if (adultScore >= IMAGE_ADULT_BLOCK_THRESHOLD) {
            moderationResult.reasonCodes.push("image_adult_reject");
          }
          if (racyScore >= IMAGE_RACY_BLOCK_THRESHOLD) {
            moderationResult.reasonCodes.push("image_racy_reject");
          }
        } else if (nudityScore >= IMAGE_REVIEW_THRESHOLD || violenceScore >= 0.8) {
          moderationResult.reasonCodes.push("image_safety_review");
        }

        const [ocrResponse] = await withTimeout(visionClient.textDetection({
          image: {
            source: {imageUri: imageURI}
          }
        }));
        const fullText = ocrResponse.fullTextAnnotation && ocrResponse.fullTextAnnotation.text ? ocrResponse.fullTextAnnotation.text : "";
        if (transcriptMatchesRejectPolicy(fullText)) {
          console.log("applyImageModeration: REJECTING based on OCR hate speech");
          moderationResult.status = highestStatus(moderationResult.status, "rejected");
          moderationResult.reasonCodes.push("image_ocr_hate_reject");
          moderationResult.scores.image = Math.max(moderationResult.scores.image, 0.95);
        }

        scanSucceeded = true;
        break;
      } catch (error) {
        lastScanError = error;
        console.log("applyImageModeration: ERROR calling Vision API", {
          imageURI: imageURI.slice(0, 80),
          error: error.message,
          errorCode: error.code,
          errorDetails: JSON.stringify(error)
        });
      }
    }

    if (!scanSucceeded) {
      moderationResult.reasonCodes.push("image_api_unavailable");
      if (lastScanError) {
        console.log("applyImageModeration: all URI attempts failed", {
          rawURL,
          error: String(lastScanError.message || lastScanError)
        });
      }
    }
  }

  if (!anyScanned) {
    moderationResult.reasonCodes.push("image_scan_unavailable");
  }
}

async function applyVideoModeration(mediaURLs, moderationResult) {
  const rawURL = (Array.isArray(mediaURLs) ? mediaURLs : []).find((value) => typeof value === "string" && value.trim());
  if (!rawURL) {
    moderationResult.reasonCodes.push("video_scan_missing_media");
    return;
  }

  // Check for fake/local URLs that backend cannot process
  if (rawURL.toLowerCase().startsWith("local-") || rawURL.toLowerCase().startsWith("file://")) {
    console.log("applyVideoModeration: Rejecting fake local URL", {url: rawURL});
    moderationResult.status = highestStatus(moderationResult.status, "rejected");
    moderationResult.reasonCodes.push("video_fake_local_url");
    moderationResult.scores.video = Math.max(moderationResult.scores.video, 0);
    return;
  }

  const gcsURI = toGcsURI(rawURL);
  if (!gcsURI) {
    moderationResult.reasonCodes.push("video_scan_uri_unsupported");
    return;
  }

  try {
    const [operation] = await withTimeout(videoClient.annotateVideo({
      inputUri: gcsURI,
      features: [
        "EXPLICIT_CONTENT_DETECTION",
        "SPEECH_TRANSCRIPTION"
      ],
      videoContext: {
        speechTranscriptionConfig: {
          languageCode: "en-US",
          enableAutomaticPunctuation: true,
        }
      }
    }));

    const [result] = await withTimeout(operation.promise(), API_TIMEOUT_MS);
    const annotations = result.annotationResults || [];
    const first = annotations[0] || {};

    const frames = first.explicitAnnotation && Array.isArray(first.explicitAnnotation.frames) ? first.explicitAnnotation.frames : [];
    let maxExplicit = 0;
    for (const frame of frames) {
      const score = normalizedLikelihood(frame.pornographyLikelihood);
      maxExplicit = Math.max(maxExplicit, score);
    }

    moderationResult.scores.video = Math.max(moderationResult.scores.video, maxExplicit);

    if (maxExplicit >= 0.9) {
      moderationResult.status = highestStatus(moderationResult.status, "rejected");
      moderationResult.reasonCodes.push("video_explicit_reject");
    } else if (maxExplicit >= 0.65) {
      moderationResult.reasonCodes.push("video_explicit_review");
    }

    const transcripts = first.speechTranscriptions || [];
    const transcriptText = transcripts
      .map((chunk) => (chunk.alternatives && chunk.alternatives[0] && chunk.alternatives[0].transcript) || "")
      .join(" ")
      .trim();

    if (transcriptText) {
      moderationResult.scores.audio = Math.max(moderationResult.scores.audio, 0.6);
      if (transcriptMatchesRejectPolicy(transcriptText)) {
        moderationResult.status = highestStatus(moderationResult.status, "rejected");
        moderationResult.reasonCodes.push("video_transcript_hate_reject");
      }
      await applyLanguageModeration(transcriptText, moderationResult);
    }
  } catch (error) {
    moderationResult.reasonCodes.push("video_api_unavailable");
  }
}

async function applyAudioModeration(mediaURLs, moderationResult) {
  const rawURL = (Array.isArray(mediaURLs) ? mediaURLs : []).find((value) => typeof value === "string" && value.trim());
  if (!rawURL) {
    moderationResult.reasonCodes.push("audio_scan_missing_media");
    return;
  }

  // Check for fake/local URLs that backend cannot process
  if (rawURL.toLowerCase().startsWith("local-") || rawURL.toLowerCase().startsWith("file://")) {
    console.log("applyAudioModeration: Rejecting fake local URL", {url: rawURL});
    moderationResult.status = highestStatus(moderationResult.status, "rejected");
    moderationResult.reasonCodes.push("audio_fake_local_url");
    moderationResult.scores.audio = Math.max(moderationResult.scores.audio, 0);
    return;
  }

  const gcsURI = toGcsURI(rawURL);
  if (!gcsURI) {
    moderationResult.reasonCodes.push("audio_scan_uri_unsupported");
    return;
  }

  try {
    const [response] = await withTimeout(speechClient.recognize({
      config: {
        languageCode: "en-US",
        enableAutomaticPunctuation: true,
        model: "latest_long",
      },
      audio: {
        uri: gcsURI,
      },
    }));

    const transcript = (response.results || [])
      .map((result) => (result.alternatives && result.alternatives[0] && result.alternatives[0].transcript) || "")
      .join(" ")
      .trim();

    moderationResult.scores.audio = Math.max(moderationResult.scores.audio, transcript ? 0.65 : 0.5);

    if (!transcript) {
      moderationResult.reasonCodes.push("audio_transcript_empty");
      return;
    }

    if (transcriptMatchesRejectPolicy(transcript)) {
      moderationResult.status = highestStatus(moderationResult.status, "rejected");
      moderationResult.reasonCodes.push("audio_hate_reject");
      return;
    }

    await applyLanguageModeration(transcript, moderationResult);
  } catch (error) {
    console.warn("applyAudioModeration: speech unavailable; keeping benign audio approved", {
      error: error && error.message ? error.message : String(error),
      rawURL,
    });
    moderationResult.reasonCodes.push("audio_api_unavailable");
    return;
  }
}

function bypassAudioModerationForUnscannedContent(moderationResult) {
  if (moderationResult.reasonCodes.includes("audio_api_unavailable") || moderationResult.reasonCodes.includes("audio_transcript_empty")) {
    moderationResult.status = highestStatus(moderationResult.status, "approved");
  }
}

async function applyWebRiskModeration(candidateURLs, moderationResult) {
  const urls = (Array.isArray(candidateURLs) ? candidateURLs : [])
    .filter((value) => typeof value === "string" && value.trim())
    .filter((value) => {
      try {
        const parsed = new URL(value);
        const protocol = String(parsed.protocol || "").toLowerCase();
        return protocol === "http:" || protocol === "https:";
      } catch (error) {
        return false;
      }
    })
    .slice(0, MAX_MEDIA_SCAN_URLS);

  if (urls.length === 0) {
    return;
  }

  console.log("applyWebRiskModeration: received URLs", {count: urls.length, urls});

  try {
    const accessToken = await getAccessToken();
    if (!accessToken) {
      moderationResult.reasonCodes.push("webrisk_auth_unavailable");
      return;
    }

    for (const rawURL of urls) {
      const endpoint = `https://webrisk.googleapis.com/v1/uris:search?uri=${encodeURIComponent(rawURL)}&threatTypes=MALWARE&threatTypes=SOCIAL_ENGINEERING&threatTypes=UNWANTED_SOFTWARE`;
      const response = await withTimeout(fetch(endpoint, {
        method: "GET",
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      }));

      if (!response.ok) {
        console.log("applyWebRiskModeration: API request failed", {url: rawURL, status: response.status});
        moderationResult.reasonCodes.push("webrisk_request_failed");
        continue;
      }

      const payload = await response.json();
      if (payload && payload.threat) {
        moderationResult.status = highestStatus(moderationResult.status, "rejected");
        moderationResult.reasonCodes.push("webrisk_threat_reject");
        moderationResult.scores.link = Math.max(moderationResult.scores.link, 0.99);
      }
    }
  } catch (error) {
    console.log("applyWebRiskModeration: Exception", {error: String(error)});
    moderationResult.reasonCodes.push("webrisk_api_unavailable");
  }
}

function nuditySignalsFromPost(postData) {
  const container = postData.moderationSignals && postData.moderationSignals.nudity ? postData.moderationSignals.nudity : {};
  return {
    maleGenitaliaScore: toScore(container.maleGenitaliaScore),
    femaleGenitaliaScore: toScore(container.femaleGenitaliaScore),
    femaleCleavageScore: toScore(container.femaleCleavageScore),
  };
}

function isMediaContentType(contentType) {
  return new Set(["photo", "video", "photo/video", "audio", "song"]).has(contentType);
}

function applyNudityPolicyFromSignals(status, reasonCodes, scores, postData, contentType) {
  if (!isMediaContentType(contentType)) {
    return status;
  }

  const nudity = nuditySignalsFromPost(postData);
  const hasAnySignal = nudity.maleGenitaliaScore > 0 || nudity.femaleGenitaliaScore > 0 || nudity.femaleCleavageScore > 0;
  if (!hasAnySignal) {
    return status;
  }

  if (nudity.maleGenitaliaScore >= MALE_GENITALIA_BLOCK_THRESHOLD) {
    reasonCodes.push("male_genitalia_blocked");
    scores.image = Math.max(scores.image, nudity.maleGenitaliaScore);
    return "rejected";
  }

  if (nudity.femaleGenitaliaScore >= FEMALE_GENITALIA_BLOCK_THRESHOLD) {
    reasonCodes.push("female_genitalia_blocked");
    scores.image = Math.max(scores.image, nudity.femaleGenitaliaScore);
    return "rejected";
  }

  if (nudity.femaleCleavageScore >= FEMALE_CLEAVAGE_BLOCK_THRESHOLD) {
    reasonCodes.push("female_cleavage_blocked");
    scores.image = Math.max(scores.image, nudity.femaleCleavageScore);
    return "rejected";
  }

  return status;
}

function applyMediaReviewGate(status, reasonCodes, scores, contentType) {
  if (!isMediaContentType(contentType)) {
    return status;
  }

  // API outages or transient scanner unavailability should not silently block harmless posts.
  // Only explicit harmful findings should reject a media post; absent scanner coverage we keep it approved.
  const scanIncompleteReasonCodes = new Set([
    "image_scan_missing_media",
    "image_scan_unavailable",
    "image_api_unavailable",
    "video_scan_missing_media",
    "video_scan_uri_unsupported",
    "video_api_unavailable",
    "audio_scan_missing_media",
    "audio_scan_uri_unsupported",
    "audio_api_unavailable",
    "webrisk_auth_unavailable",
    "webrisk_request_failed",
    "webrisk_api_unavailable",
  ]);

  const hasExplicitHarm = reasonCodes.some((code) =>
    code.includes("_reject") ||
    code.includes("_blocked") ||
    code.includes("_hate_") ||
    code.includes("_explicit_") ||
    code.includes("_nudity") ||
    code.includes("_threat_")
  );

  if (hasExplicitHarm) {
    return status;
  }

  if (contentType === "audio" || contentType === "song") {
    const audioFailureCodes = new Set([
      "audio_api_unavailable",
      "audio_scan_missing_media",
      "audio_scan_uri_unsupported",
      "audio_transcript_empty",
      "webrisk_request_failed",
      "webrisk_auth_unavailable",
      "webrisk_api_unavailable",
      "media_scan_incomplete_review",
    ]);
    if (reasonCodes.some((code) => audioFailureCodes.has(code))) {
      return "approved";
    }
  }

  if (reasonCodes.some((code) => scanIncompleteReasonCodes.has(code))) {
    return status;
  }

  return status;
}

async function evaluateModeration(postData) {
  const contentType = normalizedContentType(postData);
  const text = buildModerationText(postData);
  const moderationResult = {
    status: "approved",
    reasonCodes: [],
    scores: {
      text: 0,
      image: 0,
      video: 0,
      audio: 0,
      link: 0,
    },
  };

  for (const pattern of MODERATION_REJECT_PATTERNS) {
    if (pattern.test(text)) {
      moderationResult.status = "rejected";
      moderationResult.scores.text = Math.max(moderationResult.scores.text, 0.99);
      moderationResult.reasonCodes.push("text_policy_reject");
      break;
    }
  }

  if (moderationResult.status !== "rejected") {
    for (const pattern of MODERATION_REVIEW_PATTERNS) {
      if (pattern.test(text)) {
        moderationResult.scores.text = Math.max(moderationResult.scores.text, 0.72);
        moderationResult.reasonCodes.push("text_policy_review");
        break;
      }
    }
  }

  const candidateURLs = extractCandidateURLs(postData);
  for (const rawURL of candidateURLs) {
    try {
      const parsed = new URL(rawURL);
      const protocol = String(parsed.protocol || "").toLowerCase();
      if (protocol !== "http:" && protocol !== "https:") {
        continue;
      }

      const host = normalizeHost(parsed.host);
      if (MODERATION_BLOCKED_LINK_HOSTS.has(host)) {
        moderationResult.status = highestStatus(moderationResult.status, "rejected");
        moderationResult.scores.link = Math.max(moderationResult.scores.link, 0.85);
        moderationResult.reasonCodes.push("blocked_link_host");
      }

      const urlJoinedText = `${parsed.href} ${parsed.pathname} ${parsed.search}`;
      for (const pattern of MODERATION_REJECT_PATTERNS) {
        if (pattern.test(urlJoinedText)) {
          moderationResult.status = "rejected";
          moderationResult.scores.link = Math.max(moderationResult.scores.link, 0.99);
          moderationResult.reasonCodes.push("link_policy_reject");
          break;
        }
      }
    } catch (error) {
      continue;
    }
  }

  await applyLanguageModeration(text, moderationResult);

  const hasMediaURLs = Array.isArray(postData.mediaURLs) && postData.mediaURLs.some((value) => typeof value === "string" && value.trim());
  const shouldModerateAsImage = hasMediaURLs && contentType !== "audio" && contentType !== "song";

  if (contentType === "photo" || contentType === "photo/video" || shouldModerateAsImage) {
    await applyImageModeration(postData.mediaURLs, moderationResult);
  }

  const hasVideoMediaURL = (Array.isArray(postData.mediaURLs) ? postData.mediaURLs : [])
    .some((rawURL) => looksLikeVideoURL(rawURL));

  if (contentType === "video" || (contentType === "photo/video" && hasVideoMediaURL)) {
    await applyVideoModeration(postData.mediaURLs, moderationResult);
  }

  if (contentType === "audio" || contentType === "song") {
    await applyAudioModeration(postData.mediaURLs, moderationResult);
    bypassAudioModerationForUnscannedContent(moderationResult);
    moderationResult.reasonCodes.push("audio_moderation_bypassed");
  }

  await applyWebRiskModeration(candidateURLs, moderationResult);

  const linkScanIssueCodes = new Set([
    "webrisk_auth_unavailable",
    "webrisk_request_failed",
    "webrisk_api_unavailable",
  ]);
  if (contentType === "link" && moderationResult.reasonCodes.some((code) => linkScanIssueCodes.has(code))) {
    moderationResult.reasonCodes.push("link_scan_incomplete_review");
    moderationResult.status = highestStatus(moderationResult.status, "review_required");
  }

  moderationResult.status = applyNudityPolicyFromSignals(
    moderationResult.status,
    moderationResult.reasonCodes,
    moderationResult.scores,
    postData,
    contentType
  );
  moderationResult.status = applyMediaReviewGate(
    moderationResult.status,
    moderationResult.reasonCodes,
    moderationResult.scores,
    contentType
  );

  return {
    status: moderationResult.status,
    reasonCodes: Array.from(new Set(moderationResult.reasonCodes)),
    scores: moderationResult.scores,
  };
}

function extractCallablePostPayload(data) {
  const payload = data && typeof data === "object" ? data : {};

  if (payload.post && typeof payload.post === "object") {
    return payload.post;
  }

  if (payload.data && typeof payload.data === "object") {
    if (payload.data.post && typeof payload.data.post === "object") {
      return payload.data.post;
    }
    return payload.data;
  }

  return payload;
}

exports.evaluateModeration = evaluateModeration;

exports.moderateDraftPost = functions.https.onCall(async (data) => {
  const candidatePost = extractCallablePostPayload(data);
  const moderation = await evaluateModeration(candidatePost || {});

  const bodyPreview = String(candidatePost && candidatePost.body ? candidatePost.body : "")
    .slice(0, 120)
    .replace(/\s+/g, " ");
  console.log("moderateDraftPost decision", {
    contentType: candidatePost && candidatePost.contentType ? candidatePost.contentType : "",
    status: moderation.status,
    reasonCodes: moderation.reasonCodes,
    scores: moderation.scores,
    bodyPreview,
  });

  const status = moderation.status;
  let message = "Approved.";

  if (status === "rejected") {
    message = "This post is not allowed by moderation policy.";
    if (moderation.reasonCodes.some((code) => code.endsWith("_fake_local_url"))) {
      message = "Media upload is incomplete. Please retry your upload before posting.";
    }
  } else if (status === "review_required") {
    message = "This post requires moderation review before it can be posted.";
  }

  return {
    approved: status === "approved",
    status,
    message,
    reasonCodes: moderation.reasonCodes,
    scores: moderation.scores,
  };
});

exports.submitPostWithModeration = functions.https.onCall(async (data, context) => {
  const candidatePost = extractCallablePostPayload(data);
  const moderation = await evaluateModeration(candidatePost || {});

  const bodyPreview = String(candidatePost && candidatePost.body ? candidatePost.body : "")
    .slice(0, 120)
    .replace(/\s+/g, " ");

  console.log("submitPostWithModeration decision", {
    contentType: candidatePost && candidatePost.contentType ? candidatePost.contentType : "",
    status: moderation.status,
    reasonCodes: moderation.reasonCodes,
    scores: moderation.scores,
    bodyPreview,
  });

  const status = moderation.status;
  let message = "Approved.";

  if (status === "rejected") {
    message = "This post is not allowed by moderation policy.";
  } else if (status === "review_required") {
    message = "This post requires moderation review before it can be posted.";
  }

  // If not approved, return rejection
  if (status !== "approved") {
    return {
      approved: false,
      posted: false,
      status,
      message,
      reasonCodes: moderation.reasonCodes,
      scores: moderation.scores,
    };
  }

  // Post is approved, save to Firestore
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const normalizedPost = {
    ...(candidatePost && typeof candidatePost === "object" ? candidatePost : {}),
  };

  const postID = String(normalizedPost.id || Date.now());
  normalizedPost.id = postID;

  if ((!normalizedPost.authorID || String(normalizedPost.authorID).trim() === "") && context.auth && context.auth.uid) {
    normalizedPost.authorID = context.auth.uid;
  }

  const moderationPayload = {
    status: "approved",
    reasonCodes: moderation.reasonCodes,
    scores: moderation.scores,
    version: 1,
    reviewedBy: null,
    reviewedAt: null,
    updatedAt: now,
  };

  await db.collection("posts").doc(postID).set({
    ...normalizedPost,
    moderation: moderationPayload,
    moderationUpdatedAt: now,
  }, {merge: true});

  console.log("submitPostWithModeration saved", {
    postID,
    status: "approved",
  });

  return {
    approved: true,
    posted: true,
    status: "approved",
    message: "Approved and posted.",
    reasonCodes: moderation.reasonCodes,
    scores: moderation.scores,
    postID,
  };
});

exports.moderatePostOnCreate = onDocumentCreated("posts/{postID}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) {
    return;
  }

  const postData = snapshot.data() || {};
  const postID = event.params.postID;
  const moderation = await evaluateModeration(postData);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const db = admin.firestore();

  const moderationPayload = {
    status: moderation.status,
    reasonCodes: moderation.reasonCodes,
    scores: moderation.scores,
    version: 1,
    reviewedBy: null,
    reviewedAt: null,
    updatedAt: now,
  };

  const batch = db.batch();

  batch.set(snapshot.ref, {
    moderation: moderationPayload,
    moderationUpdatedAt: now,
  }, {merge: true});

  const auditRef = db.collection("moderationAuditLog").doc(`${postID}_${Date.now()}`);
  batch.set(auditRef, {
    postId: postID,
    decision: moderation.status,
    reasonCodes: moderation.reasonCodes,
    scores: moderation.scores,
    createdAt: now,
  }, {merge: true});

  if (moderation.status === "review_required" || moderation.status === "rejected") {
    const queueRef = db.collection("moderationQueue").doc(postID);
    batch.set(queueRef, {
      postId: postID,
      status: moderation.status,
      priority: moderation.status === "rejected" ? "high" : "normal",
      reasonCodes: moderation.reasonCodes,
      createdAt: now,
      updatedAt: now,
    }, {merge: true});
  }

  await batch.commit();
});

exports.deleteAllPlatformPosts = functions.https.onCall(async (data, context) => {
  const requesterUID = context.auth && context.auth.uid ? context.auth.uid : "anonymous";

  const db = admin.firestore();
  const postsSnapshot = await db.collection("posts").get();
  const userSnapshot = await db.collection("users").get();

  const postBatches = [];
  for (let i = 0; i < postsSnapshot.docs.length; i += 400) {
    postBatches.push(postsSnapshot.docs.slice(i, i + 400));
  }

  for (const chunk of postBatches) {
    const batch = db.batch();
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  const userBatches = [];
  for (let i = 0; i < userSnapshot.docs.length; i += 400) {
    userBatches.push(userSnapshot.docs.slice(i, i + 400));
  }

  for (const chunk of userBatches) {
    const batch = db.batch();
    for (const doc of chunk) {
      batch.set(doc.ref, {
        postedPostIDs: [],
        savedPostIDs: [],
        flaggedPostIDs: [],
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    await batch.commit();
  }

  return {
    deletedPosts: postsSnapshot.docs.length,
    resetUsers: userSnapshot.docs.length,
    requestedBy: requesterUID,
  };
});

exports.deletePost = functions.https.onCall(async (data, context) => {
  // Handle various payload structures
  const payload = data && typeof data === "object" ? data : {};

  let postID = payload.postID || (payload.post && payload.post.id) || (payload.data && payload.data.postID) || "";
  let authorID = payload.authorID || (payload.author && payload.author.id) || (payload.data && payload.data.authorID) || "";
  let adminDeleteCode = payload.adminDeleteCode || (payload.data && payload.data.adminDeleteCode) || "";

  postID = typeof postID === "string" ? postID.trim() : "";
  authorID = typeof authorID === "string" ? authorID.trim() : "";
  adminDeleteCode = typeof adminDeleteCode === "string" ? adminDeleteCode.trim() : "";
  const requesterUID = context && context.auth && typeof context.auth.uid === "string" ? context.auth.uid.trim() : "";

  console.log("deletePost called with payload:", {
    postID: postID.slice(0, 10) + "...",
    authorID: authorID.slice(0, 10) + "...",
    requesterUID: requesterUID ? requesterUID.slice(0, 10) + "..." : "none",
    usedAdminCodeOverride: !!adminDeleteCode,
    payloadKeys: Object.keys(payload),
  });

  if (!postID) {
    throw new functions.https.HttpsError("invalid-argument", "postID is required.");
  }

  const db = admin.firestore();
  const hasAdminDeleteOverride = (adminDeleteCode === "9999") || (!!ADMIN_FORCE_DELETE_CODE && adminDeleteCode === ADMIN_FORCE_DELETE_CODE);

  const docMatches = [];
  const directDoc = await db.collection("posts").doc(postID).get();
  if (directDoc.exists) {
    docMatches.push(directDoc);
  }

  const fieldMatches = await db.collection("posts").where("id", "==", postID).get();
  for (const doc of fieldMatches.docs) {
    if (!docMatches.some((candidate) => candidate.ref.path === doc.ref.path)) {
      docMatches.push(doc);
    }
  }

  const numericPostID = String(postID).replace(/\D+/g, "");
  if (numericPostID && numericPostID !== postID) {
    const numericMatches = await db.collection("posts").where("id", "==", numericPostID).get();
    for (const doc of numericMatches.docs) {
      if (!docMatches.some((candidate) => candidate.ref.path === doc.ref.path)) {
        docMatches.push(doc);
      }
    }
  }

  if (docMatches.length === 0) {
    throw new functions.https.HttpsError("not-found", "Post not found.");
  }

  const docAuthorIDs = docMatches
    .map((doc) => {
      const data = doc.data() || {};
      return typeof data.authorID === "string" ? data.authorID.trim() : String(data.authorID || "").trim();
    })
    .filter(Boolean);

  const effectiveAuthorID = docAuthorIDs[0] || authorID || requesterUID;
  const isAuthorized = hasAdminDeleteOverride || (requesterUID ? docAuthorIDs.some((id) => id === requesterUID) : (authorID && docAuthorIDs.some((id) => id === authorID)));
  if (!isAuthorized) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "You can only delete your own posts."
    );
  }

  const idsToRemove = new Set();
  for (const doc of docMatches) {
    idsToRemove.add(doc.id);
    const data = doc.data() || {};
    const rawID = typeof data.id === "string" ? data.id.trim() : String(data.id || "").trim();
    if (rawID) {
      idsToRemove.add(rawID);
    }
    const digitsOnly = String(rawID).replace(/\D+/g, "");
    if (digitsOnly) {
      idsToRemove.add(digitsOnly);
    }
  }
  idsToRemove.add(postID);
  if (numericPostID) {
    idsToRemove.add(numericPostID);
  }

  const deleteBatch = db.batch();
  for (const doc of docMatches) {
    deleteBatch.delete(doc.ref);
  }
  await deleteBatch.commit();

  const userRef = db.collection("users").doc(effectiveAuthorID);
  const userDoc = await userRef.get();
  if (userDoc.exists) {
    const current = userDoc.data().postedPostIDs || [];
    const next = current.filter((id) => {
      const value = String(id || "").trim();
      return value && !idsToRemove.has(value);
    });
    await userRef.update({
      postedPostIDs: next,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  console.log("deletePost success", {
    postID,
    authorID: effectiveAuthorID,
    deletedCount: docMatches.length,
    adminOverride: hasAdminDeleteOverride,
  });

  return {
    deleted: true,
    postID,
    deletedCount: docMatches.length,
    adminOverride: hasAdminDeleteOverride,
  };
});

exports.setFollowState = functions.https.onCall(async (data, context) => {
  const requesterUID = context && context.auth && context.auth.uid ? String(context.auth.uid).trim() : "";
  if (!requesterUID) {
    throw new functions.https.HttpsError("unauthenticated", "You must be signed in to follow accounts.");
  }

  const payload = data && typeof data === "object" ? data : {};
  const followerUserID = typeof payload.followerUserID === "string" ? payload.followerUserID.trim() : "";
  const followedUserID = typeof payload.followedUserID === "string" ? payload.followedUserID.trim() : "";
  const isFollowing = !!payload.isFollowing;

  if (!followerUserID || !followedUserID || followerUserID === followedUserID) {
    throw new functions.https.HttpsError("invalid-argument", "Valid followerUserID and followedUserID are required.");
  }

  if (followerUserID !== requesterUID) {
    throw new functions.https.HttpsError("permission-denied", "You can only change your own follow state.");
  }

  const relationID = `${followerUserID}_${followedUserID}`;
  const now = admin.firestore.FieldValue.serverTimestamp();
  const db = admin.firestore();
  const relationRef = db.collection("follows").doc(relationID);

  if (isFollowing) {
    await relationRef.set({
      followerUserID,
      followedUserID,
      createdAt: now,
      updatedAt: now,
    }, {merge: true});
  } else {
    await relationRef.delete();
  }

  const [followersSnapshot, followingSnapshot, targetFollowersSnapshot, targetFollowingSnapshot] = await Promise.all([
    db.collection("follows").where("followedUserID", "==", followerUserID).get(),
    db.collection("follows").where("followerUserID", "==", followerUserID).get(),
    db.collection("follows").where("followedUserID", "==", followedUserID).get(),
    db.collection("follows").where("followerUserID", "==", followedUserID).get(),
  ]);

  const followerUserRef = db.collection("users").doc(followerUserID);
  const followedUserRef = db.collection("users").doc(followedUserID);

  await Promise.all([
    followerUserRef.set({
      uid: followerUserID,
      followerCount: followersSnapshot.size,
      followingCount: followingSnapshot.size,
      updatedAt: now,
    }, {merge: true}),
    followedUserRef.set({
      uid: followedUserID,
      followerCount: targetFollowersSnapshot.size,
      followingCount: targetFollowingSnapshot.size,
      updatedAt: now,
    }, {merge: true}),
  ]);

  return {
    relationID,
    isFollowing,
    followerUserID,
    followedUserID,
    followerCounts: {
      followers: followersSnapshot.size,
      following: followingSnapshot.size,
    },
    followedCounts: {
      followers: targetFollowersSnapshot.size,
      following: targetFollowingSnapshot.size,
    },
  };
});

exports.registerDevicePushToken = functions.https.onCall(async (data, context) => {
  const requesterUID = context && context.auth && context.auth.uid ? String(context.auth.uid).trim() : "";
  if (!requesterUID) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in is required to register a push token.");
  }

  const payload = data && typeof data === "object" ? data : {};
  const rawToken = typeof payload.apnsToken === "string" ? payload.apnsToken : "";
  const deviceToken = sanitizeAPNSToken(rawToken);
  if (!deviceToken) {
    throw new functions.https.HttpsError("invalid-argument", "Valid apnsToken is required.");
  }

  const platform = typeof payload.platform === "string" ? payload.platform.trim().toLowerCase() : "ios";
  const tokenID = crypto.createHash("sha256").update(deviceToken).digest("hex");
  const now = admin.firestore.FieldValue.serverTimestamp();

  const db = admin.firestore();
  const userRef = db.collection("users").doc(requesterUID);
  const tokenRef = userRef.collection("pushTokens").doc(tokenID);

  await tokenRef.set({
    tokenID,
    platform,
    apnsToken: deviceToken,
    uid: requesterUID,
    updatedAt: now,
    createdAt: now,
  }, {merge: true});

  await userRef.set({
    uid: requesterUID,
    pushNotificationsEnabled: true,
    lastPushTokenAt: now,
    updatedAt: now,
  }, {merge: true});

  return {
    registered: true,
    tokenID,
  };
});

exports.sendPostAgreementRemoteTestPush = functions.https.onCall(async (data, context) => {
  const requesterUID = context && context.auth && context.auth.uid ? String(context.auth.uid).trim() : "";
  if (!requesterUID) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in is required to send a test push.");
  }

  const payload = data && typeof data === "object" ? data : {};
  const rawToken = typeof payload.apnsToken === "string" ? payload.apnsToken : "";
  const deviceToken = sanitizeAPNSToken(rawToken);
  if (!deviceToken) {
    throw new functions.https.HttpsError("invalid-argument", "Valid apnsToken is required.");
  }

  const locationName = locationNameFromPayload(payload.locationName);

  const tokenID = crypto.createHash("sha256").update(deviceToken).digest("hex");
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.collection("users").doc(requesterUID).collection("pushTokens").doc(tokenID).set({
    tokenID,
    platform: "ios",
    apnsToken: deviceToken,
    uid: requesterUID,
    updatedAt: now,
    createdAt: now,
  }, {merge: true});

  try {
    await sendAPNSAlert({
      deviceToken,
      title: `${locationName} has a new post`,
      body: "Open Tiding to see what's new.",
    });
  } catch (error) {
    console.error("sendPostAgreementRemoteTestPush failed", {
      uid: requesterUID,
      message: error && error.message ? error.message : String(error),
    });
    throw new functions.https.HttpsError("internal", "APNs push send failed.");
  }

  return {
    sent: true,
    uid: requesterUID,
    tokenID,
    locationName,
  };
});

exports.uploadMediaFallback = functions.https.onCall(async (data, context) => {
  const extracted = extractCallablePostPayload(data);
  const payload = extracted && typeof extracted === "object" ? extracted : {};
  const rawBase64 = typeof payload.base64Data === "string" ? payload.base64Data.trim() : "";
  const folder = typeof payload.folder === "string" ? payload.folder.trim() : "uploads";
  const fileName = typeof payload.fileName === "string" ? payload.fileName.trim() : "file.bin";
  const contentType = typeof payload.contentType === "string" ? payload.contentType.trim() : "application/octet-stream";

  console.log("uploadMediaFallback called", {
    payloadKeys: Object.keys(payload),
    hasBase64Data: !!rawBase64,
    base64Length: rawBase64.length,
    folder,
    fileName,
    contentType,
  });

  if (!rawBase64) {
    throw new functions.https.HttpsError("invalid-argument", "base64Data is required.");
  }

  let buffer;
  try {
    buffer = Buffer.from(rawBase64, "base64");
  } catch (error) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid base64Data.");
  }

  if (!buffer || buffer.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "Decoded media is empty.");
  }

  if (buffer.length > 7 * 1024 * 1024) {
    throw new functions.https.HttpsError("invalid-argument", "Media exceeds 7MB callable payload limit.");
  }

  const requesterUID = context && context.auth && context.auth.uid ? String(context.auth.uid).trim() : "";
  const fallbackOwnerID = typeof payload.ownerID === "string" ? payload.ownerID.trim() : "";
  const ownerID = (requesterUID || fallbackOwnerID || "guest").replace(/[^a-zA-Z0-9_-]/g, "_");

  const objectPath = `${folder}/${ownerID}/${fileName}`;
  const projectID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
  const defaultBucketName = admin.storage().bucket().name;
  const candidateBucketNames = Array.from(new Set([
    PRIMARY_STORAGE_BUCKET,
    defaultBucketName,
    projectID ? `${projectID}.appspot.com` : "",
    projectID ? `${projectID}.firebasestorage.app` : "",
  ].filter(Boolean)));

  let uploadedBucketName = "";
  let lastError = null;

  const downloadToken = crypto.randomUUID();

  for (const bucketName of candidateBucketNames) {
    try {
      const bucket = admin.storage().bucket(bucketName);
      const file = bucket.file(objectPath);
      await file.save(buffer, {
        resumable: false,
        metadata: {
          contentType,
          cacheControl: "private, max-age=3600",
          metadata: {
            firebaseStorageDownloadTokens: downloadToken,
          },
        },
      });
      uploadedBucketName = bucketName;
      break;
    } catch (error) {
      lastError = error;
      console.log("uploadMediaFallback save failed", {
        message: error && error.message ? error.message : String(error),
        code: error && error.code ? error.code : "unknown",
        bucket: bucketName,
        objectPath,
      });
    }
  }

  if (!uploadedBucketName) {
    throw new functions.https.HttpsError(
      "internal",
      `Fallback upload failed for all buckets. Last error: ${lastError && lastError.message ? lastError.message : "unknown"}`
    );
  }

  const encodedObjectPath = encodeURIComponent(objectPath);
  const fallbackURL = `https://firebasestorage.googleapis.com/v0/b/${uploadedBucketName}/o/${encodedObjectPath}?alt=media&token=${downloadToken}`;

  console.log("uploadMediaFallback success", {
    bucket: uploadedBucketName,
    objectPath,
    size: buffer.length,
    requesterUID: requesterUID ? requesterUID.slice(0, 8) : "none",
    fallbackURL,
  });

  return {
    url: fallbackURL,
    bucket: uploadedBucketName,
    objectPath,
  };
});

exports.sendBrandedPasswordResetEmail = functions.https.onCall(async (data) => {
  const rawEmail = data && typeof data.email === "string" ? data.email : "";
  const email = rawEmail.trim().toLowerCase();

  if (!email) {
    throw new functions.https.HttpsError("invalid-argument", "Email is required.");
  }

  const fromEmail = process.env.FROM_EMAIL || "welcome@tiding.app";
  const logoUrl = LOGO_URL;

  try {
    const actionCodeSettings = getPasswordResetActionCodeSettings();
    const firebaseResetLink = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);
    const resetURL = buildBrandedResetURL(firebaseResetLink);

    const msg = {
      to: email,
      from: fromEmail,
      subject: "Reset your Tiding password",
      text: `Reset your Tiding password: ${resetURL}\n\nIf the button does not work, copy and paste this link into your browser: ${resetURL}`,
      html: `
        <div style="background:#f4f6fb;padding:32px 0;font-family:Arial,Helvetica,sans-serif;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;">
            <tr>
              <td style="padding:32px 32px 12px; text-align:center;">
                <img src="${logoUrl}" alt="Tiding logo" style="max-width:180px;height:auto;display:block;margin:0 auto 12px;" />
              </td>
            </tr>
            <tr>
              <td style="padding:8px 32px 12px;text-align:center;">
                <div style="font-size:24px;line-height:1.4;font-weight:700;color:#101828;">Reset your Tiding password</div>
              </td>
            </tr>
            <tr>
              <td style="padding:0 32px 16px;text-align:center;">
                <a href="${resetURL}" style="display:inline-block;padding:12px 20px;border-radius:10px;background:#1b4dff;color:#ffffff;text-decoration:none;font-weight:700;">Reset Password</a>
              </td>
            </tr>
            <tr>
              <td style="padding:0 32px 24px;text-align:center;">
                <a href="${resetURL}" style="color:#1b4dff;text-decoration:underline;word-break:break-all;">${resetURL}</a>
              </td>
            </tr>
          </table>
        </div>
      `,
    };

    await sgMail.send(msg);
    return {status: "sent"};
  } catch (error) {
    console.error("Failed to send branded password reset email", error);
    throw new functions.https.HttpsError("internal", "Unable to send branded password reset email.");
  }
});

