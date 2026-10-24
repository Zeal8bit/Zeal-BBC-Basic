// Use jsbeeb's published, supported headless API; do not patch its emulator.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [packageRoot, sourcePath] = process.argv.slice(2);
const { MachineSession } = await import(pathToFileURL(path.join(packageRoot, "src/index.js")));
const version = JSON.parse(readFileSync(path.join(packageRoot, "package.json"))).version;
const hash = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");
// Correct only the printed comma omission. Keep MODE 5, the flight logic,
// original BBC keyboard flushing and graphics. The reference file is unchanged.
const original = readFileSync(sourcePath, "utf8");
assert.equal(original.split("VDU10 9,127").length, 2);
const source = original.replace("VDU10 9,127", "VDU10,9,127");
const runs = [];
for (let trial = 0; trial < 3; trial++) {
    const machine = new MachineSession("B-DFS1.2", { cpuMultiplier: 1, tube: false });
    await machine.initialise();
    await machine.boot();
    await machine.loadBasic(source);
    const bp = machine.addBreakpoint("execute", 0xfff4); // MOS OSBYTE
    await machine.type("RUN");
    const timestamps = [];
    const deadline = machine.elapsedCycles + 120 * 2_000_000;
    while (timestamps.length < 111 && machine.elapsedCycles < deadline) {
        await machine.runFor(2_000_000);
        const r = machine.registers();
        // The original game calls INKEY$(0) once per main loop. *FX calls
        // also reach OSBYTE, but have a different A and are not counted.
        if (r.pc === 0xfff4 && r.a === 129 && r.x === 0 && r.y === 0) {
            timestamps.push(machine.elapsedCycles);
        }
    }
    machine.removeBreakpoint(bp);
    assert.equal(timestamps.length, 111, "Game failed to complete the benchmark sample");
    const output = machine.drainOutput();
    assert(output.elements.some((element) => element.mode === 5), "Expected BBC MODE 5");
    assert(output.screenText.includes("burn?"), "Game dashboard did not render");
    const cycles = timestamps[110] - timestamps[10];
    const seconds = cycles / 2_000_000;
    runs.push({ cycles, seconds, updates_per_second: 100 / seconds });
}
console.log("BENCHMARK_JSON:" + JSON.stringify({
    emulator: "jsbeeb", version, model: "B-DFS1.2", cpu_hz: 2_000_000,
    basic_mode: 5, real_video: true, cpu_multiplier: 1, tube: false,
    source_sha256: hash(sourcePath),
    rom_sha256: {
        os: hash(path.join(packageRoot, "public/roms/os.rom")),
        basic: hash(path.join(packageRoot, "public/roms/BASIC.ROM")),
        dfs: hash(path.join(packageRoot, "public/roms/b/DFS-1.2.rom")),
    },
    runs,
}));
