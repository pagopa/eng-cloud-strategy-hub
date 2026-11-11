import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const original = readFileSync(new URL('./c-tabella.html', import.meta.url), 'utf8');
const atlas = () => readFileSync(new URL('./d-atlante.html', import.meta.url), 'utf8');
const matches = (html, pattern) => [...html.matchAll(pattern)].map(match => match[0]);
const withoutComparison = html => html.replace(
  /<div class="ba" data-part="before-after">[\s\S]*?<\/div><\/dd><\/div>/g,
  '<!-- before/after comparison -->',
);

test('preserves report content outside the revised before/after comparison', () => {
  const html = atlas();
  for (const article of matches(original, /<article\b[^>]*>[\s\S]*?<\/article>/g)) {
    assert.ok(withoutComparison(html).includes(withoutComparison(article)), 'A report article was changed or omitted');
  }
  for (const section of ['summary', 'evidence']) {
    const pattern = new RegExp(`<section data-section="${section}"[\\s\\S]*?<\\/section>`);
    const content = original.match(pattern)?.[0];
    assert.ok(content && html.includes(content), `${section} must remain unchanged`);
  }
  assert.deepEqual(
    matches(html, /data-section="[^"]+"/g),
    matches(original, /data-section="[^"]+"/g),
  );
});

test('adds intervention phase headings without changing actions or their links', () => {
  const actionList = html => html.match(/<ol class="actions">([\s\S]*?)<\/ol>/)?.[1];
  const revised = actionList(atlas());
  const phases = [...revised.matchAll(/<strong class="action-phase">([^<]+)<\/strong>/g)]
    .map(([, phase]) => phase);
  assert.deepEqual(phases, ['Prima del rilascio', 'Decisioni sui default', 'Release separata']);
  const withoutPhases = revised
    .replace(/<strong class="action-phase">[^<]+<\/strong>/g, '')
    .replace(/<span class="action-copy">([\s\S]*?)<\/span>/g, '$1');
  assert.equal(withoutPhases, actionList(original));
});

test('aligns the comparison stages and preserves the consumer in both diagrams', () => {
  const html = atlas();
  const figures = ['before', 'after'].map(side =>
    html.match(new RegExp(`<figure data-diagram data-side="${side}">([\\s\\S]*?)<\\/figure>`))?.[1],
  );
  const stages = figures.map(figure => [...figure.matchAll(
    /<text x="([^"]+)" y="([^"]+)" text-anchor="middle">([^<]+)<\/text>/g,
  )].map(([, x, y, label]) => ({ x: Number(x), y: Number(y), label })));
  assert.deepEqual(stages[0].slice(0, 2).map(node => node.label), ['Consumer', 'Modulo']);
  assert.deepEqual(stages[1].slice(0, 3).map(node => node.label), ['Consumer', 'Modulo', 'Bucket']);
  assert.deepEqual(
    stages[0].slice(0, 3).map(({ x, y }) => ({ x, y })),
    stages[1].slice(0, 3).map(({ x, y }) => ({ x, y })),
  );
  assert.equal(stages[1][3].label, 'Policy comune');
  assert.ok(stages[1][3].y > stages[1][2].y, 'Separate the shared policy from the bucket');
  assert.equal(
    figures[0].match(/viewBox="([^"]+)"/)[1],
    figures[1].match(/viewBox="([^"]+)"/)[1],
  );
  assert.match(figures[1], /C\[Consumer\] --&gt; M\[Modulo\] --&gt; B\[Bucket\] --&gt; P\[Policy comune\]/);
  for (const figure of figures) {
    const description = figure.match(/aria-label="([^"]+)"/)[1];
    assert.ok(figure.includes(`accDescr: ${description}`), 'Keep accessible and Mermaid descriptions aligned');
  }
});

test('keeps all actions and evidence states in the scan-friendly finding register', () => {
  const html = atlas();
  assert.match(html, /<ol class="register"/);
  const originalRows = [...original.matchAll(/<tr data-row="([^"]+)">([\s\S]*?)<\/tr>/g)];
  const registerRows = [...html.matchAll(/<li data-row="([^"]+)">([\s\S]*?)<\/li>/g)];
  assert.equal(registerRows.length, originalRows.length);
  for (const [index, [, severity, row]] of originalRows.entries()) {
    const [, newSeverity, newRow] = registerRows[index];
    assert.equal(newSeverity, severity);
    for (const pattern of [
      /<a href="#[^"]+">[\s\S]*?<\/a>/,
      /data-part="action">([^<]+)</,
      /<span class="ev [^"]+">[^<]+<\/span>/,
      /<use href="#sev-[^"]+"\/>/,
    ]) {
      const content = row.match(pattern);
      assert.ok(content && newRow.includes(content[1] ?? content[0]));
    }
    assert.ok(newRow.includes(row.match(/class="id hide-m">([^<]+)/)[1]));
  }
});

test('distinguishes the findings list from finding details in navigation', () => {
  const nav = atlas().match(/<nav class="toc rail"[\s\S]*?<\/nav>/)?.[0];
  assert.ok(nav, 'Missing report navigation');
  assert.match(nav, /<a href="#elenco"><span[^>]*>02<\/span>Lista criticità<\/a>/);
  assert.match(nav, /<a href="#criticita"><span[^>]*>04<\/span>Dettaglio criticità<\/a>/);
});

test('links each finding type to its first detail and shows its total', () => {
  const html = atlas();
  const submenu = html.match(/<ul class="rail-types" aria-label="Tipologie di criticità">([\s\S]*?)<\/ul>/)?.[1];
  assert.ok(submenu, 'Missing finding-type submenu');
  const links = matches(submenu, /<a\b[^>]*>[\s\S]*?<\/a>/g);
  assert.equal(links.length, 3);
  for (const [index, [severity, label]] of [
    ['blocker', 'Bloccanti'],
    ['important', 'Importanti'],
    ['improvement', 'Miglioramenti'],
  ].entries()) {
    const findings = [...html.matchAll(/<article\b[^>]*data-finding\b[^>]*>/g)]
      .map(([tag]) => tag)
      .filter(tag => tag.includes(`data-severity="${severity}"`));
    const firstId = findings[0].match(/\bid="([^"]+)"/)[1];
    assert.ok(links[index].includes(`href="#${firstId}"`));
    assert.ok(links[index].includes(`<span>${label}</span>`));
    assert.ok(links[index].includes(`<span class="n">${findings.length}</span>`));
    assert.ok(links[index].includes(`<use href="#sev-${severity}"/>`));
  }
  assert.doesNotMatch(submenu, /data-filter|<button/);
});

test('preserves baseline behavior with same-target submenu reveal, anchors, and identifiers', () => {
  const html = atlas();
  const script = html.match(/<script data-invariant="script">[\s\S]*?<\/script>/)?.[0];
  const submenuReveal = "$('.rail-types a').forEach(a=>a.addEventListener('click',()=>{if(a.hash===location.hash)reveal()}));\n";
  assert.ok(script.includes(submenuReveal), 'Reveal a filtered submenu target even when its hash is unchanged');
  assert.equal(
    script.replace(submenuReveal, ''),
    original.match(/<script data-invariant="script">[\s\S]*?<\/script>/)?.[0],
  );
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(ids.length, new Set(ids).size, 'Duplicate identifiers');
  for (const [, id] of html.matchAll(/href="#([^"]+)"/g)) {
    assert.ok(ids.includes(id), `Missing anchor: ${id}`);
  }
  assert.match(html, /class="toc rail"/);
  assert.match(html, /<div class="shell">[\s\S]*?<nav[\s\S]*?<div class="wrap">/);
  assert.doesNotMatch(html, /<(?:script|link)[^>]+(?:src|href)="https?:/);
});
