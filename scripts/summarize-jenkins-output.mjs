#!/usr/bin/env node
import fs from 'node:fs';

const inputPath = process.argv[2] && process.argv[2] !== '-' ? process.argv[2] : null;
const raw = inputPath ? fs.readFileSync(inputPath, 'utf8') : fs.readFileSync(0, 'utf8');
const lines = raw.split(/\r?\n/).map(cleanLine);

const contextBefore = numberFromEnv('JENKINS_SUMMARY_CONTEXT_BEFORE', 8);
const contextAfter = numberFromEnv('JENKINS_SUMMARY_CONTEXT_AFTER', 14);
const maxBlocks = numberFromEnv('JENKINS_SUMMARY_MAX_BLOCKS', 14);
const maxLinesWithoutMarkers = numberFromEnv('JENKINS_SUMMARY_FALLBACK_LINES', 80);

const markerPatterns = [
  /\b(fatal|error|failed|failure|exception)\b/i,
  /\b(TypeError|ReferenceError|SyntaxError|RangeError|AggregateError)\b/,
  /\b(TS|NG|NX|EADDR|ECONN|ENOTFOUND|ETIMEDOUT|EACCES|ENOENT)\d*\b/,
  /\bCannot find module\b/i,
  /\bModule not found\b/i,
  /\bCompilation failed\b/i,
  /\bProcess completed with exit code [1-9]\d*\b/i,
  /\bscript returned exit code [1-9]\d*\b/i,
  /\bFinished:\s+(FAILURE|UNSTABLE|ABORTED)\b/i,
  /\bTests?:\s+.*\bfailed\b/i,
  /\bTest Suites?:\s+.*\bfailed\b/i,
  /\b\d+\s+failed\b/i,
  /\bexpect\(.*\)\b/,
  /\bstrict mode violation\b/i,
  /\bTimed out\b/i,
  /\blocator\(/i,
  /\bnpm ERR!\b/i,
  /[✖✘×]\s+/,
];

const noisePatterns = [
  /^\s*$/,
  /^\[Pipeline]/,
  /^Running in /,
  /^Obtained /,
  /^Loading library /,
  /^The recommended git tool is:/,
  /^No credentials specified/,
  /^Commit message:/,
  /^ > git /,
  /^using credential /i,
  /^Selected Git installation /,
  /^Cloning repository /,
  /^Checking out Revision /,
  /^using GIT_/,
  /^Avoid second fetch/,
  /^Cleaning workspace/,
  /^Sending interrupt signal/,
  /^Archive the artifacts/i,
  /^Recording test results/i,
  /^sent [\d,]+ bytes\s+received/i,
  /^total size is /,
  /^\s*%\s+Total\s+% Received/,
  /^\s*\d+\s+\d+/,
];

const commandIndexes = [];
const markerIndexes = [];
const finalResult = [...lines].reverse().find((line) => /^Finished:\s+/.test(line))?.replace(/^Finished:\s+/, '') ?? 'UNKNOWN';

lines.forEach((line, index) => {
  if (/^\+\s+\S/.test(line) || /^>\s+\S/.test(line) || /^==>\s+/.test(line)) {
    commandIndexes.push(index);
  }
  if (isMarker(line)) {
    markerIndexes.push(index);
  }
});

const stageLines = lines
  .map((line, index) => ({ line, index }))
  .filter(({ line }) => /^==>\s+/.test(line) || /^Running \d+ tests?/.test(line) || /^FAIL\s+/.test(line) || /^Finished:\s+/.test(line));

const ranges = mergeRanges(
  markerIndexes.map((index) => [
    Math.max(0, index - contextBefore),
    Math.min(lines.length - 1, index + contextAfter),
  ]),
).slice(0, maxBlocks);

printHeader(inputPath, finalResult, markerIndexes.length);

if (stageLines.length) {
  console.log('\nKey stage markers:');
  for (const { index, line } of stageLines.slice(-18)) {
    console.log(formatLine(index, line));
  }
}

if (finalResult === 'SUCCESS') {
  console.log('\nResult is SUCCESS. No failure excerpts needed.');
} else if (markerIndexes.length) {
  const firstMarker = markerIndexes[0];
  const recentCommands = commandIndexes.filter((index) => index <= firstMarker).slice(-8);
  if (recentCommands.length) {
    console.log('\nCommands before first failure marker:');
    for (const index of recentCommands) {
      console.log(formatLine(index, lines[index]));
    }
  }

  console.log('\nRelevant failure excerpts:');
  ranges.forEach(([start, end], rangeIndex) => {
    if (rangeIndex > 0) {
      console.log('\n---');
    }
    for (let index = start; index <= end; index += 1) {
      if (!isNoise(lines[index]) || isMarker(lines[index])) {
        console.log(formatLine(index, lines[index]));
      }
    }
  });
} else {
  console.log('\nNo high-signal failure markers found. Showing the last non-noise lines instead:');
  const fallback = lines
    .map((line, index) => ({ line, index }))
    .filter(({ line }) => !isNoise(line))
    .slice(-maxLinesWithoutMarkers);
  for (const { index, line } of fallback) {
    console.log(formatLine(index, line));
  }
}

function cleanLine(line) {
  return line
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/^\[\d{4}-\d{2}-\d{2}T[^\]]+]\s*/, '')
    .replace(/^\[WebServer]\s*/, '')
    .replace(/\s+$/g, '');
}

function isMarker(line) {
  if (!line || isNoise(line)) {
    return false;
  }
  return markerPatterns.some((pattern) => pattern.test(line));
}

function isNoise(line) {
  return noisePatterns.some((pattern) => pattern.test(line));
}

function mergeRanges(rangesToMerge) {
  const sorted = [...rangesToMerge].sort((left, right) => left[0] - right[0]);
  const merged = [];
  for (const range of sorted) {
    const previous = merged.at(-1);
    if (!previous || range[0] > previous[1] + 1) {
      merged.push([...range]);
      continue;
    }
    previous[1] = Math.max(previous[1], range[1]);
  }
  return merged;
}

function formatLine(index, line) {
  return `${String(index + 1).padStart(6, ' ')} | ${line}`;
}

function numberFromEnv(name, fallback) {
  const value = Number.parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function printHeader(path, result, markerCount) {
  console.log('Jenkins console summary');
  console.log(`Source: ${path ?? 'stdin'}`);
  console.log(`Result: ${result}`);
  console.log(`Signal lines: ${result === 'SUCCESS' ? 0 : markerCount}`);
}
