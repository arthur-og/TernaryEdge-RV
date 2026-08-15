import { readFile } from "node:fs/promises";
import test from "node:test";
import assert from "node:assert/strict";

const root = new URL("../", import.meta.url);
const html = await readFile(new URL("index.html", root), "utf8");
const appendix = await readFile(new URL("fluxo_npu_v2_prof_ramon.md", root), "utf8");

test("deck has nine uniquely titled slides", () => {
  const titles = [...html.matchAll(/<section\s+class="slide[^>]*data-title="([^"]+)"/g)]
    .map((match) => match[1]);
  assert.equal(titles.length, 9);
  assert.equal(new Set(titles).size, titles.length);
  assert.match(html, /data-total="9"/);
});

test("evidence map keeps all stages and legend", () => {
  assert.equal((html.match(/class="flow-node"/g) ?? []).length, 5);
  assert.match(html, /ATUAL NO CÓDIGO/);
  assert.match(html, /DOCUMENTADO/);
  assert.match(html, /PROPOSTO/);
  assert.match(html, /NÃO VERIFICADO/);
  assert.match(html, /A fronteira ainda aberta/);
});

test("data representation slide keeps the contract", () => {
  assert.match(html, /Cada <code>uint32_t<\/code> carrega 16 pesos/);
  assert.match(html, /49 words\/neurônio/);
  assert.match(html, /64 words\/neurônio/);
  assert.match(html, /32 words\/neurônio/);
  assert.match(html, /unidade de <code>dma_size<\/code>/);
});

test("validation status distinguishes C++ from RTL and FPGA", () => {
  assert.match(html, /21\/21/);
  assert.match(html, /runtime RTL Verilog/);
  assert.match(html, /contrato HAL \+ weights/);
  assert.match(html, /FPGA \+ benchmark/);
  assert.match(appendix, /Runtime\/testbench RTL Verilog/);
  assert.match(appendix, /C\+\+ golden model v2/);
});

test("presenter ends with a blank next preview and accepts parent sync", () => {
  assert.match(html, /next\.src='about:blank'/);
  assert.match(html, /window\.addEventListener\('message'/);
  assert.match(html, /e\.source===window\.opener/);
});

test("removed stale blocker claims do not return", () => {
  for (const stale of ["29/29", "BLOCKER ATUAL", "Loader não fecha", "wt_buf_idx é declarado como reg [1:0]"]) {
    assert.doesNotMatch(html, new RegExp(stale.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    assert.doesNotMatch(appendix, new RegExp(stale.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
});
