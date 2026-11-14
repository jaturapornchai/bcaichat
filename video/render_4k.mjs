#!/usr/bin/env node
/**
 * BC Ai Chat — True 4K UHD (3840x2160 @ 30fps) Parallel Renderer & Two-Pass Audio Master
 *
 * Renders `stage/stage_5phones.html` driven deterministically by `data/timeline.json`
 * across parallel Playwright Chromium workers (4 workers default, auto-fallback to 2 on low RAM),
 * mixes `data/voice_master.wav` + `data/sfx_master.wav` using FFmpeg Two-Pass EBU R128 Loudnorm
 * (-14 LUFS, TP -1.5 dBTP) + gentle linear mix + lookahead limiter,
 * and outputs:
 *   - output/bc_ai_chat_5phones_4k.mp4 (3840x2160, 30fps, H.264 High, BT.709, AAC 48kHz stereo 320k)
 *   - output/thumbnail_4k.png          (3840x2160 PNG from ?thumbnail=1)
 *
 * Usage:
 *   node video/render_4k.mjs                  # Full 4K render + thumbnail + cleanup
 *   node video/render_4k.mjs --smoke          # 3s (90 frames) smoke pipeline + thumbnail + ffprobe check
 *   node video/render_4k.mjs --workers=2      # Override worker count
 *   node video/render_4k.mjs --thumbnail-only # Render & probe thumbnail_4k.png only
 */

import fs from "node:fs";
import fsp from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const VIDEO_DIR = __dirname;
const ROOT_DIR = path.resolve(VIDEO_DIR, "..");

const PLAYWRIGHT_MJS = path.join(ROOT_DIR, "web", "node_modules", "playwright", "index.mjs");
const TIMELINE_PATH = path.join(VIDEO_DIR, "data", "timeline.json");
const VOICE_WAV = path.join(VIDEO_DIR, "data", "voice_master.wav");
const SFX_WAV = path.join(VIDEO_DIR, "data", "sfx_master.wav");
const SEGMENTS_DIR = path.join(VIDEO_DIR, "segments");
const OUTPUT_DIR = path.join(VIDEO_DIR, "output");
const FINAL_VIDEO_PATH = path.join(OUTPUT_DIR, "bc_ai_chat_5phones_4k.mp4");
const SMOKE_VIDEO_PATH = path.join(OUTPUT_DIR, "smoke_4k.mp4");
const THUMBNAIL_PATH = path.join(OUTPUT_DIR, "thumbnail_4k.png");

const FPS = 30;
const VIEWPORT_W = 1920;
const VIEWPORT_H = 1080;
const SCALE_FACTOR = 2; // 1920x1080 @ 2x => 3840x2160 True 4K UHD
const MIN_FREE_RAM_FOR_4_WORKERS = 4 * 1024 * 1024 * 1024; // 4 GiB

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".wav": "audio/wav",
  ".woff2": "font/woff2",
  ".woff": "font/woff",
  ".ttf": "font/ttf",
  ".srt": "text/plain; charset=utf-8",
};

function parseArgs(argv) {
  const opts = {
    smoke: false,
    thumbnailOnly: false,
    keepSegments: false,
    workers: null,
  };
  for (const arg of argv) {
    if (arg === "--smoke") opts.smoke = true;
    else if (arg === "--thumbnail-only") opts.thumbnailOnly = true;
    else if (arg === "--keep-segments") opts.keepSegments = true;
    else if (arg.startsWith("--workers=")) {
      const n = Number(arg.slice("--workers=".length));
      if (Number.isInteger(n) && n >= 1 && n <= 8) opts.workers = n;
      else throw new Error(`Invalid --workers value: ${arg}`);
    } else if (arg === "--help" || arg === "-h") {
      console.log(
        "Usage: node render_4k.mjs [--smoke] [--workers=4] [--thumbnail-only] [--keep-segments]"
      );
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return opts;
}

function formatDuration(sec) {
  const s = Math.max(0, sec);
  const mins = Math.floor(s / 60);
  const rem = s - mins * 60;
  return `${mins}m ${rem.toFixed(1)}s`;
}

function formatMB(bytes) {
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function startStaticServer(rootDir) {
  return new Promise((resolve, reject) => {
    const resolvedRoot = path.resolve(rootDir);
    const server = http.createServer(async (req, res) => {
      try {
        const reqUrl = new URL(req.url || "/", "http://127.0.0.1");
        let relPath = decodeURIComponent(reqUrl.pathname).replace(/^\/+/, "");
        if (!relPath) relPath = "stage/stage_5phones.html";
        const absPath = path.resolve(resolvedRoot, relPath);
        if (absPath !== resolvedRoot && !absPath.startsWith(resolvedRoot + path.sep)) {
          res.writeHead(403);
          res.end("Forbidden");
          return;
        }
        const stat = await fsp.stat(absPath).catch(() => null);
        if (!stat || !stat.isFile()) {
          res.writeHead(404);
          res.end("Not Found");
          return;
        }
        const ext = path.extname(absPath).toLowerCase();
        res.writeHead(200, {
          "Content-Type": MIME_TYPES[ext] || "application/octet-stream",
          "Cache-Control": "no-store",
        });
        fs.createReadStream(absPath).pipe(res);
      } catch (err) {
        res.writeHead(500);
        res.end(String(err));
      }
    });
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const addr = server.address();
      resolve({
        server,
        port: addr.port,
        baseUrl: `http://127.0.0.1:${addr.port}`,
        close: () =>
          new Promise((resClose) => {
            server.close(() => resClose());
          }),
      });
    });
  });
}

function runProcess(cmd, args, { captureOutput = false, label = cmd } = {}) {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, {
      stdio: captureOutput ? ["ignore", "pipe", "pipe"] : ["ignore", "inherit", "pipe"],
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    if (proc.stdout) {
      proc.stdout.on("data", (chunk) => {
        stdout += chunk.toString();
      });
    }
    if (proc.stderr) {
      proc.stderr.on("data", (chunk) => {
        stderr += chunk.toString();
      });
    }
    proc.on("error", (err) => reject(new Error(`${label} failed to start: ${err.message}`)));
    proc.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        const tail = stderr.trim().split(/\r?\n/).slice(-25).join("\n");
        reject(new Error(`${label} exited with code ${code}:\n${tail}`));
      }
    });
  });
}

async function ffprobeJson(filePath) {
  const { stdout } = await runProcess(
    "ffprobe",
    ["-v", "error", "-show_format", "-show_streams", "-of", "json", filePath],
    { captureOutput: true, label: `ffprobe(${path.basename(filePath)})` }
  );
  return JSON.parse(stdout);
}

async function waitPromptFontsReady(page) {
  await page.waitForFunction(
    () => typeof window.initTimeline === "function" && typeof window.renderAtTime === "function",
    { timeout: 30000 }
  );
  await page.evaluate(async () => {
    await document.fonts.ready;
    // Explicitly ensure key Prompt weights are requested and loaded
    await Promise.allSettled([
      document.fonts.load('400 16px "Prompt"'),
      document.fonts.load('600 20px "Prompt"'),
      document.fonts.load('700 28px "Prompt"'),
      document.fonts.load('800 40px "Prompt"'),
    ]);
    await document.fonts.ready;
  });
  const fontInfo = await page.evaluate(() => ({
    status: document.fonts.status,
    size: document.fonts.size,
    prompt400: document.fonts.check('400 16px "Prompt"'),
    prompt700: document.fonts.check('700 28px "Prompt"'),
  }));
  return fontInfo;
}

async function launchChromiumBrowser(chromium) {
  const defaultExe = chromium.executablePath();
  if (defaultExe && fs.existsSync(defaultExe)) {
    return chromium.launch({ headless: true, executablePath: defaultExe });
  }
  const cacheDir = path.join(process.env.LOCALAPPDATA || "", "ms-playwright");
  if (fs.existsSync(cacheDir)) {
    const dirs = fs
      .readdirSync(cacheDir)
      .filter((d) => /^chromium-\d+$/.test(d) || /^chromium_headless_shell-\d+$/.test(d))
      .sort((a, b) => {
        const score = (n) => (n.startsWith("chromium-") ? 100000 : 0) + Number(n.split("-").pop());
        return score(b) - score(a);
      });
    for (const d of dirs) {
      const candidates = [
        path.join(cacheDir, d, "chrome-win64", "chrome.exe"),
        path.join(cacheDir, d, "chrome-headless-shell-win64", "chrome-headless-shell.exe"),
      ];
      for (const exe of candidates) {
        if (fs.existsSync(exe)) {
          return chromium.launch({ headless: true, executablePath: exe });
        }
      }
    }
  }
  try {
    return await chromium.launch({ headless: true, channel: "chrome" });
  } catch {
    return chromium.launch({ headless: true, channel: "msedge" });
  }
}

async function renderThumbnail({ chromium, baseUrl, timeline, outputPath }) {
  console.log(`[thumbnail] Launching Chromium for 4K thumbnail (${VIEWPORT_W * SCALE_FACTOR}x${VIEWPORT_H * SCALE_FACTOR})...`);
  const browser = await launchChromiumBrowser(chromium);
  try {
    const context = await browser.newContext({
      viewport: { width: VIEWPORT_W, height: VIEWPORT_H },
      deviceScaleFactor: SCALE_FACTOR,
    });
    const page = await context.newPage();
    const pageErrors = [];
    page.on("pageerror", (err) => pageErrors.push(err.message));
    page.on("console", (msg) => {
      if (msg.type() === "error") pageErrors.push(msg.text());
    });

    await page.goto(`${baseUrl}/stage/stage_5phones.html?thumbnail=1`, {
      waitUntil: "networkidle",
      timeout: 60000,
    });
    const fontInfo = await waitPromptFontsReady(page);
    await page.evaluate((tl) => {
      window.initTimeline(tl);
      window.renderThumbnail();
    }, timeline);

    if (pageErrors.length > 0) {
      throw new Error(`Thumbnail page errors: ${pageErrors.join(" | ")}`);
    }

    await fsp.mkdir(path.dirname(outputPath), { recursive: true });
    await page.screenshot({ path: outputPath, type: "png" });

    const probe = await ffprobeJson(outputPath);
    const vStream = (probe.streams || []).find((s) => s.codec_type === "video");
    if (!vStream || vStream.width !== 3840 || vStream.height !== 2160) {
      throw new Error(
        `Thumbnail dimension mismatch: expected 3840x2160, got ${vStream?.width}x${vStream?.height}`
      );
    }
    const stat = await fsp.stat(outputPath);
    console.log(
      `[thumbnail] Verified ${outputPath}: ${vStream.width}x${vStream.height} (${vStream.codec_name}, ${formatMB(stat.size)}, Prompt loaded=${fontInfo.prompt400}/${fontInfo.prompt700}, fonts=${fontInfo.size})`
    );
    return { width: vStream.width, height: vStream.height, size: stat.size, fontInfo };
  } finally {
    await browser.close();
  }
}

function buildChunks(totalFrames, workerCount) {
  const chunks = [];
  const base = Math.floor(totalFrames / workerCount);
  const rem = totalFrames % workerCount;
  let cursor = 0;
  for (let i = 0; i < workerCount; i++) {
    const count = base + (i < rem ? 1 : 0);
    if (count <= 0) continue;
    chunks.push({
      workerIdx: i,
      startFrame: cursor,
      endFrame: cursor + count - 1,
      frameCount: count,
    });
    cursor += count;
  }
  return chunks;
}

async function renderSegmentWorker({
  chromium,
  baseUrl,
  timeline,
  chunk,
  segPath,
  onFrameProgress,
}) {
  const { workerIdx, startFrame, endFrame, frameCount } = chunk;
  const browser = await launchChromiumBrowser(chromium);
  let ffmpegProc = null;
  let ffmpegStderr = "";
  let ffmpegClosed = null;

  try {
    const context = await browser.newContext({
      viewport: { width: VIEWPORT_W, height: VIEWPORT_H },
      deviceScaleFactor: SCALE_FACTOR,
    });
    const page = await context.newPage();
    const pageErrors = [];
    page.on("pageerror", (err) => pageErrors.push(err.message));
    page.on("console", (msg) => {
      if (msg.type() === "error") pageErrors.push(msg.text());
    });

    await page.goto(`${baseUrl}/stage/stage_5phones.html`, {
      waitUntil: "networkidle",
      timeout: 60000,
    });
    const fontInfo = await waitPromptFontsReady(page);
    await page.evaluate((tl) => window.initTimeline(tl), timeline);

    if (workerIdx === 0) {
      console.log(
        `[fonts] status=${fontInfo.status} size=${fontInfo.size} Prompt400=${fontInfo.prompt400} Prompt700=${fontInfo.prompt700}`
      );
    }

    ffmpegProc = spawn(
      "ffmpeg",
      [
        "-y",
        "-f",
        "image2pipe",
        "-vcodec",
        "mjpeg",
        "-framerate",
        String(FPS),
        "-i",
        "-",
        "-vf",
        "scale=out_range=limited:out_color_matrix=bt709,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv,format=yuv420p",
        "-c:v",
        "libx264",
        "-preset",
        "fast",
        "-crf",
        "16",
        "-pix_fmt",
        "yuv420p",
        "-color_range",
        "tv",
        "-colorspace",
        "bt709",
        "-color_primaries",
        "bt709",
        "-color_trc",
        "bt709",
        segPath,
      ],
      {
        stdio: ["pipe", "ignore", "pipe"],
        windowsHide: true,
      }
    );

    ffmpegProc.stderr.on("data", (d) => {
      ffmpegStderr += d.toString();
      if (ffmpegStderr.length > 16384) {
        ffmpegStderr = ffmpegStderr.slice(-8192);
      }
    });

    let ffmpegExitedEarly = null;
    ffmpegClosed = new Promise((resolve, reject) => {
      ffmpegProc.on("error", reject);
      ffmpegProc.on("close", (code) => {
        if (code === 0) resolve();
        else {
          const tail = ffmpegStderr.trim().split(/\r?\n/).slice(-20).join("\n");
          reject(new Error(`ffmpeg seg_${workerIdx} exited with code ${code}:\n${tail}`));
        }
      });
    });
    ffmpegClosed.catch((err) => {
      ffmpegExitedEarly = err;
    });

    for (let f = startFrame; f <= endFrame; f++) {
      if (ffmpegExitedEarly) throw ffmpegExitedEarly;
      const t = f / FPS;
      await page.evaluate((sec) => window.renderAtTime(sec), t);
      const buf = await page.screenshot({ type: "jpeg", quality: 94 });
      if (pageErrors.length > 0) {
        throw new Error(`Worker ${workerIdx} page errors at frame ${f}: ${pageErrors.join(" | ")}`);
      }
      if (!ffmpegProc.stdin.write(buf)) {
        await Promise.race([
          new Promise((res) => ffmpegProc.stdin.once("drain", res)),
          ffmpegClosed,
        ]);
      }
      onFrameProgress(workerIdx, f - startFrame + 1, frameCount);
    }

    ffmpegProc.stdin.end();
    await ffmpegClosed;

    const probe = await ffprobeJson(segPath);
    const vStream = (probe.streams || []).find((s) => s.codec_type === "video");
    const actualFrames = Number(vStream?.nb_frames || 0);
    if (!vStream || vStream.width !== 3840 || vStream.height !== 2160 || actualFrames !== frameCount) {
      throw new Error(
        `Segment seg_${workerIdx}.mp4 validation failed: got ${vStream?.width}x${vStream?.height}, nb_frames=${actualFrames}, expected=${frameCount}`
      );
    }
    return { workerIdx, segPath, frameCount, width: vStream.width, height: vStream.height };
  } catch (err) {
    if (ffmpegProc && !ffmpegProc.killed) {
      try {
        ffmpegProc.stdin?.destroy();
        ffmpegProc.kill("SIGKILL");
      } catch {
        // ignore cleanup error
      }
    }
    throw err;
  } finally {
    await browser.close().catch(() => {});
  }
}

async function renderAllSegmentsWithAutoFallback({
  chromium,
  baseUrl,
  timeline,
  totalFrames,
  requestedWorkers,
}) {
  let workerCount = requestedWorkers ?? 4;
  const freeRam = os.freemem();
  if (workerCount > 2 && freeRam < MIN_FREE_RAM_FOR_4_WORKERS) {
    console.warn(
      `[render] Low free RAM (${(freeRam / 1024 ** 3).toFixed(2)} GB < 4.00 GB). Reducing workers from ${workerCount} to 2.`
    );
    workerCount = 2;
  }

  const runAttempt = async (nWorkers) => {
    await fsp.rm(SEGMENTS_DIR, { recursive: true, force: true });
    await fsp.mkdir(SEGMENTS_DIR, { recursive: true });

    const chunks = buildChunks(totalFrames, nWorkers);
    const perWorkerDone = new Array(chunks.length).fill(0);
    const t0 = Date.now();
    let lastLoggedTotal = 0;

    console.log(
      `[render] Starting ${chunks.length} Playwright Chromium worker(s) for ${totalFrames} frames (${VIEWPORT_W * SCALE_FACTOR}x${VIEWPORT_H * SCALE_FACTOR} @ ${FPS}fps)...`
    );
    for (const c of chunks) {
      console.log(
        `  - worker ${c.workerIdx}: frames ${c.startFrame}..${c.endFrame} (${c.frameCount} frames)`
      );
    }

    const onFrameProgress = (wIdx, doneInWorker) => {
      perWorkerDone[wIdx] = doneInWorker;
      const totalDone = perWorkerDone.reduce((a, b) => a + b, 0);
      if (totalDone === totalFrames || totalDone - lastLoggedTotal >= 120) {
        lastLoggedTotal = totalDone;
        const elapsedSec = (Date.now() - t0) / 1000;
        const fps = totalDone / Math.max(0.01, elapsedSec);
        const etaSec = (totalFrames - totalDone) / Math.max(0.01, fps);
        const freeGb = (os.freemem() / 1024 ** 3).toFixed(2);
        const rssMb = (process.memoryUsage().rss / 1024 ** 2).toFixed(0);
        console.log(
          `[progress] ${totalDone}/${totalFrames} (${((totalDone / totalFrames) * 100).toFixed(1)}%) | ${fps.toFixed(2)} fps | elapsed ${formatDuration(elapsedSec)} | ETA ${formatDuration(etaSec)} | RSS ${rssMb} MB | FreeRAM ${freeGb} GB`
        );
      }
    };

    const results = await Promise.all(
      chunks.map((chunk) =>
        renderSegmentWorker({
          chromium,
          baseUrl,
          timeline,
          chunk,
          segPath: path.join(SEGMENTS_DIR, `seg_${chunk.workerIdx}.mp4`),
          onFrameProgress,
        })
      )
    );
    results.sort((a, b) => a.workerIdx - b.workerIdx);
    const elapsedSec = (Date.now() - t0) / 1000;
    console.log(
      `[render] Completed ${totalFrames} frames across ${chunks.length} workers in ${formatDuration(elapsedSec)} (${(totalFrames / elapsedSec).toFixed(2)} fps effective)`
    );
    return results;
  };

  try {
    return await runAttempt(workerCount);
  } catch (err) {
    if (workerCount > 2) {
      console.warn(
        `[render] ${workerCount}-worker run failed (${err.message}). Retrying automatically with 2 workers...`
      );
      return await runAttempt(2);
    }
    throw err;
  }
}

async function buildTwoPassNormalizedAudio({ trimSec = null }) {
  console.log("[audio] Pass 1: Measuring voice_master.wav loudness (EBU R128 I=-14 TP=-1.5 LRA=11)...");
  const pass1 = await runProcess(
    "ffmpeg",
    [
      "-hide_banner",
      "-i",
      VOICE_WAV,
      "-af",
      "aformat=sample_rates=48000:channel_layouts=stereo,loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json",
      "-f",
      "null",
      "-",
    ],
    { captureOutput: true, label: "ffmpeg-loudnorm-pass1" }
  );

  const jsonMatch = pass1.stderr.match(/\{[\s\S]*?"input_i"[\s\S]*?\}/);
  if (!jsonMatch) {
    throw new Error(`Failed to parse loudnorm pass-1 JSON from stderr:\n${pass1.stderr.slice(-800)}`);
  }
  const m = JSON.parse(jsonMatch[0]);
  console.log(
    `[audio] Pass 1 measured: input_i=${m.input_i} LUFS, input_tp=${m.input_tp} dBTP, input_lra=${m.input_lra} LU, input_thresh=${m.input_thresh}, target_offset=${m.target_offset}`
  );

  const audioMasterWav = path.join(SEGMENTS_DIR, "audio_master.wav");
  const filterGraph = [
    `[0:a]aformat=sample_rates=48000:channel_layouts=stereo,loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=${m.input_i}:measured_TP=${m.input_tp}:measured_LRA=${m.input_lra}:measured_thresh=${m.input_thresh}:offset=${m.target_offset}:linear=true,aresample=48000[v]`,
    `[1:a]aformat=sample_rates=48000:channel_layouts=stereo,volume=0.95[s]`,
    `[v][s]amix=inputs=2:duration=first:dropout_transition=0:normalize=0,alimiter=limit=0.89:level=false[aout]`,
  ].join(";");

  const pass2Args = [
    "-y",
    "-hide_banner",
    "-i",
    VOICE_WAV,
    "-i",
    SFX_WAV,
    "-filter_complex",
    filterGraph,
    "-map",
    "[aout]",
    "-c:a",
    "pcm_s24le",
    "-ar",
    "48000",
    "-ac",
    "2",
  ];
  if (trimSec !== null) {
    pass2Args.push("-t", trimSec.toFixed(6));
  }
  pass2Args.push(audioMasterWav);

  console.log("[audio] Pass 2: Normalizing voice + linear mixing subtle SFX + alimiter(limit=0.89)...");
  await runProcess("ffmpeg", pass2Args, { captureOutput: true, label: "ffmpeg-audio-mix" });

  // Measure resulting master audio loudness
  const ebu = await runProcess(
    "ffmpeg",
    ["-hide_banner", "-i", audioMasterWav, "-af", "ebur128=peak=true", "-f", "null", "-"],
    { captureOutput: true, label: "ffmpeg-ebur128-verify" }
  );
  const summaryMatch = ebu.stderr.match(/Summary:[\s\S]*$/);
  if (summaryMatch) {
    const iMatch = summaryMatch[0].match(/I:\s*([-0-9.]+)\s*LUFS/);
    const tpMatch = summaryMatch[0].match(/Peak:\s*([-0-9.]+)\s*dBFS/);
    console.log(
      `[audio] Master WAV verified: Integrated=${iMatch?.[1] ?? "?"} LUFS, TruePeak=${tpMatch?.[1] ?? "?"} dBFS`
    );
  }
  return audioMasterWav;
}

async function concatAndMuxFinal({ segments, audioMasterWav, outputPath, expectedFrames }) {
  const concatTxtPath = path.join(SEGMENTS_DIR, "concat.txt");
  const concatBody = segments
    .map((s) => `file '${s.segPath.replace(/\\/g, "/").replace(/'/g, "'\\''")}'`)
    .join("\n");
  await fsp.writeFile(concatTxtPath, concatBody + "\n", "utf8");
  await fsp.mkdir(path.dirname(outputPath), { recursive: true });

  console.log(`[mux] Concatenating ${segments.length} segments + mastered audio => ${outputPath}...`);
  const t0 = Date.now();
  await runProcess(
    "ffmpeg",
    [
      "-y",
      "-hide_banner",
      "-f",
      "concat",
      "-safe",
      "0",
      "-i",
      concatTxtPath,
      "-i",
      audioMasterWav,
      "-map",
      "0:v:0",
      "-map",
      "1:a:0",
      "-c:v",
      "libx264",
      "-profile:v",
      "high",
      "-preset",
      "medium",
      "-crf",
      "18",
      "-pix_fmt",
      "yuv420p",
      "-r",
      "30",
      "-g",
      "30",
      "-bf",
      "2",
      "-color_range",
      "tv",
      "-colorspace",
      "bt709",
      "-color_primaries",
      "bt709",
      "-color_trc",
      "bt709",
      "-c:a",
      "aac",
      "-b:a",
      "320k",
      "-ar",
      "48000",
      "-ac",
      "2",
      "-movflags",
      "+faststart",
      outputPath,
    ],
    { captureOutput: true, label: "ffmpeg-final-mux" }
  );
  console.log(`[mux] Completed in ${formatDuration((Date.now() - t0) / 1000)}.`);

  const probe = await ffprobeJson(outputPath);
  const vStream = (probe.streams || []).find((s) => s.codec_type === "video");
  const aStream = (probe.streams || []).find((s) => s.codec_type === "audio");
  if (!vStream || !aStream) {
    throw new Error(`Missing video or audio stream in ${outputPath}`);
  }
  if (vStream.width !== 3840 || vStream.height !== 2160) {
    throw new Error(`Final video resolution mismatch: ${vStream.width}x${vStream.height}`);
  }
  if (vStream.codec_name !== "h264" || vStream.pix_fmt !== "yuv420p") {
    throw new Error(`Final video codec/pix_fmt mismatch: ${vStream.codec_name} / ${vStream.pix_fmt}`);
  }
  if (
    vStream.color_space !== "bt709" ||
    vStream.color_primaries !== "bt709" ||
    vStream.color_transfer !== "bt709" ||
    vStream.color_range !== "tv"
  ) {
    throw new Error(
      `Final video BT.709 color tag mismatch: space=${vStream.color_space} primaries=${vStream.color_primaries} trc=${vStream.color_transfer} range=${vStream.color_range}`
    );
  }
  if (Number(vStream.nb_frames) !== expectedFrames) {
    throw new Error(`Final video frame count mismatch: got ${vStream.nb_frames}, expected ${expectedFrames}`);
  }
  if (aStream.codec_name !== "aac" || Number(aStream.sample_rate) !== 48000 || aStream.channels !== 2) {
    throw new Error(
      `Final audio mismatch: ${aStream.codec_name} ${aStream.sample_rate}Hz ch=${aStream.channels}`
    );
  }

  // Verify final AAC loudness inside MP4
  const ebuFinal = await runProcess(
    "ffmpeg",
    ["-hide_banner", "-i", outputPath, "-vn", "-af", "ebur128=peak=true", "-f", "null", "-"],
    { captureOutput: true, label: "ffmpeg-final-ebur128" }
  );
  const finalI = ebuFinal.stderr.match(/Summary:[\s\S]*?I:\s*([-0-9.]+)\s*LUFS/)?.[1] ?? "?";
  const finalTp = ebuFinal.stderr.match(/Summary:[\s\S]*?Peak:\s*([-0-9.]+)\s*dBFS/)?.[1] ?? "?";

  const stat = await fsp.stat(outputPath);
  console.log(
    `[verify] ${outputPath}: ${formatMB(stat.size)}, dur=${Number(probe.format.duration).toFixed(3)}s, video=${vStream.codec_name}(${vStream.profile}) ${vStream.width}x${vStream.height} ${vStream.pix_fmt} ${vStream.r_frame_rate} frames=${vStream.nb_frames} bt709=${vStream.color_space}, audio=${aStream.codec_name} ${aStream.sample_rate}Hz ${aStream.channels}ch ${Math.round(Number(aStream.bit_rate) / 1000)}kbps, loudness=${finalI} LUFS (TP ${finalTp} dBFS)`
  );

  return { probe, stat, vStream, aStream, finalI, finalTp };
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const overallT0 = Date.now();

  for (const required of [PLAYWRIGHT_MJS, TIMELINE_PATH, VOICE_WAV, SFX_WAV]) {
    if (!fs.existsSync(required)) {
      throw new Error(`Required input missing: ${required}`);
    }
  }

  const timeline = JSON.parse(await fsp.readFile(TIMELINE_PATH, "utf8"));
  const fullFrames = Math.round(timeline.totalDuration * FPS);
  const targetFrames = opts.smoke ? Math.min(90, fullFrames) : fullFrames;
  const targetDuration = targetFrames / FPS;
  const outputVideoPath = opts.smoke ? SMOKE_VIDEO_PATH : FINAL_VIDEO_PATH;

  console.log(
    `[init] mode=${opts.smoke ? "SMOKE (3s)" : opts.thumbnailOnly ? "THUMBNAIL-ONLY" : "FULL 4K"} | timeline.totalDuration=${timeline.totalDuration}s | fullFrames=${fullFrames} | targetFrames=${targetFrames}`
  );
  console.log(
    `[init] system: ${os.cpus().length} CPUs, TotalRAM=${(os.totalmem() / 1024 ** 3).toFixed(2)} GB, FreeRAM=${(os.freemem() / 1024 ** 3).toFixed(2)} GB`
  );

  const { chromium } = await import(pathToFileURL(PLAYWRIGHT_MJS).href);
  const server = await startStaticServer(VIDEO_DIR);
  console.log(`[http] Serving ${VIDEO_DIR} at ${server.baseUrl}`);

  try {
    // 1. Always render & verify 4K thumbnail
    await renderThumbnail({
      chromium,
      baseUrl: server.baseUrl,
      timeline,
      outputPath: THUMBNAIL_PATH,
    });

    if (opts.thumbnailOnly) {
      return;
    }

    // 2. Render video segments across parallel Playwright workers
    const segments = await renderAllSegmentsWithAutoFallback({
      chromium,
      baseUrl: server.baseUrl,
      timeline,
      totalFrames: targetFrames,
      requestedWorkers: opts.workers,
    });

    // 3. Two-Pass Loudnorm + Mix Audio
    const audioMasterWav = await buildTwoPassNormalizedAudio({
      trimSec: opts.smoke ? targetDuration : null,
    });

    // 4. Seamless Concat + Final MP4 Mux + ffprobe verification
    await concatAndMuxFinal({
      segments,
      audioMasterWav,
      outputPath: outputVideoPath,
      expectedFrames: targetFrames,
    });

    // 5. Cleanup temporary segments/ (and smoke mp4 if in smoke mode)
    if (!opts.keepSegments) {
      await fsp.rm(SEGMENTS_DIR, { recursive: true, force: true });
      console.log(`[cleanup] Removed temporary directory: ${SEGMENTS_DIR}`);
    }
    if (opts.smoke && fs.existsSync(SMOKE_VIDEO_PATH)) {
      await fsp.rm(SMOKE_VIDEO_PATH, { force: true });
      console.log(`[cleanup] Removed temporary smoke video: ${SMOKE_VIDEO_PATH}`);
    }

    console.log(`[done] Total elapsed time: ${formatDuration((Date.now() - overallT0) / 1000)}`);
  } finally {
    await server.close();
    console.log("[http] Static server closed.");
  }
}

main().catch((err) => {
  console.error("[fatal]", err);
  process.exit(1);
});
