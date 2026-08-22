#!/usr/bin/env node

import {
  existsSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const INFRA_DIR = resolve(SCRIPT_DIR, '../..');
const REPO_ROOT = resolve(INFRA_DIR, '..');
const WORKSPACE_ROOT = dirname(REPO_ROOT);
const REGISTRY_PATH = join(INFRA_DIR, 'workshops.json');

function shellQuote(value) {
  return `'${String(value).replaceAll("'", `'\"'\"'`)}'`;
}

function parseAttributes(text) {
  const attributes = {};
  const pattern = /([A-Za-z][\w-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s}]+))/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    attributes[match[1]] = match[2] ?? match[3] ?? match[4] ?? '';
  }
  return attributes;
}

function parseBoolean(value, defaultValue) {
  if (value === undefined) return defaultValue;
  if (value === true || value === 'true') return true;
  if (value === false || value === 'false') return false;
  throw new Error(`Expected true or false, received: ${value}`);
}

function listMarkdownFiles(root) {
  const files = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) files.push(...listMarkdownFiles(path));
    if (entry.isFile() && entry.name.endsWith('.md')) files.push(path);
  }
  return files.sort();
}

function frontMatter(lines, sourcePath) {
  if (lines[0]?.trim() !== '---') throw new Error(`${sourcePath}: missing YAML front matter`);
  const end = lines.findIndex((line, index) => index > 0 && line.trim() === '---');
  if (end < 0) throw new Error(`${sourcePath}: unterminated YAML front matter`);

  const values = {};
  for (const line of lines.slice(1, end)) {
    const match = line.match(/^\s*([\w-]+)\s*:\s*(.*?)\s*$/);
    if (match) values[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
  const weight = Number(values.weight);
  if (!values.title || !Number.isFinite(weight)) {
    throw new Error(`${sourcePath}: front matter must contain title and numeric weight`);
  }
  return {
    title: values.title,
    weight,
    testEnabled: parseBoolean(values['ws-test'], true),
    endLine: end + 1,
  };
}

function blockMetadata(
  attributes,
  language,
  defaultTimeout,
  context,
  copyActionEnabled = true,
  defaultTestEnabled = true,
  defaultDisabledReason = 'test disabled',
) {
  const testEnabled = parseBoolean(attributes.test, defaultTestEnabled);
  const enabled = copyActionEnabled && testEnabled;
  let reason = '';
  if (!enabled) {
    if (!copyActionEnabled) reason = 'copy action disabled';
    else if (attributes.test !== undefined) reason = 'test disabled';
    else reason = defaultDisabledReason;
  }
  reason = attributes.reason ?? reason;
  const timeoutText = attributes.testTimeout ?? attributes.timeout;
  const timeout = timeoutText === undefined ? defaultTimeout : Number(timeoutText);
  if (enabled && (!Number.isInteger(timeout) || timeout <= 0)) {
    throw new Error(`${context}: timeout must be a positive integer`);
  }
  return {
    enabled,
    language: language || attributes.language || '',
    reason,
    timeout: enabled ? timeout : 0,
    explicitId: attributes.testId ?? attributes.id ?? '',
  };
}

function cleanInstruction(value) {
  return value
    .replace(/\[([^\]]+)]\([^)]*\)/g, '$1')
    .replace(/[*_`]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function visibleHtmlContent(line, commentOpen) {
  let visible = '';
  let cursor = 0;
  let insideComment = commentOpen;

  while (cursor < line.length) {
    if (insideComment) {
      const commentEnd = line.indexOf('-->', cursor);
      if (commentEnd < 0) return { visible, commentOpen: true };
      cursor = commentEnd + 3;
      insideComment = false;
      continue;
    }

    const commentStart = line.indexOf('<!--', cursor);
    if (commentStart < 0) {
      visible += line.slice(cursor);
      break;
    }
    visible += line.slice(cursor, commentStart);
    cursor = commentStart + 4;
    insideComment = true;
  }

  return { visible, commentOpen: insideComment };
}

function currentTabId(containers) {
  for (let index = containers.length - 1; index >= 0; index -= 1) {
    if (containers[index].name === 'tab') return containers[index].id || '';
  }
  return '';
}

function updateContainers(visibleLine, containers) {
  const closingMatch = visibleLine.match(/^(:{3,})\s*$/);
  if (closingMatch) {
    const delimiterLength = closingMatch[1].length;
    const containerIndex = containers.findLastIndex(
      (container) => container.delimiterLength === delimiterLength,
    );
    if (containerIndex >= 0) containers.splice(containerIndex);
    return true;
  }

  const openingMatch = visibleLine.match(/^(:{3,})([A-Za-z][\w-]*)\s*(?:\{(.*)\})?\s*$/);
  if (!openingMatch || openingMatch[2] === 'code') return false;

  const name = openingMatch[2];
  const attributes = parseAttributes(openingMatch[3] ?? '');
  containers.push({
    delimiterLength: openingMatch[1].length,
    name,
    id: name === 'tab' ? attributes.id : '',
  });
  return true;
}

function findStep(lines, openingIndex, lowerBound, section) {
  let proseFallback = '';
  for (let index = openingIndex - 1; index >= lowerBound; index -= 1) {
    const value = lines[index].trim();
    if (!value || /^:{3,}/.test(value) || /^<!--/.test(value)) continue;
    if (/^#{1,6}\s+/.test(value)) break;

    const numbered = value.match(/^(\d+[.)]\s+.+)$/);
    if (numbered) return cleanInstruction(numbered[1]);
    const bullet = value.match(/^([-*]\s+.+)$/);
    if (bullet) return cleanInstruction(bullet[1]);
    if (!proseFallback && value.length <= 240 && /[:.]$/.test(value)) {
      proseFallback = cleanInstruction(value);
    }
  }
  return proseFallback || section;
}

function parsePage(sourcePath, contentRoot, defaultTimeout) {
  const lines = readFileSync(sourcePath, 'utf8').split(/\r?\n/);
  const metadata = frontMatter(lines, sourcePath);
  if (!metadata.testEnabled) {
    return {
      source: relative(contentRoot, sourcePath).split(sep).join('/'),
      title: metadata.title,
      weight: metadata.weight,
      blocks: [],
    };
  }
  const blocks = [];
  let section = metadata.title;
  let sectionLine = metadata.endLine;
  let previousBlockEnd = metadata.endLine;
  let htmlCommentOpen = false;
  const containers = [];

  for (let index = metadata.endLine; index < lines.length; index += 1) {
    const line = lines[index];
    const htmlContent = visibleHtmlContent(line, htmlCommentOpen);
    htmlCommentOpen = htmlContent.commentOpen;
    const visibleLine = htmlContent.visible;

    if (updateContainers(visibleLine, containers)) continue;

    const headingMatch = visibleLine.match(/^#{1,6}\s+(.+?)\s*#*\s*$/);
    if (headingMatch) {
      section = cleanInstruction(headingMatch[1]);
      sectionLine = index;
    }

    const directiveMatch = visibleLine.match(/^(:{3,})code\{(.*)\}\s*$/);
    if (directiveMatch) {
      const delimiter = directiveMatch[1];
      let end = index + 1;
      while (end < lines.length && lines[end].trim() !== delimiter) end += 1;
      if (end >= lines.length) throw new Error(`${sourcePath}:${index + 1}: unterminated code directive`);
      const attributes = parseAttributes(directiveMatch[2]);
      const copyActionEnabled = parseBoolean(attributes.showCopyAction, true);
      const info = blockMetadata(
        attributes,
        attributes.language ?? '',
        defaultTimeout,
        `${sourcePath}:${index + 1}`,
        copyActionEnabled,
      );
      const blockNumber = blocks.length + 1;
      blocks.push({
        ...info,
        tabId: currentTabId(containers),
        id: info.explicitId || `block-${String(blockNumber).padStart(3, '0')}`,
        section,
        step: findStep(lines, index, Math.max(sectionLine + 1, previousBlockEnd + 1), section),
        startLine: index + 2,
        endLine: end,
        code: lines.slice(index + 1, end).join('\n'),
      });
      previousBlockEnd = end;
      index = end;
      continue;
    }

    const fenceMatch = visibleLine.match(/^\s*(`{3,}|~{3,})(.*)$/);
    if (!fenceMatch) continue;
    const opening = fenceMatch[1];
    const marker = opening[0];
    let end = index + 1;
    while (end < lines.length) {
      const closing = lines[end].match(/^\s*(`{3,}|~{3,})\s*$/);
      if (closing && closing[1][0] === marker && closing[1].length >= opening.length) break;
      end += 1;
    }
    if (end >= lines.length) throw new Error(`${sourcePath}:${index + 1}: unterminated code fence`);

    const infoText = fenceMatch[2].trim();
    const firstToken = infoText.match(/^([^\s{]+)/)?.[1] ?? '';
    const language = firstToken.includes('=') ? '' : firstToken;
    const attributes = parseAttributes(infoText);
    const copyActionEnabled = parseBoolean(attributes.showCopyAction, true);
    const info = blockMetadata(
      attributes,
      language,
      defaultTimeout,
      `${sourcePath}:${index + 1}`,
      copyActionEnabled,
      language !== '',
      'informational block without language',
    );
    const blockNumber = blocks.length + 1;
    blocks.push({
      ...info,
      tabId: currentTabId(containers),
      id: info.explicitId || `block-${String(blockNumber).padStart(3, '0')}`,
      section,
      step: findStep(lines, index, Math.max(sectionLine + 1, previousBlockEnd + 1), section),
      startLine: index + 2,
      endLine: end,
      code: lines.slice(index + 1, end).join('\n'),
    });
    previousBlockEnd = end;
    index = end;
  }

  return {
    source: relative(contentRoot, sourcePath).split(sep).join('/'),
    title: metadata.title,
    weight: metadata.weight,
    blocks,
  };
}

function blockDelimiter(page, index, code) {
  const base = `WS_TEST_BLOCK_${String(page.weight).padStart(3, '0')}_${String(index + 1).padStart(3, '0')}`;
  let delimiter = base;
  let suffix = 1;
  while (code.split(/\r?\n/).some((line) => line === delimiter)) {
    delimiter = `${base}_${suffix}`;
    suffix += 1;
  }
  return delimiter;
}

function renderWorkshop(pages, config) {
  const enabledBlockCount = pages
    .flatMap((page) => page.blocks)
    .filter((block) => block.enabled)
    .length;
  let enabledBlockNumber = 0;
  const lines = [
    '#!/usr/bin/env bash',
    '',
    '# Generated by infra/scripts/ws-test/generate.mjs. Do not edit.',
    '',
    'set -Eeuo pipefail',
    'WS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
    'source "${WS_SCRIPT_DIR}/runtime.sh"',
    `ws_begin_run ${shellQuote(config.title)} "\${WS_SCRIPT_DIR}/reports/${config.template}" ${config.delay} "$@"`,
    ...config.environmentFiles.map((path) => `ws_source_environment ${shellQuote(path)}`),
    '',
  ];

  for (const page of pages) {
    lines.push(`ws_begin_page ${shellQuote(page.title)} ${page.weight} ${shellQuote(page.source)}`, '');
    page.blocks.forEach((block, index) => {
      const common = [
        shellQuote(block.id),
        shellQuote(block.section),
        shellQuote(block.step),
        block.startLine,
        block.endLine,
        shellQuote(block.language),
        shellQuote(block.tabId),
      ].join(' ');
      if (!block.enabled) {
        lines.push(`ws_skip_block ${common} ${shellQuote(block.reason)}`, '');
        return;
      }
      enabledBlockNumber += 1;
      const delimiter = blockDelimiter(page, index, block.code);
      lines.push(
        `ws_run_block ${common} ${block.timeout} ${enabledBlockNumber} ${enabledBlockCount} <<'${delimiter}'`,
        block.code,
        delimiter,
        '',
      );
    });
    lines.push('ws_end_page', '');
  }
  lines.push('ws_finish_run', '');
  return lines.join('\n');
}

function readRegistry() {
  if (!existsSync(REGISTRY_PATH)) throw new Error(`Workshop registry not found: ${REGISTRY_PATH}`);
  const registry = JSON.parse(readFileSync(REGISTRY_PATH, 'utf8'));
  const defaults = registry.testDefaults ?? {};
  const workshops = (registry.workshops ?? [])
    .filter((workshop) => workshop.test?.enabled)
    .map((workshop) => {
      const environmentFiles = workshop.test.environmentFiles ?? defaults.environmentFiles ?? [];
      if (environmentFiles.some((path) => !isAbsolute(path))) {
        throw new Error(`${workshop.template}: test environment files must use absolute paths`);
      }
      return {
        template: workshop.template,
        repository: workshop.repository,
        title: workshop.test.title ?? workshop.template,
        contentDirectory: workshop.test.contentDirectory ?? 'content',
        timeout: workshop.test.blockTimeoutSeconds ?? defaults.blockTimeoutSeconds ?? 600,
        delay: workshop.test.delayBetweenBlocksSeconds ?? defaults.delayBetweenBlocksSeconds ?? 5,
        environmentFiles,
      };
    });
  return workshops;
}

function selectWorkshops(workshops, requested) {
  if (requested.length === 0) return workshops;
  const byTemplate = new Map(workshops.map((workshop) => [workshop.template, workshop]));
  return requested.map((template) => {
    const workshop = byTemplate.get(template);
    if (!workshop) throw new Error(`Test generation is not enabled for workshop '${template}'`);
    return workshop;
  });
}

function cleanStaleTemporaryFiles(artifactId) {
  const prefix = `.${artifactId}.sh.tmp-`;
  for (const entry of readdirSync(SCRIPT_DIR, { withFileTypes: true })) {
    if (entry.isFile() && entry.name.startsWith(prefix)) rmSync(join(SCRIPT_DIR, entry.name), { force: true });
  }
}

function cleanMigratedRepositoryArtifacts(config, outputPath) {
  if (config.repository === config.template) return;

  const previousOutputPath = join(SCRIPT_DIR, `${config.repository}.sh`);
  if (previousOutputPath !== outputPath) rmSync(previousOutputPath, { force: true });
  cleanStaleTemporaryFiles(config.repository);

  const previousLegacyDirectory = join(SCRIPT_DIR, config.repository);
  if (existsSync(previousLegacyDirectory)) {
    rmSync(previousLegacyDirectory, { recursive: true, force: true });
  }
}

function generateWorkshop(config) {
  const started = process.hrtime.bigint();
  const repositoryRoot = join(WORKSPACE_ROOT, config.repository);
  const contentRoot = join(repositoryRoot, config.contentDirectory);
  if (!existsSync(contentRoot) || !statSync(contentRoot).isDirectory()) {
    throw new Error(`${config.repository}: content directory not found: ${contentRoot}`);
  }

  const outputPath = join(SCRIPT_DIR, `${config.template}.sh`);
  const temporaryPath = join(SCRIPT_DIR, `.${config.template}.sh.tmp-${process.pid}`);
  cleanStaleTemporaryFiles(config.template);

  try {
    const allPages = listMarkdownFiles(contentRoot).map((path) => parsePage(path, contentRoot, config.timeout));
    const pages = allPages
      .filter((page) => page.blocks.length > 0)
      .sort((left, right) => left.weight - right.weight
        || (left.source < right.source ? -1 : left.source > right.source ? 1 : 0));
    const blocks = pages.flatMap((page) => page.blocks);
    const enabledBlocks = blocks.filter((block) => block.enabled);

    writeFileSync(temporaryPath, renderWorkshop(pages, config), { mode: 0o755 });
    renameSync(temporaryPath, outputPath);

    const legacyDirectory = join(SCRIPT_DIR, config.template);
    if (existsSync(legacyDirectory)) rmSync(legacyDirectory, { recursive: true, force: true });
    cleanMigratedRepositoryArtifacts(config, outputPath);

    const elapsedMilliseconds = Number(process.hrtime.bigint() - started) / 1_000_000;
    console.log(`\n${config.title}`);
    console.log(`  Repository: ../${config.repository}`);
    console.log(`  Markdown pages scanned: ${allPages.length}`);
    console.log(`  Chapters with blocks: ${pages.length}`);
    console.log(`  Code blocks: ${blocks.length}`);
    console.log(`  Enabled blocks: ${enabledBlocks.length}`);
    console.log(`  Non-executable blocks: ${blocks.length - enabledBlocks.length}`);
    console.log(`  Script: ${outputPath}`);
    console.log(`  Full regeneration: ${elapsedMilliseconds.toFixed(0)} ms`);
  } finally {
    rmSync(temporaryPath, { force: true });
  }
}

try {
  const workshops = selectWorkshops(readRegistry(), process.argv.slice(2));
  if (workshops.length === 0) throw new Error('No workshops have test generation enabled');
  for (const workshop of workshops) generateWorkshop(workshop);
} catch (error) {
  console.error(`ws-test generation failed: ${error.message}`);
  process.exitCode = 1;
}
