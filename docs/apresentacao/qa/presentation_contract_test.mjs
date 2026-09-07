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
  const slide = html.match(/<section class="slide" data-title="Como os dados são representados">([\s\S]*?)<\/section>/)?.[1];
  assert.ok(slide);
  assert.equal((slide.match(/class="metric"/g) ?? []).length, 3);
  for (const value of ["49", "64", "32"]) {
    assert.match(slide, new RegExp(`<div class="value">${value}<\\/div>`));
  }
  assert.match(slide, /784 → 1024/);
  assert.match(slide, /1024 → 512/);
  assert.match(slide, /512 → 256/);
  assert.match(slide, /words\/neurônio/);
  assert.match(slide, /64 PEs.*árvore.*INT32/s);
  assert.match(slide, /bias\/scale/);
});

test("requested technical narrative is visible", () => {
  assert.match(html, /MNIST/);
  assert.match(html, /w ∈ \{-1, 0, \+1\}/);
  assert.match(html, /64 PEs/);
  assert.match(html, /adder tree/);
  assert.match(html, /acumulador INT32/);
  assert.match(html, /CPU.*MMIO|MMIO.*CPU/);
  assert.match(html, /Wishbone/);
  assert.match(html, /DMA/);
  assert.match(html, /RAM/);
  assert.match(html, /IRQ/);
  assert.match(html, /START/);
  assert.match(html, /ping-pong/);
  assert.match(html, /bias/i);
  assert.match(html, /signed-scale/);
  assert.match(html, /round\/shift/);
  assert.match(html, /saturate/);
});

test("operational transition has no fixed completion deadline", () => {
  assert.match(html, /Gilvan saiu da operação diária/);
  assert.match(html, /Gildo assumiu/);
  assert.match(html, /Gustavo.*continuidade/);
  assert.match(html, /quarto autor/);
  assert.doesNotMatch(html, /31\/08\/2026/);
  assert.match(appendix, /Gilvan saiu da operação diária/);
  assert.match(appendix, /Gildo assumiu/);
  assert.doesNotMatch(appendix, /31\/08\/2026/);
});

test("validation status distinguishes C++ from RTL and FPGA", () => {
  assert.match(html, /Icarus.*testes RTL focados/);
  assert.match(html, /16\/32\/64/);
  assert.match(html, /Verilator.*lint matrix/);
  assert.match(html, /14\/14/);
  assert.match(html, /C\+\+ v2 21\/21.*histórico;.*prova canônica/);
  assert.match(appendix, /Icarus RTL focado.*PASS/);
  assert.match(appendix, /Matriz top-level.*16, 32 e 64 PEs/);
  assert.match(appendix, /Verilator lint matrix.*PASS/);
  assert.match(appendix, /Report gate unit tests.*14\/14/);
  assert.match(appendix, /C\+\+ golden model v2.*HISTÓRICO\/SECUNDÁRIO/);
});

test("current RTL integration and MMIO contract are visible", () => {
  for (const source of [html, appendix]) {
    assert.match(source, /64 PEs/);
    assert.match(source, /árvore registrada/);
    assert.match(source, /acumulador (?:escalar )?INT32/);
    assert.match(source, /buffers? (?:de ativação )?bancados/);
    assert.match(source, /seis estágios/);
    assert.match(source, /até oito descritores/);
    assert.match(source, /0x80000000/);
    assert.match(source, /0x40000000/);
    assert.match(source, /IRQ 10/);
    assert.match(source, /17 registradores/);
    assert.match(source, /0x40/);
  }
  for (const offset of ["0x00", "0x04", "0x08", "0x0c", "0x10", "0x14", "0x18", "0x1c", "0x20", "0x24", "0x28", "0x2c", "0x30", "0x34", "0x38", "0x3c", "0x40"]) {
    assert.match(appendix, new RegExp(offset.replace(".", "\\.")));
  }
  assert.match(html, /layer \[15:8\] \+ busy\/IRQ\/done\/error/);
  assert.match(appendix, /camada em bits `\[15:8\]`/);
});

test("DMA protocol and handoff evidence are current", () => {
  for (const source of [html, appendix]) {
    assert.match(source, /não é burst/);
    assert.match(source, /beat (?:único|único Wishbone|Wishbone Classic)/);
    assert.match(source, /CTI=000/);
    assert.match(source, /BTE=00/);
    assert.match(source, /ERR/);
    assert.match(source, /256 ciclos/);
  }
  assert.match(html, /Vivado.*report gate passaram|Vivado.*fecha 100 MHz/);
  assert.match(html, /report gate/);
  assert.match(appendix, /Vivado atual passou.*100 MHz/);
  assert.match(appendix, /python3 hardware\/litex_soc\/check_vivado_reports\.py/);
  assert.match(html, /\+0\.065 ns/);
  assert.match(html, /0\.000 ns/);
  assert.match(appendix, /\+0\.065 ns/);
  assert.match(appendix, /TNS 0/);
});

test("physical evidence stays pending", () => {
  for (const source of [html, appendix]) {
    assert.match(source, /bitstream/);
    assert.match(source, /boot Linux/);
    assert.match(source, /IRQ\/DMA/);
    assert.match(source, /inferência.*end-to-end|inferência.*ponta a ponta/);
    assert.match(source, /desempenho/);
    assert.match(source, /potência/);
    assert.match(source, /energia/);
    assert.match(source, /PENDENTE|pendentes|PENDENTES/);
  }
});

test("presenter ends with a blank next preview and accepts parent sync", () => {
  assert.match(html, /next\.src='about:blank'/);
  assert.match(html, /window\.addEventListener\('message'/);
  assert.match(html, /e\.source===window\.opener/);
});

test("removed stale blocker claims do not return", () => {
  for (const stale of [
    "29/29",
    "BLOCKER ATUAL",
    "Loader não fecha",
    "wt_buf_idx é declarado como reg [1:0]",
    "11 estados nomeados",
    "Runtime/testbench RTL Verilog",
    "runtime Verilog ainda não foi executado",
    "O mapa atual cobre `0x00` até `0x2c`",
    "DMA_SIZE",
    "WEIGHT_CFG",
    "ACT_CFG",
    "LAYER_CTRL",
  ]) {
    assert.doesNotMatch(html, new RegExp(stale.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    assert.doesNotMatch(appendix, new RegExp(stale.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
});
