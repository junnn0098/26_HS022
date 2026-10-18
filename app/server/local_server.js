const http = require("http");
const https = require("https");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const configuredPort = Number(process.env.PORT || 8000);
const PORT = Number.isFinite(configuredPort) ? configuredPort : 8000;
// 실제 휴대폰·Jetson 시연을 위해 기본값은 모든 인터페이스(0.0.0.0). 로컬 전용이면 HOST=127.0.0.1
const HOST = String(process.env.HOST || "").trim() || "0.0.0.0";
const REAL_SENSOR_ONLY = String(process.env.REAL_SENSOR_ONLY || "")
  .trim()
  .toLowerCase() === "true";
// 설정된 경우에만 POST 전체와 상태 조회 GET에 `Authorization: Bearer <token>`을 요구한다.
const API_TOKEN = String(process.env.HANIUM_API_TOKEN || "").trim();
// 기본은 같은 출처(관리자 페이지)만 허용. 다른 출처는 쉼표로 구분해 지정하고 "*"는 전체 허용.
const CORS_ORIGINS = String(process.env.HANIUM_CORS_ORIGIN || "")
  .split(",")
  .map((origin) => origin.trim().replace(/\/+$/, ""))
  .filter(Boolean);
const PROTECTED_GET_PATHS = new Set([
  "/state",
  "/emergency-info",
  "/guardians",
  "/alerts",
  "/settings",
  "/location/latest",
]);
const JSON_BODY_POST_PATHS = new Set([
  "/device/register",
  "/care-recipient/safe",
  "/alerts/delete",
  "/guardians",
  "/guardians/update",
  "/guardians/delete",
  "/settings",
  "/emergency-info",
  "/sensor/update",
  "/scenario",
]);
const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const STATE_FILE = path.join(__dirname, "dev_state.json");
const WARNING_NOTIFICATION_CHANNEL_ID = "hanium_warning_alerts_v2";
const WARNING_NOTIFICATION_SOUND = "hanium_warning_alert";

const defaultState = {
  tokens: [],
  deviceTokens: [],
  guardians: [
    { id: 1, name: "김영희 어르신", phone: "010-0000-0000", role: "보호 대상" },
    { id: 2, name: "홍길동 보호자", phone: "010-1234-5678", role: "1순위 보호자" },
  ],
  settings: {
    fallDetection: true,
    stillnessDetection: true,
    stillnessMinutes: 30,
    intrusionDetection: true,
    showPath: true,
    showSensors: true,
    locationSharingEnabled: true,
    largeTextMode: false,
    miniatureSize: "medium",
  },
  emergencyInfo: {
    address: "○○시 ○○구 ○○로 123, 101동 1001호",
    accessNote: "공동현관 호출 후 보호자에게 연락해 주세요.",
    medicalNote: "고혈압 약 복용 중. 낙상 의심 시 무리하게 일으키지 말아 주세요.",
    hospital: "가까운 응급실: ○○병원 응급실",
  },
  alerts: [
    {
      id: 1,
      type: "danger",
      title: "낙상 의심 움직임 감지",
      message: "거실 소파 근처에서 급격한 쓰러짐 패턴이 감지됐어요.",
      room: "거실",
      time: "오후 3:18",
      urgent: true,
      resolved: false,
    },
    {
      id: 2,
      type: "warning",
      title: "현관 접근이 감지됐어요",
      message: "현관 위험 구역에 접근했어요.",
      room: "현관",
      time: "오후 1:42",
      urgent: false,
      resolved: false,
    },
  ],
};

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function normalizeDeviceRole(value) {
  const role = String(value || "guardian").trim();
  if (role === "careRecipient" || role === "care_recipient" || role === "recipient") {
    return "careRecipient";
  }
  if (role.includes("피보호") || role.includes("대상")) {
    return "careRecipient";
  }
  return "guardian";
}

function normalizeDeviceTokens(deviceTokens, legacyTokens = []) {
  const byToken = new Map();

  function add(token, role) {
    const cleanToken = typeof token === "string" ? token.trim() : "";
    if (!cleanToken) return;
    const cleanRole = normalizeDeviceRole(role);
    const current =
      byToken.get(cleanToken) || {
        token: cleanToken,
        roles: [],
        lastRole: cleanRole,
        updatedAt: new Date().toISOString(),
      };
    if (!current.roles.includes(cleanRole)) current.roles.push(cleanRole);
    current.lastRole = cleanRole;
    byToken.set(cleanToken, current);
  }

  if (Array.isArray(deviceTokens)) {
    for (const item of deviceTokens) {
      if (typeof item === "string") {
        add(item, "guardian");
        continue;
      }
      if (!item || typeof item !== "object") continue;
      const roles = Array.isArray(item.roles) ? item.roles : [item.role || item.lastRole];
      for (const role of roles) add(item.token, role);
    }
  }

  if (Array.isArray(legacyTokens)) {
    for (const token of legacyTokens) add(token, "guardian");
  }

  return [...byToken.values()];
}

function loadState() {
  try {
    if (!fs.existsSync(STATE_FILE)) return defaultState;
    const saved = JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
    const legacyTokens = Array.isArray(saved.tokens)
      ? saved.tokens
      : defaultState.tokens;
    // 이전 상태 파일의 출입 비밀번호(doorPassword)는 더 이상 저장·노출하지 않는다.
    const { doorPassword: _droppedDoorPassword, ...savedEmergencyInfo } =
      saved.emergencyInfo || {};
    return {
      tokens: legacyTokens,
      deviceTokens: normalizeDeviceTokens(saved.deviceTokens, legacyTokens),
      guardians: Array.isArray(saved.guardians)
        ? saved.guardians
        : defaultState.guardians,
      settings: { ...defaultState.settings, ...(saved.settings || {}) },
      emergencyInfo: {
        ...defaultState.emergencyInfo,
        ...savedEmergencyInfo,
      },
      alerts: Array.isArray(saved.alerts) ? saved.alerts : defaultState.alerts,
    };
  } catch (error) {
    console.warn("저장된 mock 상태를 읽지 못해 기본값으로 시작합니다.", error.message);
    return defaultState;
  }
}

let state = loadState();
let tokens = state.tokens;
let deviceTokens = normalizeDeviceTokens(state.deviceTokens, tokens);
let guardians = state.guardians;
let settings = state.settings;
let emergencyInfo = state.emergencyInfo;
let alerts = state.alerts;
let forcedScenario = null;
let latestLocation = null;
let manualSensorUntil = 0;
const wsClients = new Set();

function allRegisteredTokens() {
  return [
    ...new Set([
      ...tokens,
      ...deviceTokens.map((device) => device.token),
    ]),
  ].filter(Boolean);
}

function recipientTokens(targetRole = "guardian") {
  const role = normalizeDeviceRole(targetRole);
  const matching = deviceTokens
    .filter((device) => Array.isArray(device.roles) && device.roles.includes(role))
    .map((device) => device.token)
    .filter(Boolean);
  if (matching.length) return [...new Set(matching)];
  return allRegisteredTokens();
}

function roleTokenCounts() {
  return deviceTokens.reduce(
    (counts, device) => {
      for (const role of device.roles || []) {
        counts[role] = (counts[role] || 0) + 1;
      }
      return counts;
    },
    { guardian: 0, careRecipient: 0 },
  );
}

function registerDeviceToken(token, role) {
  const cleanToken = typeof token === "string" ? token.trim() : "";
  if (!cleanToken) return null;
  const cleanRole = normalizeDeviceRole(role);
  const index = deviceTokens.findIndex((device) => device.token === cleanToken);
  const updatedAt = new Date().toISOString();
  if (index >= 0) {
    const current = deviceTokens[index];
    const roles = Array.isArray(current.roles) ? [...current.roles] : [];
    if (!roles.includes(cleanRole)) roles.push(cleanRole);
    deviceTokens[index] = {
      ...current,
      token: cleanToken,
      roles,
      lastRole: cleanRole,
      updatedAt,
    };
  } else {
    deviceTokens.push({
      token: cleanToken,
      roles: [cleanRole],
      lastRole: cleanRole,
      updatedAt,
    });
  }
  tokens = allRegisteredTokens();
  return deviceTokens.find((device) => device.token === cleanToken);
}

function saveState() {
  const nextState = {
    tokens: allRegisteredTokens(),
    deviceTokens,
    guardians,
    settings,
    emergencyInfo,
    alerts: alerts.slice(0, 80),
    savedAt: new Date().toISOString(),
  };
  fs.writeFileSync(STATE_FILE, JSON.stringify(nextState, null, 2), "utf8");
}

let serviceAccountLoaded = false;
let serviceAccount = null;
let fcmAccessToken = null;
let fcmAccessTokenExpiresAt = 0;
let fcmMissingConfigLogged = false;

function base64Url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function loadServiceAccount() {
  if (serviceAccountLoaded) return serviceAccount;
  serviceAccountLoaded = true;

  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
      return serviceAccount;
    }

    const configuredPath =
      process.env.GOOGLE_APPLICATION_CREDENTIALS ||
      process.env.FIREBASE_SERVICE_ACCOUNT;
    if (configuredPath && fs.existsSync(configuredPath)) {
      serviceAccount = JSON.parse(fs.readFileSync(configuredPath, "utf8"));
      return serviceAccount;
    }
  } catch (error) {
    console.warn("FCM service account load failed:", error.message);
  }

  serviceAccount = null;
  return serviceAccount;
}

function fcmProjectId() {
  return process.env.FIREBASE_PROJECT_ID || loadServiceAccount()?.project_id;
}

function fcmCredentialPath() {
  return (
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    process.env.FIREBASE_SERVICE_ACCOUNT ||
    ""
  );
}

function fcmConfigStatus() {
  const credentialPath = fcmCredentialPath();
  const account = loadServiceAccount();
  const projectId = process.env.FIREBASE_PROJECT_ID || account?.project_id || null;
  const tokenCount = allRegisteredTokens().length;

  return {
    configured: Boolean(projectId && account?.client_email && account?.private_key),
    projectId,
    tokenCount,
    roleTokenCounts: roleTokenCounts(),
    credentialSource: process.env.FIREBASE_SERVICE_ACCOUNT_JSON
      ? "FIREBASE_SERVICE_ACCOUNT_JSON"
      : credentialPath
        ? "file"
        : "missing",
    credentialPathExists: credentialPath ? fs.existsSync(credentialPath) : null,
  };
}

function httpsRequestJson(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => {
        data += chunk;
      });
      res.on("end", () => {
        let parsed = null;
        try {
          parsed = data ? JSON.parse(data) : null;
        } catch (_) {
          parsed = data;
        }

        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(parsed);
        } else {
          reject(
            new Error(
              `HTTP ${res.statusCode}: ${
                typeof parsed === "string" ? parsed : JSON.stringify(parsed)
              }`,
            ),
          );
        }
      });
    });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

async function getFcmAccessToken() {
  if (fcmAccessToken && Date.now() < fcmAccessTokenExpiresAt - 60000) {
    return fcmAccessToken;
  }

  const account = loadServiceAccount();
  if (!account?.client_email || !account?.private_key) return null;

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64Url(JSON.stringify(header))}.${base64Url(
    JSON.stringify(claim),
  )}`;
  const privateKey = String(account.private_key).replace(/\\n/g, "\n");
  const signature = crypto
    .createSign("RSA-SHA256")
    .update(unsigned)
    .sign(privateKey, "base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
  const assertion = `${unsigned}.${signature}`;
  const form = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  }).toString();

  const response = await httpsRequestJson(
    {
      hostname: "oauth2.googleapis.com",
      path: "/token",
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Content-Length": Buffer.byteLength(form),
      },
    },
    form,
  );

  fcmAccessToken = response.access_token;
  fcmAccessTokenExpiresAt = Date.now() + Number(response.expires_in || 3600) * 1000;
  return fcmAccessToken;
}

async function sendFcmMessage(token, alert, location = null) {
  const projectId = fcmProjectId();
  const accessToken = await getFcmAccessToken();
  if (!projectId || !accessToken) return { skipped: true };

  const title = String(alert.title || "Hanium Safety 알림");
  const body = String(
    alert.message || `${alert.room || location?.room || "집 안"} 상태를 확인해 주세요.`,
  );
  const payload = JSON.stringify({
    message: {
      token,
      notification: { title, body },
      android: {
        priority: "HIGH",
        notification: {
          channel_id: WARNING_NOTIFICATION_CHANNEL_ID,
          sound: WARNING_NOTIFICATION_SOUND,
          notification_priority: "PRIORITY_MAX",
        },
      },
      data: {
        type: String(alert.type || location?.status || "system"),
        room: String(alert.room || location?.room || ""),
        status: String(location?.status || alert.type || ""),
        alertId: String(alert.id || Date.now()),
      },
    },
  });

  return httpsRequestJson(
    {
      hostname: "fcm.googleapis.com",
      path: `/v1/projects/${projectId}/messages:send`,
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(payload),
      },
    },
    payload,
  );
}

function sendPushForAlert(alert, location = null, options = {}) {
  const targetRole = options.targetRole || "guardian";
  const recipients = recipientTokens(targetRole);
  const fcm = fcmConfigStatus();

  if (!recipients.length) {
    return {
      requested: false,
      reason: "no_registered_tokens",
      recipients: 0,
      targetRole,
      fcm,
    };
  }

  if (!fcm.configured) {
    if (!fcmMissingConfigLogged) {
      console.warn(
        "FCM service account is not configured. Set GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_JSON to enable terminated-app push notifications.",
      );
      fcmMissingConfigLogged = true;
    }
    return {
      requested: false,
      reason: "fcm_not_configured",
      recipients: recipients.length,
      targetRole,
      fcm,
    };
  }

  Promise.allSettled(
    recipients.map((token) => sendFcmMessage(token, alert, location)),
  ).then((results) => {
    const sent = results.filter((result) => result.status === "fulfilled").length;
    const failed = results.length - sent;
    console.log(`FCM push result: sent=${sent}, failed=${failed}`);
  });

  return {
    requested: true,
    reason: "fcm_request_started",
    recipients: recipients.length,
    targetRole,
    fcm,
  };
}

function roomFromPosition(x, y) {
  if (x < 0.50 && y < 0.39) return "침실-2";
  if (x >= 0.50 && y < 0.255) return "주방";
  if (x < 0.50 && y < 0.565) return "거실";
  if (x >= 0.50 && x < 0.72 && y < 0.565) return "욕실";
  if (x < 0.50 && y >= 0.565) return "침실-1";
  return "현관";
}

function statusForTick(tick) {
  if ([21, 22, 23].includes(tick % 45)) return "danger";
  if ([10, 11, 12].includes(tick % 36)) return "out";
  return "normal";
}

function poseFromStatus(status) {
  if (status === "danger") return "lying";
  if (status === "out") return "walking";
  if (status === "still") return "sitting";
  return "standing";
}

function confidenceFromStatus(status) {
  if (status === "danger") return 0.91;
  if (status === "still") return 0.83;
  if (status === "out") return 0.86;
  return 0.88;
}

function breathingRateFromStatus(status) {
  if (status === "danger") return 23.8;
  if (status === "still") return 13.6;
  if (status === "out") return 18.4;
  return 16.8;
}

function presetForStatus(status) {
  if (status === "out") {
    return { x: 0.76, y: 0.66, room: "현관" };
  }
  if (status === "still") {
    return { x: 0.31, y: 0.68, room: "침실-1" };
  }
  if (status === "danger") {
    return { x: 0.35, y: 0.45, room: "거실" };
  }
  return { x: 0.35, y: 0.45, room: "거실" };
}

function normalizeNumber(value, fallback, min = 0, max = 1) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, number));
}

function normalizeStatus(status) {
  const raw = String(status || "").toLowerCase().trim();
  if (["danger", "fall", "fallen", "lying"].includes(raw)) return "danger";
  if (["out", "exit", "intrusion", "entrance"].includes(raw)) return "out";
  if (["still", "inactive", "sitting", "no_motion"].includes(raw)) return "still";
  if (raw === "normal") return "normal";
  // 누락·판단 불가(model_unavailable)·인식하지 못한 상태는 정상으로 바꾸지 않는다.
  return "unknown";
}

function normalizeRoom(room, x, y) {
  const value = typeof room === "string" ? room.trim() : "";
  const validRooms = ["거실", "주방", "침실", "침실-1", "침실-2", "욕실", "현관"];
  if (validRooms.includes(value)) return value;
  return roomFromPosition(x, y);
}

function sensorPayloadWarnings(input = {}) {
  const warnings = [];
  const x = Number(input.x);
  const y = Number(input.y);
  const confidence = Number(input.confidence);
  const rawStatus = String(input.status || "").toLowerCase().trim();
  const acceptedStatus = [
    "normal",
    "out",
    "danger",
    "still",
    "fall",
    "fallen",
    "lying",
    "exit",
    "intrusion",
    "entrance",
    "inactive",
    "sitting",
    "no_motion",
    "unknown",
    "model_unavailable",
  ];

  if (!Number.isFinite(x)) warnings.push("x is missing or invalid; fallback coordinate was used.");
  else if (x < 0 || x > 1) warnings.push("x was outside 0.0~1.0 and was clamped.");

  if (!Number.isFinite(y)) warnings.push("y is missing or invalid; fallback coordinate was used.");
  else if (y < 0 || y > 1) warnings.push("y was outside 0.0~1.0 and was clamped.");

  if (!rawStatus) {
    warnings.push("status is missing; the previous status (or 'unknown') was used.");
  } else if (!acceptedStatus.includes(rawStatus)) {
    warnings.push(`status '${input.status}' is not recognized and was normalized to 'unknown'.`);
  }

  if (input.confidence !== undefined) {
    if (!Number.isFinite(confidence)) warnings.push("confidence is invalid; fallback confidence was used.");
    else if (confidence < 0 || confidence > 1) {
      warnings.push("confidence was outside 0.0~1.0 and was clamped.");
    }
  }

  if (!input.source) warnings.push("source is missing; 'unknown' was used.");
  return warnings;
}

function normalizeLocation(input = {}) {
  const x = normalizeNumber(input.x, latestLocation?.x ?? 0.48);
  const y = normalizeNumber(input.y, latestLocation?.y ?? 0.50);
  const status = normalizeStatus(input.status ?? latestLocation?.status);
  const room = normalizeRoom(input.room, x, y);
  const pose = input.pose || poseFromStatus(status);
  const confidence = normalizeNumber(
    input.confidence,
    // 판단 불가 상태에 이전 신뢰도를 이어 붙이지 않고, 판단 불가의 신뢰도 0을 다음 상태에 물려주지도 않는다.
    status === "unknown"
      ? 0
      : latestLocation && latestLocation.status !== "unknown"
        ? latestLocation.confidence ?? 0.86
        : 0.86,
    0,
    1,
  );
  // 호흡값이 없으면 예시값으로 채우지 않고 null로 전달한다(앱은 '측정 대기'로 표시).
  const rawBreathingRate = input.breathingRate ?? input.respirationRate ?? input.breathRate;
  const breathingRate =
    rawBreathingRate === undefined || rawBreathingRate === null || rawBreathingRate === ""
      ? null
      : normalizeNumber(rawBreathingRate, null, 6, 36);
  const rawBreathingConfidence = input.breathingConfidence ?? input.respirationConfidence;
  const breathingConfidence =
    breathingRate === null ||
    rawBreathingConfidence === undefined ||
    rawBreathingConfidence === null ||
    rawBreathingConfidence === ""
      ? null
      : normalizeNumber(rawBreathingConfidence, null, 0, 1);
  // 서버는 호흡값을 보충하지 않는다. 모의 이동 상태를 이어받은 경우처럼 입력이 추정값이라고 표시할 때만 true.
  const breathingEstimated = breathingRate !== null && input.breathingEstimated === true;

  return {
    x: Number(x.toFixed(3)),
    y: Number(y.toFixed(3)),
    status,
    room,
    pose,
    confidence: Number(confidence.toFixed(2)),
    breathingRate: breathingRate === null ? null : Number(breathingRate.toFixed(1)),
    breathingConfidence:
      breathingConfidence === null ? null : Number(breathingConfidence.toFixed(2)),
    breathingEstimated,
    source: input.source || "unknown",
    timestamp: new Date().toLocaleTimeString("ko-KR", { hour12: false }),
  };
}

function ensureLatestLocation() {
  if (!latestLocation) {
    // 아직 받은 입력이 없으므로 'normal'이 아니라 'unknown'(앱: 확인 필요)으로 시작한다.
    // 모의 이동 모드에서는 다음 WebSocket 틱부터 모의 이동이 상태를 정한다.
    latestLocation = normalizeLocation({
      x: 0.34,
      y: 0.45,
      status: "unknown",
      source: "boot",
    });
  }

  return latestLocation;
}

function isLocationSharingEnabled() {
  return settings.locationSharingEnabled !== false;
}

function publicLocation(location = ensureLatestLocation()) {
  if (isLocationSharingEnabled()) {
    return {
      ...location,
      locationSharingEnabled: true,
    };
  }

  return {
    ...location,
    x: 0.5,
    y: 0.5,
    room: "위치 공유 꺼짐",
    locationSharingEnabled: false,
    hiddenReason: "care_recipient_disabled",
  };
}

function nextLocation(tick) {
  const angle = tick / 7;
  let x = 0.48 + Math.cos(angle) * 0.22 + (Math.random() * 0.03 - 0.015);
  let y = 0.50 + Math.sin(angle * 0.8) * 0.24 + (Math.random() * 0.03 - 0.015);
  x = Math.max(0.12, Math.min(0.88, x));
  y = Math.max(0.12, Math.min(0.88, y));
  const status = forcedScenario?.status ?? statusForTick(tick);
  return {
    x: Number(x.toFixed(3)),
    y: Number(y.toFixed(3)),
    status,
    room: roomFromPosition(x, y),
    pose: poseFromStatus(status),
    confidence: 0.86,
    breathingRate: Number((breathingRateFromStatus(status) + Math.sin(angle) * 0.6).toFixed(1)),
    breathingConfidence: 0.66,
    breathingEstimated: true,
    timestamp: new Date().toLocaleTimeString("ko-KR", { hour12: false }),
  };
}

function currentLocation(tick) {
  if (latestLocation && Date.now() < manualSensorUntil) {
    return {
      ...latestLocation,
      timestamp: new Date().toLocaleTimeString("ko-KR", { hour12: false }),
    };
  }

  if (REAL_SENSOR_ONLY) {
    const location = ensureLatestLocation();
    latestLocation = {
      ...location,
      source: location.source || "sensor-waiting",
      timestamp: new Date().toLocaleTimeString("ko-KR", { hour12: false }),
    };
    return latestLocation;
  }

  const location = nextLocation(tick);
  latestLocation = { ...location, source: "mock" };
  return latestLocation;
}

function nowLabel() {
  return new Date().toLocaleTimeString("ko-KR", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

function addAlertFromLocation(location) {
  // 'unknown'(판단 불가)은 위험 알림으로 만들지 않고 상태로만 전달한다.
  if (location.status === "normal" || location.status === "unknown") return;
  const existing = alerts[0];
  const sharingEnabled = isLocationSharingEnabled();
  const alertRoom = sharingEnabled ? location.room : "위치 비공개";
  if (
    existing &&
    existing.type === location.status &&
    existing.room === alertRoom &&
    !existing.resolved
  ) {
    return;
  }

  const isDanger = location.status === "danger";
  const isStill = location.status === "still";
  const isOut = location.status === "out";
  const safeRoomText = sharingEnabled
    ? `${location.room}에서`
    : "위치 비공개 상태에서";
  const alert = {
    id: Date.now(),
    type: isDanger ? "danger" : "warning",
    title: isDanger
      ? "낙상 의심 움직임 감지"
      : isStill
        ? "장시간 움직임이 적어요"
        : "현관 접근이 감지됐어요",
    message: isDanger
      ? `${safeRoomText} 급격한 쓰러짐 패턴이 감지됐어요.`
      : isStill
        ? `${safeRoomText} 움직임이 오래 감지되지 않았어요.`
        : isOut
          ? `${safeRoomText} 외출 또는 현관 접근 가능성이 확인됐어요.`
          : `${safeRoomText} 평소와 다른 움직임이 감지됐어요.`,
    room: alertRoom,
    time: nowLabel(),
    urgent: isDanger,
    resolved: false,
  };
  alerts.unshift(alert);
  saveState();
  sendPushForAlert(alert, location);
  return alert;
}

function resetDemoState() {
  const currentTokens = allRegisteredTokens();
  const currentDeviceTokens = deviceTokens;
  guardians = clone(defaultState.guardians);
  settings = clone(defaultState.settings);
  emergencyInfo = clone(defaultState.emergencyInfo);
  alerts = [];
  tokens = currentTokens;
  deviceTokens = currentDeviceTokens;
  forcedScenario = null;
  // 초기화 직후에는 입력이 없으므로 'unknown'(앱: 확인 필요)으로 둔다.
  latestLocation = normalizeLocation({
    x: 0.34,
    y: 0.45,
    status: "unknown",
    room: "거실",
    source: "reset",
    holdMs: 60000,
  });
  manualSensorUntil = Date.now() + 60000;
  saveState();
  broadcastLocation(latestLocation);
  return {
    guardians,
    settings,
    emergencyInfo,
    alerts,
    location: publicLocation(latestLocation),
  };
}

function updateGuardian(body) {
  const id = Number(body.id);
  const index = guardians.findIndex((guardian) => Number(guardian.id) === id);
  if (index < 0) return null;

  guardians[index] = {
    ...guardians[index],
    name: body.name || guardians[index].name,
    phone: body.phone || guardians[index].phone,
    role: body.role || guardians[index].role,
  };
  saveState();
  return guardians[index];
}

function deleteGuardian(body) {
  const id = Number(body.id);
  const before = guardians.length;
  guardians = guardians.filter((guardian) => Number(guardian.id) !== id);
  if (guardians.length === before) return false;
  saveState();
  return true;
}

function updateEmergencyInfo(body) {
  emergencyInfo = {
    ...emergencyInfo,
    address: body.address ?? emergencyInfo.address,
    accessNote: body.accessNote ?? emergencyInfo.accessNote,
    medicalNote: body.medicalNote ?? emergencyInfo.medicalNote,
    hospital: body.hospital ?? emergencyInfo.hospital,
  };
  saveState();
  return emergencyInfo;
}

function readJsonBody(req, callback) {
  let raw = "";
  req.on("data", (chunk) => (raw += chunk));
  req.on("end", () => {
    try {
      callback(raw ? JSON.parse(raw) : {});
    } catch (_) {
      callback({});
    }
  });
}

function isAuthorized(req) {
  if (!API_TOKEN) return true;
  const given = Buffer.from(String(req.headers.authorization || ""), "utf8");
  const expected = Buffer.from(`Bearer ${API_TOKEN}`, "utf8");
  return given.length === expected.length && crypto.timingSafeEqual(given, expected);
}

// 브라우저는 WebSocket에 헤더를 붙일 수 없어 토큰을 ?token= 쿼리로도 받는다.
// CORS가 적용되지 않는 WebSocket은 Origin을 직접 확인해, 다른 출처의 웹페이지가 위치 스트림을 열지 못하게 한다.
function isWebSocketAllowed(req, url) {
  const origin = String(req.headers.origin || "").replace(/\/+$/, "");
  if (origin) {
    const sameHost = origin.replace(/^https?:\/\//, "") === String(req.headers.host || "");
    if (!sameHost && !CORS_ORIGINS.includes("*") && !CORS_ORIGINS.includes(origin)) return false;
  }
  if (!API_TOKEN || isAuthorized(req)) return true;
  const given = Buffer.from(url.searchParams.get("token") || "", "utf8");
  const expected = Buffer.from(API_TOKEN, "utf8");
  return given.length === expected.length && crypto.timingSafeEqual(given, expected);
}

function isJsonRequest(req) {
  const type = String(req.headers["content-type"] || "")
    .split(";")[0]
    .trim()
    .toLowerCase();
  return type === "application/json";
}

// 같은 출처(관리자 페이지)는 CORS 헤더가 필요 없다. HANIUM_CORS_ORIGIN에 지정한 출처만 허용한다.
function applyCors(req, res) {
  const origin = String(req.headers.origin || "").replace(/\/+$/, "");
  if (!origin || !CORS_ORIGINS.length) return;
  if (!CORS_ORIGINS.includes("*") && !CORS_ORIGINS.includes(origin)) return;
  res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

function sendJson(res, code, body) {
  const payload = JSON.stringify(body);
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function sendHtml(res, body) {
  res.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
  });
  res.end(body);
}

function sendWsText(socket, obj) {
  const payload = Buffer.from(JSON.stringify(obj), "utf8");
  let header;
  if (payload.length < 126) {
    header = Buffer.from([0x81, payload.length]);
  } else if (payload.length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(payload.length), 2);
  }
  socket.write(Buffer.concat([header, payload]));
}

// WebSocket으로 나가는 모든 위치는 REST와 같은 publicLocation() 필터(위치 공유 OFF)를 거친다.
function sendLocationWs(socket, location) {
  sendWsText(socket, publicLocation(location));
}

function broadcastLocation(location) {
  addAlertFromLocation(location);
  for (const socket of wsClients) {
    if (socket.destroyed) {
      wsClients.delete(socket);
      continue;
    }
    try {
      sendLocationWs(socket, location);
    } catch (_) {
      wsClients.delete(socket);
      socket.destroy();
    }
  }
}

function updateSensorLocation(body = {}) {
  const warnings = sensorPayloadWarnings(body);
  latestLocation = normalizeLocation(body);
  manualSensorUntil = Date.now() + Number(body.holdMs || 60000);
  broadcastLocation(latestLocation);
  return {
    accepted: warnings.length === 0,
    warnings,
    location: publicLocation(latestLocation),
  };
}

function adminHtml() {
  return `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Hanium 관리자 콘솔</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f5f7fb;
      color: #121a2f;
    }
    header {
      padding: 24px;
      background: linear-gradient(135deg, #5b6cf6, #20c997);
      color: white;
    }
    header h1 { margin: 0 0 6px; font-size: 28px; }
    header p { margin: 0; opacity: .88; }
    main {
      display: grid;
      grid-template-columns: minmax(320px, 1.25fr) minmax(300px, .75fr);
      gap: 18px;
      padding: 18px;
      max-width: 1180px;
      margin: 0 auto;
    }
    section, .card {
      background: white;
      border: 1px solid #e8ecf4;
      border-radius: 24px;
      box-shadow: 0 14px 34px rgba(17, 24, 39, .06);
    }
    section { padding: 18px; }
    h2 { margin: 0 0 12px; font-size: 20px; }
    .map {
      position: relative;
      aspect-ratio: .82;
      min-height: 540px;
      background: #fbfcff;
      border: 1px solid #e8ecf4;
      border-radius: 22px;
      overflow: hidden;
      cursor: crosshair;
    }
    .room {
      position: absolute;
      border: 4px solid #3c465a;
      display: flex;
      align-items: flex-start;
      padding: 10px;
      font-weight: 800;
      color: #586176;
    }
    .living { left: 6%; top: 8%; width: 50%; height: 42%; background:#e8f4ed; }
    .kitchen { left: 56%; top: 8%; width: 38%; height: 28%; background:#fff1cc; }
    .bed { left: 6%; top: 50%; width: 38%; height: 38%; background:#d8e6ff; }
    .bath { left: 44%; top: 50%; width: 18%; height: 38%; background:#d9eef5; }
    .door { left: 62%; top: 36%; width: 32%; height: 52%; background:#ead7f1; }
    .sensor {
      position: absolute;
      width: 18px;
      height: 18px;
      border-radius: 999px;
      background: #28be82;
      box-shadow: 0 0 0 8px rgba(40,190,130,.16);
      transform: translate(-50%, -50%);
      z-index: 5;
    }
    .person {
      position: absolute;
      width: 34px;
      height: 46px;
      border-radius: 22px;
      background: rgba(91,108,246,.16);
      transform: translate(-50%, -50%);
      z-index: 10;
    }
    .person::before {
      content: "";
      position: absolute;
      left: 10px;
      top: 5px;
      width: 14px;
      height: 14px;
      border-radius: 50%;
      background: var(--person-color, #5b6cf6);
    }
    .person::after {
      content: "";
      position: absolute;
      left: 16px;
      top: 19px;
      width: 4px;
      height: 20px;
      border-radius: 99px;
      background: var(--person-color, #5b6cf6);
      box-shadow: -8px 8px 0 -1px var(--person-color, #5b6cf6), 8px 8px 0 -1px var(--person-color, #5b6cf6);
    }
    .label {
      position: absolute;
      transform: translate(-50%, calc(-100% - 14px));
      background: white;
      color: #121a2f;
      border-radius: 999px;
      padding: 7px 10px;
      font-weight: 900;
      font-size: 13px;
      box-shadow: 0 8px 20px rgba(17,24,39,.12);
      z-index: 12;
      white-space: nowrap;
    }
    .controls { display: grid; gap: 12px; }
    .row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .quick-actions { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .quick-actions button { min-height: 52px; }
    .status-banner {
      margin: 0 0 12px;
      padding: 14px;
      border-radius: 18px;
      background: #eef2ff;
      color: #3140c9;
      font-weight: 900;
      line-height: 1.45;
    }
    .demo-steps {
      display: grid;
      gap: 8px;
      margin-bottom: 12px;
    }
    .step-card {
      display: grid;
      grid-template-columns: 34px 1fr;
      gap: 10px;
      align-items: start;
      padding: 10px;
      border-radius: 16px;
      background: #f8faff;
      border: 1px solid #e8ecf4;
    }
    .step-card.active {
      background: #e9fff5;
      border-color: rgba(40, 190, 130, .35);
      box-shadow: 0 10px 24px rgba(40, 190, 130, .12);
    }
    .step-no {
      width: 28px;
      height: 28px;
      border-radius: 999px;
      display: grid;
      place-items: center;
      background: #eef2ff;
      color: #5b6cf6;
      font-size: 13px;
      font-weight: 900;
    }
    .step-card.active .step-no {
      background: #28be82;
      color: white;
    }
    .step-title { font-weight: 900; }
    .step-desc {
      margin-top: 3px;
      color: #7a8397;
      font-size: 12px;
      line-height: 1.35;
    }
    button, select, input {
      border: 1px solid #e8ecf4;
      border-radius: 14px;
      padding: 12px 14px;
      font: inherit;
    }
    button {
      cursor: pointer;
      font-weight: 900;
      background: #eef2ff;
      color: #5b6cf6;
    }
    button.primary { background: #5b6cf6; color: white; }
    button.danger { background: #ff5b73; color: white; }
    button.dark { background: #1b2a4a; color: white; }
    button.success { background: #28be82; color: white; }
    button:disabled { opacity: .55; cursor: wait; }
    .pill {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      padding: 8px 11px;
      border-radius: 999px;
      background: #e9fff5;
      color: #28be82;
      font-weight: 900;
      font-size: 13px;
    }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
    .list { display: grid; gap: 10px; }
    .card { padding: 14px; }
    .alert-card {
      border-left: 5px solid #e8ecf4;
    }
    .alert-card.urgent {
      border-left-color: #ff5b73;
      background: #fff7f9;
    }
    .alert-card.warning {
      border-left-color: #f4a62a;
      background: #fffaf0;
    }
    .alert-card.safe {
      border-left-color: #28be82;
      background: #f3fff9;
    }
    .alert-title-line {
      display: flex;
      gap: 8px;
      align-items: center;
      justify-content: space-between;
    }
    .badge {
      padding: 4px 8px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 900;
      background: #eef2ff;
      color: #5b6cf6;
      white-space: nowrap;
    }
    .badge.danger { background: #ffe9ee; color: #ff5b73; }
    .badge.warning { background: #fff2d8; color: #d98200; }
    .badge.safe { background: #e9fff5; color: #28be82; }
    .muted { color: #7a8397; font-size: 13px; }
    @media (max-width: 860px) {
      main { grid-template-columns: 1fr; }
      .map { min-height: 460px; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Hanium 관리자 콘솔</h1>
    <p>발표/시연 중 센서 위치와 위험 상황을 브라우저에서 바로 조작합니다.</p>
  </header>
  <main>
    <section>
      <h2>실시간 집 도면</h2>
      <div class="map" id="map">
        <div class="room living">거실</div>
        <div class="room kitchen">주방</div>
        <div class="room bed">침실-1</div>
        <div class="room bath">욕실</div>
        <div class="room door">현관</div>
        <div class="sensor" style="left:8%;top:8%"></div>
        <div class="sensor" style="left:92%;top:8%"></div>
        <div class="sensor" style="left:8%;top:91%"></div>
        <div class="sensor" style="left:92%;top:91%"></div>
        <div class="label" id="personLabel">연결 대기</div>
        <div class="person" id="person"></div>
      </div>
    </section>
    <aside class="controls">
      <section>
        <h2>발표 리모컨</h2>
        <p class="status-banner" id="demoMessage">1번 시연 시작을 누른 뒤, 앱 설정의 '앱 연결 상태'에서 서버 연결이 '준비됨'인지 확인하세요.</p>
        <div class="demo-steps" id="demoSteps"></div>
        <div class="quick-actions">
          <button class="primary" onclick="demoStart()">1. 시연 시작</button>
          <button onclick="demoNormal()">2. 평소 상태</button>
          <button onclick="demoOut()">3. 현관 접근</button>
          <button onclick="demoStill()">4. 무반응</button>
          <button class="danger" onclick="demoDanger()">5. 낙상 의심</button>
          <button class="success" onclick="demoRecover()">6. 안전 확인</button>
          <button class="dark" onclick="runAutoDemo()">자동 시연</button>
          <button onclick="copyDemoScript()">멘트 복사</button>
        </div>
      </section>
      <section>
        <h2>현재 상태</h2>
        <p><span class="pill"><span class="dot"></span><span id="serverStatus">확인 중</span></span></p>
        <div class="list">
          <div class="card"><b>방</b><div class="muted" id="roomText">-</div></div>
          <div class="card"><b>상태</b><div class="muted" id="statusText">-</div></div>
          <div class="card"><b>신뢰도</b><div class="muted" id="confidenceText">-</div></div>
        </div>
      </section>
      <section>
        <h2>센서 위치 입력</h2>
        <div class="row">
          <input id="xInput" type="number" min="0" max="1" step="0.01" value="0.34" />
          <input id="yInput" type="number" min="0" max="1" step="0.01" value="0.45" />
        </div>
        <select id="statusInput">
          <option value="normal">정상</option>
          <option value="danger">낙상 의심</option>
          <option value="out">현관 접근</option>
          <option value="still">장시간 무반응</option>
          <option value="unknown">판단 불가</option>
        </select>
        <button class="primary" onclick="sendManual()">위치 전송</button>
        <button onclick="resetSensor()">자동 mock 위치로 복귀</button>
        <p class="muted">지도 위를 클릭해도 해당 좌표가 앱으로 전송됩니다.</p>
      </section>
      <section>
        <h2>시연 버튼</h2>
        <div class="row">
          <button onclick="scenario('normal', { x: .35, y: .45, room: '거실' })">정상</button>
          <button onclick="scenario('out', { x: .76, y: .66, room: '현관' })">현관</button>
        </div>
        <button onclick="scenario('still', { x: .31, y: .68, room: '침실-1' })">장시간 무반응</button>
        <button class="danger" onclick="scenario('danger')">낙상 의심 발생</button>
        <button class="dark" onclick="resolveAlerts()">알림 확인 완료</button>
        <button onclick="resetDemo()">시연 상태 초기화</button>
      </section>
      <section>
        <h2>최근 알림</h2>
        <div class="list" id="alerts"></div>
      </section>
    </aside>
  </main>
  <script>
    const person = document.getElementById("person");
    const label = document.getElementById("personLabel");
    const statusColors = { normal: "#28be82", danger: "#ff5b73", out: "#f4a62a", still: "#f4a62a", unknown: "#7a8397" };
    const statusLabels = { normal: "정상", danger: "낙상 의심", out: "현관 접근", still: "장시간 무반응", unknown: "판단 불가" };
    let apiToken = "";
    try {
      apiToken = sessionStorage.getItem("haniumApiToken") || "";
    } catch (_) {}
    let tokenPromptDeclined = false;
    const demoSteps = [
      ["시연 시작", "서버와 앱 연결을 초기화합니다. 입력 전이므로 앱은 확인 필요 상태입니다."],
      ["평소 상태", "거실에서 평소와 비슷한 움직임이 감지되는 장면입니다."],
      ["현관 접근", "현관 쪽 이동을 외출 가능성으로 보여줍니다."],
      ["장시간 무반응", "침실-1에서 오랫동안 움직임이 적은 상태를 보여줍니다."],
      ["낙상 의심", "거실 소파 근처에서 급격한 쓰러짐 패턴을 보여줍니다."],
      ["안전 확인", "보호자가 확인한 뒤 알림을 정리하고 정상 상태로 복구합니다."],
    ];
    let activeDemoStep = 0;
    let autoDemoRunning = false;

    function renderDemoSteps() {
      const root = document.getElementById("demoSteps");
      root.innerHTML = "";
      demoSteps.forEach((step, index) => {
        const div = document.createElement("div");
        div.className = "step-card" + (index === activeDemoStep ? " active" : "");
        div.innerHTML =
          "<div class='step-no'>" + (index + 1) + "</div>" +
          "<div><div class='step-title'>" + step[0] + "</div>" +
          "<div class='step-desc'>" + step[1] + "</div></div>";
        root.appendChild(div);
      });
    }

    function setDemoStep(index, message) {
      activeDemoStep = Math.max(0, Math.min(demoSteps.length - 1, index));
      document.getElementById("demoMessage").textContent = message || demoSteps[activeDemoStep][1];
      renderDemoSteps();
    }

    function setBusy(isBusy) {
      document.querySelectorAll(".quick-actions button").forEach(button => {
        button.disabled = isBusy;
      });
    }

    function wait(ms) {
      return new Promise(resolve => setTimeout(resolve, ms));
    }

    function roomFromPosition(x, y) {
      if (x < 0.50 && y < 0.39) return "침실-2";
      if (x >= 0.50 && y < 0.255) return "주방";
      if (x < 0.50 && y < 0.565) return "거실";
      if (x >= 0.50 && x < 0.72 && y < 0.565) return "욕실";
      if (x < 0.50 && y >= 0.565) return "침실-1";
      return "현관";
    }

    function poseFromStatus(status) {
      if (status === "danger") return "lying";
      if (status === "out") return "walking";
      if (status === "still") return "sitting";
      return "standing";
    }

    function confidenceFromStatus(status) {
      if (status === "danger") return .91;
      if (status === "still") return .83;
      if (status === "out") return .86;
      return .88;
    }

    function defaultPointForStatus(status) {
      if (status === "out") return { x: .76, y: .66, room: "현관" };
      if (status === "still") return { x: .31, y: .68, room: "침실-1" };
      if (status === "danger") return { x: .35, y: .45, room: "거실" };
      return { x: .35, y: .45, room: "거실" };
    }

    function updateLocation(location) {
      const x = Math.max(0.07, Math.min(0.93, Number(location.x || 0.5)));
      const y = Math.max(0.07, Math.min(0.92, Number(location.y || 0.5)));
      person.style.left = (x * 100) + "%";
      person.style.top = (y * 100) + "%";
      label.style.left = person.style.left;
      label.style.top = person.style.top;
      person.style.setProperty("--person-color", statusColors[location.status] || "#5b6cf6");
      label.textContent = (location.room || roomFromPosition(x, y)) + " · " + (statusLabels[location.status] || location.status);
      document.getElementById("roomText").textContent = location.room || roomFromPosition(x, y);
      document.getElementById("statusText").textContent = statusLabels[location.status] || location.status;
      document.getElementById("confidenceText").textContent = Math.round((location.confidence || 0) * 100) + "%";
      document.getElementById("xInput").value = x.toFixed(2);
      document.getElementById("yInput").value = y.toFixed(2);
      document.getElementById("statusInput").value = location.status || "normal";
    }

    // 서버에 HANIUM_API_TOKEN이 설정된 경우에만 401이 오며, 이때 한 번 토큰을 물어 이 탭에만 보관한다.
    async function apiFetch(path, options = {}) {
      const send = () => fetch(path, {
        cache: "no-store",
        ...options,
        headers: { ...(options.headers || {}), ...(apiToken ? { Authorization: "Bearer " + apiToken } : {}) },
      });
      const sentToken = apiToken;
      const response = await send();
      if (response.status !== 401) return response;
      if (apiToken !== sentToken) return send();
      if (tokenPromptDeclined) return response;
      const entered = (window.prompt("서버에 API 토큰(HANIUM_API_TOKEN)이 설정되어 있습니다. 토큰을 입력하세요.") || "").trim();
      if (!entered) {
        tokenPromptDeclined = true;
        return response;
      }
      apiToken = entered;
      try {
        sessionStorage.setItem("haniumApiToken", apiToken);
      } catch (_) {}
      return send();
    }

    async function refreshState() {
      try {
        const [health, state, latest] = await Promise.all([
          fetch("/health", { cache: "no-store" }).then(r => r.json()),
          apiFetch("/state").then(r => r.json()),
          apiFetch("/location/latest").then(r => r.json()),
        ]);
        document.getElementById("serverStatus").textContent = state.error === "unauthorized"
          ? "API 토큰 필요"
          : health.ok ? "서버 연결됨" : "확인 필요";
        renderAlerts(state.alerts || []);
        if (latest.location) updateLocation(latest.location);
      } catch (error) {
        document.getElementById("serverStatus").textContent = "서버 연결 실패";
      }
    }

    function renderAlerts(alerts) {
      const root = document.getElementById("alerts");
      root.innerHTML = "";
      alerts.slice(0, 4).forEach(alert => {
        const div = document.createElement("div");
        const badgeClass = alert.urgent || alert.type === "danger"
          ? "danger"
          : alert.type === "safe"
            ? "safe"
          : alert.type === "warning"
            ? "warning"
            : "";
        const badgeText = alert.urgent || alert.type === "danger"
          ? "긴급"
          : alert.type === "safe"
            ? "안전"
          : alert.type === "warning"
            ? "주의"
            : "기록";
        div.className = "card alert-card " + badgeClass + (alert.urgent ? " urgent" : "");
        div.innerHTML =
          "<div class='alert-title-line'><b>" + alert.title + "</b><span class='badge " + badgeClass + "'>" + badgeText + "</span></div>" +
          "<div class='muted'>" + alert.room + " · " + alert.time + (alert.resolved ? " · 확인 완료" : "") + "</div>" +
          "<div class='muted'>" + (alert.message || "") + "</div>";
        root.appendChild(div);
      });
      if (!alerts.length) root.innerHTML = "<p class='muted'>알림이 없습니다.</p>";
    }

    async function postJson(path, body) {
      return apiFetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }).then(r => r.json());
    }

    async function sendManual() {
      const x = Number(document.getElementById("xInput").value);
      const y = Number(document.getElementById("yInput").value);
      const status = document.getElementById("statusInput").value;
      const location = await postJson("/sensor/update", { x, y, status, source: "admin", holdMs: 60000 });
      updateLocation(location.location);
      await refreshState();
    }

    async function resetSensor() {
      await postJson("/sensor/reset", {});
      await refreshState();
    }

    async function scenario(status, options = {}) {
      const seconds = options.seconds || 60;
      const fallback = defaultPointForStatus(status);
      const rawX = options.x ?? Number(document.getElementById("xInput").value);
      const rawY = options.y ?? Number(document.getElementById("yInput").value);
      const x = Number.isFinite(Number(rawX)) ? Number(rawX) : fallback.x;
      const y = Number.isFinite(Number(rawY)) ? Number(rawY) : fallback.y;
      const payload = {
        x,
        y,
        status,
        room: options.room || roomFromPosition(x, y),
        pose: options.pose || poseFromStatus(status),
        confidence: options.confidence ?? confidenceFromStatus(status),
        source: "admin",
        seconds,
        holdMs: seconds * 1000,
      };
      const result = await postJson("/scenario", payload);
      if (result.location) updateLocation(result.location);
      await refreshState();
      if (options.step !== undefined) {
        setDemoStep(options.step, options.message);
      }
    }

    async function resetDemo() {
      await postJson("/demo/reset", {});
      setDemoStep(0, "시연 상태를 초기화했어요. 앱에서 확인 필요(입력 대기) 상태와 설정의 서버 연결 '준비됨'을 확인하세요.");
      await refreshState();
    }

    async function resolveAlerts() {
      await postJson("/alerts/resolve", {});
      setDemoStep(5, "보호자가 확인한 상황입니다. 앱에서 알림이 확인 완료 또는 정상 상태로 정리되는지 보세요.");
      await refreshState();
    }

    async function demoStart() {
      await resetDemo();
      setDemoStep(0, "시연 시작: 서버와 앱 연결이 정상인지 먼저 확인합니다.");
    }

    async function demoNormal() {
      await scenario("normal", {
        x: .35,
        y: .45,
        room: "거실",
        step: 1,
        message: "평소 상태: 거실에서 일반적인 움직임이 감지됩니다. 앱 홈 화면의 '정상' 상태를 확인하세요.",
      });
    }

    async function demoOut() {
      await scenario("out", {
        x: .76,
        y: .66,
        room: "현관",
        step: 2,
        message: "현관 접근: 현관 쪽 움직임이 감지됩니다. 앱에서 외출/현관 접근 알림을 확인하세요.",
      });
    }

    async function demoStill() {
      await scenario("still", {
        x: .31,
        y: .68,
        room: "침실-1",
        step: 3,
        message: "장시간 무반응: 침실-1에서 움직임이 적은 상태입니다. 앱의 주의 알림을 확인하세요.",
      });
    }

    async function demoDanger() {
      await scenario("danger", {
        x: .35,
        y: .45,
        room: "거실",
        step: 4,
        message: "낙상 의심: 거실 소파 근처에서 급격한 쓰러짐 패턴입니다. 앱의 긴급 알림과 응급 대응 버튼을 확인하세요.",
      });
    }

    async function demoRecover() {
      await resolveAlerts();
      await wait(400);
      await scenario("normal", {
        x: .35,
        y: .45,
        room: "거실",
        step: 5,
        message: "안전 확인 완료: 알림을 정리하고 정상 상태로 복구했습니다.",
      });
    }

    async function runAutoDemo() {
      if (autoDemoRunning) return;
      autoDemoRunning = true;
      setBusy(true);
      try {
        await demoStart();
        await wait(1800);
        await demoNormal();
        await wait(2500);
        await demoOut();
        await wait(3000);
        await demoStill();
        await wait(3000);
        await demoDanger();
        await wait(3500);
        await demoRecover();
      } finally {
        autoDemoRunning = false;
        setBusy(false);
      }
    }

    async function copyDemoScript() {
      const text = [
        "이 앱은 카메라 없이 WiFi CSI 기반 움직임 정보를 받아 보호자에게 꼭 필요한 안전 상태만 보여줍니다.",
        "먼저 평소 상태에서는 거실에서 일반적인 움직임이 감지되어 앱에 정상으로 표시됩니다.",
        "현관 접근이나 장시간 무반응처럼 보호자가 확인해야 할 상황이 생기면 앱에 주의 알림이 생성됩니다.",
        "낙상 의심 상황에서는 위치와 시간, 응급 대응 절차를 바로 확인할 수 있고 보호자 연락/119 신고 정보까지 이어집니다.",
      ].join("\\n");
      try {
        await navigator.clipboard.writeText(text);
        setDemoStep(activeDemoStep, "발표 멘트를 클립보드에 복사했어요.");
      } catch (error) {
        setDemoStep(activeDemoStep, "브라우저가 복사를 막았어요. 콘솔/문서의 발표 멘트를 사용하세요.");
      }
    }

    document.getElementById("map").addEventListener("click", (event) => {
      const rect = event.currentTarget.getBoundingClientRect();
      document.getElementById("xInput").value = ((event.clientX - rect.left) / rect.width).toFixed(2);
      document.getElementById("yInput").value = ((event.clientY - rect.top) / rect.height).toFixed(2);
      sendManual();
    });

    renderDemoSteps();
    const ws = new WebSocket("ws://" + location.host + "/ws/location" + (apiToken ? "?token=" + encodeURIComponent(apiToken) : ""));
    ws.onmessage = (event) => updateLocation(JSON.parse(event.data));
    setInterval(refreshState, 3000);
    refreshState();
  </script>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");

  applyCors(req, res);
  if (req.method === "OPTIONS") return sendJson(res, 204, {});
  const needsToken =
    req.method === "POST" ||
    (req.method === "GET" && PROTECTED_GET_PATHS.has(url.pathname));
  if (needsToken && !isAuthorized(req)) {
    res.setHeader("WWW-Authenticate", "Bearer");
    return sendJson(res, 401, { error: "unauthorized" });
  }
  if (
    req.method === "POST" &&
    JSON_BODY_POST_PATHS.has(url.pathname) &&
    !isJsonRequest(req)
  ) {
    return sendJson(res, 415, { error: "Content-Type must be application/json" });
  }
  if (req.method === "GET" && url.pathname === "/") {
    return sendJson(res, 200, {
      project: "Hanium CSI Safety System",
      status: "running",
      timestamp: new Date().toISOString(),
      admin: `http://127.0.0.1:${PORT}/admin`,
    });
  }
  if (req.method === "GET" && url.pathname === "/admin") {
    return sendHtml(res, adminHtml());
  }
  if (req.method === "GET" && url.pathname === "/health") {
    return sendJson(res, 200, {
      ok: true,
      port: PORT,
      realSensorOnly: REAL_SENSOR_ONLY,
      mockMotion: !REAL_SENSOR_ONLY,
      authRequired: Boolean(API_TOKEN),
      wsClients: wsClients.size,
      hasLocation: Boolean(latestLocation),
      push: fcmConfigStatus(),
      uptimeSeconds: Math.round(process.uptime()),
      timestamp: new Date().toISOString(),
    });
  }
  if (req.method === "GET" && url.pathname === "/push/status") {
    return sendJson(res, 200, { push: fcmConfigStatus() });
  }
  if (req.method === "GET" && url.pathname === "/state") {
    return sendJson(res, 200, {
      guardians,
      settings,
      emergencyInfo,
      alerts,
      tokens: allRegisteredTokens().length,
      deviceTokens: roleTokenCounts(),
      location: publicLocation(ensureLatestLocation()),
    });
  }
  if (req.method === "GET" && url.pathname === "/location/latest") {
    return sendJson(res, 200, { location: publicLocation(ensureLatestLocation()) });
  }
  if (req.method === "GET" && url.pathname === "/sensor/schema") {
    return sendJson(res, 200, {
      endpoint: "POST /sensor/update",
      contentType: "application/json",
      coordinateSystem: {
        origin: "ESP32-1 top-left corner",
        normalizedRange: "0.0 ~ 1.0",
        realSizeMeters: { width: 4.5, height: 8.1 },
        grid: "10 x 18 blocks, 1 block = 45cm",
      },
      requiredFields: {
        x: "number, 0.0~1.0",
        y: "number, 0.0~1.0",
        status: "normal | out | still | danger | fall | fallen | no_motion | unknown | model_unavailable",
      },
      optionalFields: {
        room: "거실 | 주방 | 침실-1 | 침실-2 | 욕실 | 현관",
        pose: "standing | walking | sitting | lying",
        confidence: "number, 0.0~1.0",
        breathingRate: "number, breaths per minute. alias: respirationRate, breathRate",
        breathingConfidence: "number, 0.0~1.0. alias: respirationConfidence",
        source: "jetson_orin (real edge inference) | scripted_demo | admin | esp32 | mock. missing -> unknown",
        holdMs: "number, milliseconds to keep manual value",
      },
      authorization: API_TOKEN ? "Authorization: Bearer <HANIUM_API_TOKEN>" : "not required",
      example: {
        x: 0.76,
        y: 0.68,
        status: "danger",
        room: "현관",
        pose: "lying",
        confidence: 0.92,
        breathingRate: 24.1,
        breathingConfidence: 0.84,
        source: "jetson_orin",
        holdMs: 60000,
      },
    });
  }
  if (req.method === "GET" && url.pathname === "/sensor/test-command") {
    const host = req.headers.host || `127.0.0.1:${PORT}`;
    const uri = `http://${host}/sensor/update`;
    const body = {
      x: 0.76,
      y: 0.68,
      status: "danger",
      room: "현관",
      pose: "lying",
      confidence: 0.92,
      breathingRate: 24.1,
      breathingConfidence: 0.84,
      source: "scripted_demo",
      holdMs: 60000,
    };
    const bodyText = JSON.stringify(body).replace(/'/g, "''");
    // 토큰 값 자체는 응답에 넣지 않고 자리표시자만 보여준다.
    const psAuth = API_TOKEN ? " -Headers @{ Authorization = 'Bearer <HANIUM_API_TOKEN>' }" : "";
    const curlAuth = API_TOKEN ? " -H 'Authorization: Bearer <HANIUM_API_TOKEN>'" : "";
    return sendJson(res, 200, {
      powershell:
        `Invoke-RestMethod -Method Post -Uri '${uri}' -ContentType 'application/json; charset=utf-8'${psAuth} -Body '${bodyText}'`,
      curl:
        `curl -X POST '${uri}' -H 'Content-Type: application/json'${curlAuth} -d '${JSON.stringify(body)}'`,
      body,
    });
  }
  if (req.method === "GET" && url.pathname === "/alerts") {
    return sendJson(res, 200, { alerts });
  }
  if (req.method === "GET" && url.pathname === "/guardians") {
    return sendJson(res, 200, { guardians });
  }
  if (req.method === "GET" && url.pathname === "/settings") {
    return sendJson(res, 200, { settings });
  }
  if (req.method === "GET" && url.pathname === "/emergency-info") {
    return sendJson(res, 200, { emergencyInfo });
  }
  if (req.method === "POST" && url.pathname === "/device/register") {
    readJsonBody(req, (body) => {
      const device = registerDeviceToken(body.token, body.role);
      saveState();
      sendJson(res, 200, {
        status: device ? "ok" : "ignored",
        device,
        tokens: allRegisteredTokens().length,
        roleTokenCounts: roleTokenCounts(),
      });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/alarm/test") {
    const alert = {
      id: Date.now(),
      type: "system",
      title: "테스트 알림을 보냈어요",
      message: "보호자 알림 연결을 확인하기 위한 테스트입니다.",
      room: "시스템",
      time: nowLabel(),
      urgent: false,
      resolved: false,
    };
    alerts.unshift(alert);
    saveState();
    const push = sendPushForAlert(alert);
    return sendJson(res, 200, {
      status: push.requested ? "push_requested" : "stored_only",
      recipients: push.recipients,
      push,
    });
  }
  if (req.method === "POST" && url.pathname === "/care-recipient/safe") {
    readJsonBody(req, (body) => {
      const current = ensureLatestLocation();
      const room = normalizeRoom(body.room || current.room, current.x, current.y);
      alerts = alerts.map((alert) => ({
        ...alert,
        resolved: true,
        urgent: false,
      }));

      // 위치 공유 OFF이면 보호자 알림·푸시에도 방 이름을 남기지 않는다.
      const sharingEnabled = isLocationSharingEnabled();
      const alertRoom = sharingEnabled ? room : "위치 비공개";
      const safeRoomText = sharingEnabled ? `${room}에서` : "위치 비공개 상태에서";
      const alert = {
        id: Date.now(),
        type: "safe",
        title: "어르신이 괜찮다고 알려왔어요",
        message: `${safeRoomText} 괜찮다고 표시했어요. 보호자 확인 알림을 정리합니다.`,
        room: alertRoom,
        time: nowLabel(),
        urgent: false,
        resolved: true,
      };
      alerts.unshift(alert);

      forcedScenario = { status: "normal", until: Date.now() + 10000 };
      latestLocation = normalizeLocation({
        ...current,
        status: "normal",
        // 판단 불가였던 신뢰도 0은 이어받지 않는다.
        confidence: current.status === "unknown" ? undefined : current.confidence,
        room,
        pose: "standing",
        source: "care-recipient",
      });
      broadcastLocation(latestLocation);
      saveState();

      const push = sendPushForAlert(alert, latestLocation, {
        targetRole: "guardian",
      });
      sendJson(res, 200, {
        status: push.requested ? "guardian_push_requested" : "stored_only",
        alert,
        location: publicLocation(latestLocation),
        push,
      });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/alerts/resolve") {
    alerts = alerts.map((alert) => ({ ...alert, resolved: true, urgent: false }));
    forcedScenario = { status: "normal", until: Date.now() + 10000 };
    saveState();
    return sendJson(res, 200, { status: "resolved", alerts });
  }
  if (req.method === "POST" && url.pathname === "/alerts/delete") {
    readJsonBody(req, (body) => {
      const id = Number(body.id);
      const before = alerts.length;
      alerts = alerts.filter((alert) => Number(alert.id) !== id);
      const deleted = alerts.length !== before;
      saveState();
      sendJson(res, 200, { status: deleted ? "deleted" : "not_found", deleted, alerts });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/alerts/clear") {
    alerts = [];
    saveState();
    return sendJson(res, 200, { status: "cleared", alerts });
  }
  if (req.method === "POST" && url.pathname === "/demo/reset") {
    return sendJson(res, 200, { status: "ok", ...resetDemoState() });
  }
  if (req.method === "POST" && url.pathname === "/guardians") {
    readJsonBody(req, (body) => {
      const guardian = {
        id: Date.now(),
        name: body.name || "새 보호자",
        phone: body.phone || "010-0000-0000",
        role: body.role || "보호자",
      };
      guardians.push(guardian);
      saveState();
      sendJson(res, 200, { status: "ok", guardian, guardians });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/guardians/update") {
    readJsonBody(req, (body) => {
      const guardian = updateGuardian(body);
      if (!guardian) {
        sendJson(res, 404, { error: "guardian not found", guardians });
        return;
      }
      sendJson(res, 200, { status: "ok", guardian, guardians });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/guardians/delete") {
    readJsonBody(req, (body) => {
      const deleted = deleteGuardian(body);
      if (!deleted) {
        sendJson(res, 404, { error: "guardian not found", guardians });
        return;
      }
      sendJson(res, 200, { status: "ok", guardians });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/settings") {
    readJsonBody(req, (body) => {
      settings = { ...settings, ...body };
      saveState();
      broadcastLocation(ensureLatestLocation());
      sendJson(res, 200, { status: "ok", settings });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/emergency-info") {
    readJsonBody(req, (body) => {
      const nextEmergencyInfo = updateEmergencyInfo(body);
      sendJson(res, 200, { status: "ok", emergencyInfo: nextEmergencyInfo });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/sensor/update") {
    readJsonBody(req, (body) => {
      const result = updateSensorLocation(body);
      sendJson(res, 200, { status: "ok", ...result });
    });
    return;
  }
  if (req.method === "POST" && url.pathname === "/sensor/reset") {
    latestLocation = null;
    manualSensorUntil = 0;
    forcedScenario = null;
    return sendJson(res, 200, { status: "ok", location: null });
  }
  if (req.method === "POST" && url.pathname === "/scenario") {
    readJsonBody(req, (body) => {
      const status = ["normal", "out", "danger", "still"].includes(body.status)
        ? body.status
        : "danger";
      const seconds = Number(body.seconds || 12);
      forcedScenario = { status, until: Date.now() + seconds * 1000 };
      const preset = presetForStatus(status);
      const x = normalizeNumber(body.x, preset.x);
      const y = normalizeNumber(body.y, preset.y);
      latestLocation = normalizeLocation({
        ...preset,
        x,
        y,
        status,
        room: body.room || roomFromPosition(x, y),
        pose: body.pose || poseFromStatus(status),
        confidence: body.confidence ?? confidenceFromStatus(status),
        source: body.source || "scenario",
      });
      manualSensorUntil = Date.now() + Number(body.holdMs || seconds * 1000);
      broadcastLocation(latestLocation);
      saveState();
      sendJson(res, 200, {
        status: "ok",
        scenario: forcedScenario,
        location: publicLocation(latestLocation),
        push: fcmConfigStatus(),
      });
    });
    return;
  }
  return sendJson(res, 404, { error: "not found" });
});

server.on("upgrade", (req, socket) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname !== "/ws/location") {
    socket.destroy();
    return;
  }
  if (!isWebSocketAllowed(req, url)) {
    socket.end("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
    return;
  }

  const key = req.headers["sec-websocket-key"];
  const accept = crypto.createHash("sha1").update(key + WS_GUID).digest("base64");
  socket.write(
    [
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${accept}`,
      "",
      "",
    ].join("\r\n"),
  );

  wsClients.add(socket);
  sendLocationWs(socket, ensureLatestLocation());
  let tick = 0;
  const timer = setInterval(() => {
    if (socket.destroyed) return clearInterval(timer);
    if (forcedScenario && Date.now() > forcedScenario.until) forcedScenario = null;
    const location = currentLocation(tick++);
    addAlertFromLocation(location);
    sendLocationWs(socket, location);
  }, 1000);

  socket.on("close", () => {
    wsClients.delete(socket);
    clearInterval(timer);
  });
  socket.on("error", () => {
    wsClients.delete(socket);
    clearInterval(timer);
  });
});

server.listen(PORT, HOST, () => {
  // 특정 주소(예: LAN IP)에만 바인딩하면 127.0.0.1로는 접속되지 않으므로 그 주소를 안내한다.
  const displayHost = ["0.0.0.0", "::", "localhost"].includes(HOST)
    ? "127.0.0.1"
    : HOST.includes(":")
      ? `[${HOST}]`
      : HOST;
  console.log(`Hanium local server running on http://${displayHost}:${PORT} (listening on ${HOST})`);
  console.log(`Admin page: http://${displayHost}:${PORT}/admin`);
  console.log(`Android emulator app URL: http://10.0.2.2:${PORT}`);
  console.log(`WebSocket endpoint: ws://10.0.2.2:${PORT}/ws/location`);
  if (REAL_SENSOR_ONLY) {
    console.log(
      "Mode: REAL_SENSOR_ONLY=true -> mock motion OFF. Only POST /sensor/update, /scenario and admin input change the state.",
    );
  } else {
    console.log(
      "Mode: REAL_SENSOR_ONLY is not true -> mock motion ON. Synthetic movement and a mock fall about every 45 s are generated (source=mock). Set REAL_SENSOR_ONLY=true to turn it off.",
    );
  }
  console.log(
    API_TOKEN
      ? "API token: required (HANIUM_API_TOKEN is set; send Authorization: Bearer <token>)."
      : "API token: not required (set HANIUM_API_TOKEN to require a Bearer token).",
  );
  console.log(
    CORS_ORIGINS.length
      ? `CORS allowed origins: ${CORS_ORIGINS.join(", ")}`
      : "CORS: same-origin only (set HANIUM_CORS_ORIGIN to allow another origin).",
  );
  if (HOST === "0.0.0.0" || HOST === "::") {
    console.warn(
      `[warn] HOST=${HOST}: the API is reachable from every device on this network (needed for a real phone or a separate Jetson). ` +
        `Use only on a trusted demo network, set HOST=127.0.0.1 for local-only use (the Android emulator still reaches it via 10.0.2.2)` +
        (API_TOKEN ? "." : ", or set HANIUM_API_TOKEN."),
    );
  }
});
