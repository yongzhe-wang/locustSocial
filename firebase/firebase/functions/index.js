// functions/index.js
// Node.js (CommonJS) Firebase Functions v2

"use strict";

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const fetch = require("node-fetch"); // v2.x
const FormData = require("form-data");
const crypto = require("crypto");
const { FieldValue } = require("firebase-admin/firestore");


// ----------------------------------------------------------------------------
// Admin init
// ----------------------------------------------------------------------------
admin.initializeApp({
  storageBucket: process.env.FB_DEFAULT_BUCKET, // e.g. "<project-id>.appspot.com"
});
const db = admin.firestore();

// ----------------------------------------------------------------------------
// Config
// ----------------------------------------------------------------------------
const REGION = process.env.FUNCTIONS_REGION || "us-central1";
// ----- CONFIG (replaces functions.config()) -----
// Optional override just for rank:

// Your FastAPI backend
const BACKEND_BASE = process.env.BACKEND_BASE || "http://127.0.0.1:8000";
const BACKEND_SECRET =
  process.env.BACKEND_SECRET || "this-is-my-local-secret-locustsocial";

const POSTS_URL = `${BACKEND_BASE}/api/posts`;
const USER_EVENT_URL = `${BACKEND_BASE}/api/user-event`;
const RANK_URL = `${BACKEND_BASE}/api/rank`;

// Attachment limits (mirror backend defaults; keep <= backend MAX_IMAGE_BYTES)
const MAX_IMAGE_BYTES = Number(process.env.MAX_IMAGE_BYTES || 10 * 1024 * 1024); // 10MB

// Debounce window to coalesce bursts of edits (ms)
const DEBOUNCE_MS = Number(process.env.DEBOUNCE_MS || 600);

// Retry policy for backend calls
const RETRY_MAX = Number(process.env.RETRY_MAX || 5);
const RETRY_BASE_MS = Number(process.env.RETRY_BASE_MS || 300);
const RETRY_MAX_MS = Number(process.env.RETRY_MAX_MS || 6000);

// Soft in-memory debounce per instance (best-effort)
const debounceMap = new Map(); // key: docPath, value: timestamp (ms)

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

/** Lightweight CORS responder */
function applyCors(req, res, methods = "GET, POST, OPTIONS") {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", methods);
  res.set("Access-Control-Allow-Headers", "content-type");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  return false;
}

/** Backoff helper with jitter & Retry-After support */
async function fetchWithRetry(url, opts, retryMax = RETRY_MAX) {
  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    attempt++;
    const resp = await fetch(url, opts);
    if (resp.ok) return resp;

    const status = resp.status;
    // Respect Retry-After header when present (429/503 typical)
    let waitMs = null;
    if (status === 429 || status === 503) {
      const ra = resp.headers.get("retry-after");
      if (ra) {
        const asInt = parseInt(ra, 10);
        if (!Number.isNaN(asInt)) {
          waitMs = asInt * 1000;
        } else {
          // HTTP-date format fallback: default small sleep
          waitMs = 1500;
        }
      }
    }

    if (attempt >= retryMax) {
      return resp; // give caller the failure to log/propagate
    }

    // Exponential backoff with jitter
    const base = waitMs ?? Math.min(
      RETRY_MAX_MS,
      RETRY_BASE_MS * Math.pow(2, attempt - 1)
    );
    const jitter = Math.floor(Math.random() * Math.max(100, base * 0.2));
    const sleep = base + jitter;

    logger.warn(`Retrying (${attempt}/${retryMax - 1}) ${url} after ${sleep} ms; status=${status}`);
    await new Promise((r) => setTimeout(r, sleep));
  }
}

/**
 * Extracts image reference from a post document.
 * Tries many common shapes:
 *  - direct HTTP(S) URL (e.g. post.imageUrl, post.image.url, arrays)
 *  - Firebase Storage REST URLs: .../b/<bucket>/o/<encodedPath>?...
 *  - gs://bucket/path
 *  - plain Storage path in post.imagePath (+ optional post.bucket)
 *
 * @param {object} post Firestore document data
 * @returns {{bucket?: string, objectPath?: string, httpUrl?: string, shape?: string}}
 */
function findImageRef(post) {
  try {
    logger.debug("[findImageRef] keys:", Object.keys(post || {}));
  } catch {
    /* no-op */
  }

  if (!post || typeof post !== "object") return {};

  const candidates = [
    post.imageUrl,
    post.imageURL,
    post.photoURL,
    post.downloadURL,
    post.storageURL,

    post.imagePath,
    post.storagePath,
    post.storageRef,
    post.objectPath,

    // nested
    post.image?.url,
    post.image?.downloadURL,
    post.image?.path,
    post.image?.objectPath,

    // arrays
    Array.isArray(post.images) ? post.images[0]?.url : undefined,
    Array.isArray(post.images) ? post.images[0]?.downloadURL : undefined,
    Array.isArray(post.images) ? post.images[0]?.path : undefined,
    Array.isArray(post.imageUrls) ? post.imageUrls[0] : undefined,
    Array.isArray(post.photos) ? post.photos[0]?.url : undefined,

    Array.isArray(post.media) ? post.media[0]?.url : undefined,
    Array.isArray(post.media) ? post.media[0]?.downloadURL : undefined,
    Array.isArray(post.media) ? post.media[0]?.thumbURL : undefined,
    Array.isArray(post.media) ? post.media[0]?.path : undefined,
  ].filter(Boolean);

  const raw = candidates.find(Boolean);
  logger.debug("[findImageRef] raw candidate:", raw);

  if (!raw) return {};

  // HTTP(S) URL
  if (typeof raw === "string" && /^https?:\/\//i.test(raw)) {
    // Try to parse Firebase Storage REST form
    const m1 = raw.match(/\/b\/([^/]+)\/o\/([^?]+)(?:\?|$)/); // bucket + encodedPath
    if (m1) {
      const bucket = decodeURIComponent(m1[1]);
      const objectPath = decodeURIComponent(m1[2]);
      logger.debug("[findImageRef] parsed REST URL ->", { bucket, objectPath });
      return { bucket, objectPath, httpUrl: raw, shape: "rest" };
    }
    // Generic http(s)
    return { httpUrl: raw, shape: "http" };
  }

  // gs://bucket/path
  if (typeof raw === "string" && raw.startsWith("gs://")) {
    const m = raw.match(/^gs:\/\/([^/]+)\/(.+)$/);
    if (m) {
      const bucket = m[1];
      const objectPath = m[2];
      logger.debug("[findImageRef] gs:// parsed ->", { bucket, objectPath });
      return { bucket, objectPath, shape: "gs" };
    }
  }

  // Plain storage path; rely on post.bucket or default app bucket
  if (typeof raw === "string") {
    const bucket = post.bucket || undefined;
    const objectPath = raw;
    logger.debug("[findImageRef] plain path ->", { bucket, objectPath });
    return { bucket, objectPath, shape: "path" };
  }

  return {};
}

/** Safe JSON parse for logs */
function tryJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

/** Build a stable sync hash of material fields sent to backend */
function computeSyncHash({ title, body, imageRef }) {
  const h = crypto.createHash("sha256");
  // Normalize undefineds to empty strings to keep stability
  const norm = JSON.stringify({
    title: title || "",
    body: body || "",
    image: imageRef
      ? {
          bucket: imageRef.bucket || "",
          objectPath: imageRef.objectPath || "",
          httpUrl: imageRef.httpUrl || "",
          shape: imageRef.shape || "",
        }
      : null,
  });
  h.update(norm);
  return h.digest("hex");
}

/** Best-effort debounce by doc path */
function shouldDebounce(docPath, now = Date.now()) {
  const last = debounceMap.get(docPath) || 0;
  if (now - last < DEBOUNCE_MS) return true;
  debounceMap.set(docPath, now);
  return false;
}

// ----------------------------------------------------------------------------
// Firestore → Backend: push created/updated posts to /api/posts
// ----------------------------------------------------------------------------

exports.pushPostToBackend = onDocumentWritten(
  {
    document: "posts/{postId}",
    region: REGION,
    memory: "256MiB",
    maxInstances: 5, // keep modest to avoid flooding backend/Cohere
    // (optionally) cpu: 0.5,
    // (optionally) concurrency: 10,
  },
  async (event) => {
    const afterSnap = event.data && event.data.after;
    const beforeSnap = event.data && event.data.before;
    const after = afterSnap && afterSnap.data();
    if (!after) return; // deleted or empty

    const docRef = afterSnap.ref;
    const docPath = docRef.path;
    const postId = event.params.postId;

    // Basic fields
    const title = after.title || "";
    const body = after.text || after.body || "";

    const imageRef = findImageRef(after);
    const syncHash = computeSyncHash({ title, body, imageRef });

    const prevHash =
      (beforeSnap && beforeSnap.exists && beforeSnap.get("backendSyncHash")) ||
      null;
    const currHash = after.backendSyncHash || null;

    // If only our bookkeeping fields changed, or the content hash matches, skip
    if (currHash && currHash === syncHash) {
      logger.debug("[pushPostToBackend] no-op (hash match)", { docPath, postId });
      return;
    }
    if (prevHash && prevHash === syncHash && !currHash) {
      // Edge case on first write after we just updated; safe to skip
      logger.debug("[pushPostToBackend] no-op (prevHash match)", { docPath, postId });
      return;
    }

    // Coalesce rapid edits within a short window
    if (shouldDebounce(docPath)) {
      logger.info("[pushPostToBackend] debounced burst", { docPath, postId });
      // Small wait to let subsequent edits land, then re-read current data
      await new Promise((r) => setTimeout(r, DEBOUNCE_MS));
      const fresh = await docRef.get();
      if (fresh.exists) {
        const data = fresh.data() || {};
        const freshImageRef = findImageRef(data);
        const freshHash = computeSyncHash({
          title: data.title || "",
          body: data.text || data.body || "",
          imageRef: freshImageRef,
        });
        if (freshHash !== syncHash) {
          // Allow the later invocation to handle it
          logger.info("[pushPostToBackend] newer content detected; skipping older push", {
            docPath,
            postId,
          });
          return;
        }
      }
    }

    // Prepare form
    const form = new FormData();
    form.append("firebase_id", postId);
    form.append("title", title);
    form.append("body", body);

    // Attach image when available and within size cap
    let attached = false;
    if (imageRef.objectPath) {
      try {
        const defaultBucket = admin.app().options.storageBucket; // may be undefined
        const bucket =
          imageRef.bucket || defaultBucket
            ? admin.storage().bucket(imageRef.bucket || defaultBucket)
            : null;

        if (!bucket) {
          logger.warn(
            "[pushPostToBackend] no bucket configured; skip Storage download",
            imageRef
          );
        } else {
          logger.debug("[pushPostToBackend] Storage read", {
            bucket: bucket.name,
            objectPath: imageRef.objectPath,
          });
          const [buf] = await bucket.file(imageRef.objectPath).download();
          if (buf.length <= MAX_IMAGE_BYTES) {
            form.append("image", buf, {
              filename:
                imageRef.objectPath.split("/").pop() || "upload.jpg",
            });
            attached = true;
            logger.info("Attached image via Storage", {
              bucket: bucket.name,
              objectPath: imageRef.objectPath,
              bytes: buf.length,
            });
          } else {
            logger.warn("Image exceeds size cap; skipping attachment", {
              bytes: buf.length,
              cap: MAX_IMAGE_BYTES,
            });
          }
        }
      } catch (e) {
        logger.error("Storage download failed; will try HTTP if available", e);
      }
    }

    if (!attached && imageRef.httpUrl) {
      try {
        logger.debug("[pushPostToBackend] HTTP fetch", { url: imageRef.httpUrl });
        const r = await fetch(imageRef.httpUrl);
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        const buf = await r.buffer();
        if (buf.length <= MAX_IMAGE_BYTES) {
          form.append("image", buf, { filename: "upload.jpg" });
          attached = true;
          logger.info("Attached image via HTTP", {
            url: imageRef.httpUrl,
            bytes: buf.length,
          });
        } else {
          logger.warn("HTTP image exceeds size cap; skipping", {
            bytes: buf.length,
            cap: MAX_IMAGE_BYTES,
          });
        }
      } catch (e) {
        logger.error("HTTP image fetch failed", e);
      }
    }

    logger.info("POST → backend /api/posts", {
      postId,
      hasImage: attached,
      docPath,
    });

    const resp = await fetchWithRetry(
      POSTS_URL,
      {
        method: "POST",
        headers: {
          "x-firebase-token": BACKEND_SECRET,
          ...form.getHeaders(),
        },
        body: form,
      },
      RETRY_MAX
    );

    const text = await resp.text();
    if (!resp.ok) {
      logger.error("Backend error", resp.status, tryJson(text));
      throw new Error(`Backend ${resp.status}`);
    }
    logger.info("Backend OK", { status: resp.status, preview: String(text).slice(0, 400) });

    // Mark synced to suppress redundant re-triggers.
    await docRef.set(
      {
        backendSyncedAt: FieldValue.serverTimestamp(),
        backendSyncHash: syncHash,
      },
      { merge: true }
    );
  }
);






exports.forwardInteractionToBackend = onDocumentWritten(
  {
    document: "users/{uid}/interactions/{postId}",
    region: REGION,
    memory: "128MiB",
    maxInstances: 10,
  },
  async (event) => {
    const { uid, postId } = event.params;
    const before = event.data.before?.data() || {};
    const after  = event.data.after?.data() || {};
    if (!event.data.after || !event.data.after.exists) {
      // Interaction deleted; you can optionally send a “clear” event.
      logger.info("Interaction doc removed, skipping", { uid, postId });
      return;
    }

    // Detect changes
    const changed = {};
    if (before.like !== after.like && typeof after.like === "boolean") {
      changed.like = after.like ? 1 : 0; // treat as weight 1/0
    }
    if (before.save !== after.save && typeof after.save === "boolean") {
      changed.save = after.save ? 1 : 0;
    }
    // For viewSecs we only send the positive delta
    const prevSecs = Number(before.viewSecs || 0);
    const nextSecs = Number(after.viewSecs || 0);
    const deltaSecs = Math.max(0, nextSecs - prevSecs);
    if (deltaSecs > 0) {
      changed.view = deltaSecs; // use key "view" for the backend etype
    }

    const keys = Object.keys(changed);
    if (keys.length === 0) {
      logger.debug("No meaningful interaction changes", { uid, postId });
      return;
    }

    // Send one event per changed key
    for (const key of keys) {
      const payload = {
        uid,
        etype: key,                   // "like" | "save" | "view"
        firebase_post_id: postId,
        weight: changed[key],         // 1/0 or seconds delta
      };

      try {
        const r = await fetch(USER_EVENT_URL, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-firebase-token": BACKEND_SECRET,
          },
          body: JSON.stringify(payload),
        });

        const txt = await r.text();
        if (!r.ok) {
          logger.error("forwardInteractionToBackend error", r.status, txt, { payload });
        } else {
          logger.info("forwardInteractionToBackend OK", { payload, status: r.status });
        }
      } catch (e) {
        logger.error("forwardInteractionToBackend failed", e, { payload });
      }
    }

    // Optionally stamp a sync marker (helps avoid loops in future if you mirror anything back)
    try {
      await event.data.after.ref.set(
        { lastPushedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
    } catch (e) {
      logger.warn("Failed to stamp lastPushedAt", e);
    }
  }
);
function setCORS(req, res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
}

// GET /rankProxy?uid=...&limit=15&cursor=abc123
exports.rankProxy = onRequest({ region: REGION }, async (req, res) => {
  setCORS(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");

  try {
    const uid = (req.query.uid && String(req.query.uid)) || "";
    const limit = (req.query.limit && String(req.query.limit)) || "15";
    const cursor = (req.query.cursor && String(req.query.cursor)) || "";

    const qs = new URLSearchParams({
      uid,
      limit,
      ...(cursor ? { cursor } : {}),
    }).toString();

    const target = `${BACKEND_BASE}/api/rank?${qs}`;

    const upstream = await fetch(target, { method: "GET" });
    const bodyText = await upstream.text();

    res
      .status(upstream.status)
      .set("content-type", upstream.headers.get("content-type") || "application/json")
      .send(bodyText);
  } catch (err) {
    console.error("[rankProxy] error:", err);
    res.status(502).json({ error: "Upstream error", detail: String(err) });
  }
});