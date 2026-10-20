/* Run real assembled routines; model only Zeal syscalls and flat user RAM.
 * CPU implementation is supplied by an unmodified Zeal-NativeEmulator checkout.
 */
#include "hw/z80.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static z80 cpu;
static device_t ram;
static uint8_t memory[65536], image[65536], file[65536];
static const char *map_path;
static uint32_t file_size, file_pos;
static int fail_call, failure, close_failure, short_limit, opened, closed, transfers;
static int fail_transfer, premature_eof;
static int basic_error, invalid_buffer;
static unsigned last_flags;
static char opened_name[256];
static unsigned checks;
static unsigned stop_pc;
static int follow_basic_error;
static uint8_t keys[128];
static unsigned key_size, key_pos, keyboard_mode;
static int inject_interrupt, interrupt_seen, escape_after_reads, input_reads;
static int partial_release;

static uint8_t read_ram(device_t *dev, uint32_t address) { (void)dev; return memory[address & 65535]; }
static void write_ram(device_t *dev, uint32_t address, uint8_t value) { (void)dev; memory[address & 65535] = value; }
int mmu_init(mmu_t *mmu) {
    memset(mmu, 0, sizeof(*mmu));
    for (int i = 0; i < 4; ++i) { mmu->pages[i] = i; mmu->vpages[i].dev = &ram; }
    return 0;
}
void vtimer_tick(uint64_t elapsed) { (void)elapsed; }
uint64_t vtimer_stall_bus(uint64_t maximum, const bool *requested) { (void)requested; return maximum; }

static uint16_t symbol(const char *name) {
    FILE *fp = fopen(map_path, "r"); assert(fp);
    char line[512], found[128]; unsigned address;
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "%127s = $%x", found, &address) == 2 && !strcmp(name, found)) {
            fclose(fp); return address;
        }
    }
    fprintf(stderr, "Missing symbol: %s\n", name); exit(1);
}
static void set_bc(unsigned v) { cpu.b = v >> 8; cpu.c = v; }
static void set_de(unsigned v) { cpu.d = v >> 8; cpu.e = v; }
static void set_hl(unsigned v) { cpu.h = v >> 8; cpu.l = v; }
static void return_to_caller(void) {
    cpu.pc = memory[cpu.sp] | memory[(uint16_t)(cpu.sp + 1)] << 8; cpu.sp += 2;
}
static void reset(const char *entry) {
    memcpy(memory, image, sizeof(memory)); z80_init(&cpu);
    cpu.pc = symbol(entry); cpu.sp = 0xf700;
    memory[cpu.sp] = 0; memory[cpu.sp + 1] = 0x30;
    fail_call = -1; failure = 19; close_failure = 0; short_limit = -1;
    opened = closed = transfers = basic_error = invalid_buffer = 0;
    fail_transfer = premature_eof = 0;
    file_pos = 0; file_size = 16; opened_name[0] = 0;
    stop_pc = 0;
    follow_basic_error = 0;
    key_size = key_pos = keyboard_mode = 0;
    inject_interrupt = interrupt_seen = escape_after_reads = input_reads = 0;
    partial_release = 0;
    for (unsigned i = 0; i < sizeof(file); ++i) file[i] = (uint8_t)(i * 17 + 3);
    strcpy((char *)memory + 0x7c00, "test.bbc");
    set_hl(0x7c00); set_de(0x8000); set_bc(16);
}
static void syscall(void) {
    unsigned call = cpu.l, address = cpu.d << 8 | cpu.e, count = cpu.b << 8 | cpu.c;
    cpu.a = 0;
    if ((int)call == fail_call) { cpu.a = call == 2 ? (uint8_t)-failure : failure; }
    else switch (call) {
    case 2:
        opened++; last_flags = cpu.h;
        for (unsigned i = 0; i < sizeof(opened_name) - 1; ++i) {
            opened_name[i] = memory[(uint16_t)(count + i)];
            if (!opened_name[i]) break;
        }
        if (last_flags & 4) file_size = 0;
        cpu.a = 2; break;
    case 3: closed++; cpu.a = close_failure; break;
    case 4:
        memset(memory + address, 0, 29); memory[address] = 1;
        for (int i = 0; i < 4; ++i) memory[address + 1 + i] = file_size >> (8 * i);
        break;
    case 0: case 1:
        if (call == 0 && cpu.h == 1) {
            input_reads++;
            if (escape_after_reads && input_reads == escape_after_reads) {
                keys[key_size++] = 0xf0;
            }
            if (count > key_size - key_pos) count = key_size - key_pos;
            /* A raw read may never end with a release marker. */
            if (!partial_release && count && keys[key_pos + count - 1] == 0xfe) count--;
            memcpy(memory + address, keys + key_pos, count); key_pos += count;
            set_bc(count); break;
        }
        if (call == 1 && cpu.h == 0) break;
        transfers++;
        if (transfers == fail_transfer) { cpu.a = failure; break; }
        if (count > 0x4000 || (address & 0x3fff) + count > 0x4000) {
            invalid_buffer++; cpu.a = 6; break;
        }
        if (short_limit >= 0 && count > (unsigned)short_limit) count = short_limit;
        if (call == 0 && premature_eof) count = 0;
        if (call == 0) {
            if (count > file_size - file_pos) count = file_size - file_pos;
            memcpy(memory + address, file + file_pos, count);
        } else {
            assert(file_pos + count <= sizeof(file));
            memcpy(file + file_pos, memory + address, count);
            if (file_pos + count > file_size) file_size = file_pos + count;
        }
        file_pos += count; set_bc(count); break;
    case 6: set_bc(0); set_de(file_pos); break;
    case 7: keyboard_mode = cpu.e; break;
    default: fprintf(stderr, "Unexpected syscall: %u\n", call); exit(1);
    }
    /* Zeal returns status in A. Deliberately do not promise meaningful flags. */
    cpu.zf = false; cpu.cf = true;
    return_to_caller();
}
static void run(void) {
    unsigned error_entry = symbol("EXTERR");
    for (unsigned step = 0; step < 2000000; ++step) {
        if (cpu.pc == 0x3000 || (stop_pc && cpu.pc == stop_pc)) return;
        if (cpu.pc == error_entry && !follow_basic_error) { basic_error = cpu.a; return; }
        if (inject_interrupt && cpu.iff1) {
            inject_interrupt = 0; z80_gen_int(&cpu, 0xff);
        }
        if (cpu.pc == 0x2000) interrupt_seen++;
        if (cpu.pc == 8) syscall(); else z80_step(&cpu);
    }
    fprintf(stderr, "Instruction limit at %04x\n", cpu.pc); exit(1);
}
#define CHECK(condition) do { checks++; if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); } } while (0)

static void test_errors(void) {
    const char *entries[] = {"OSLOAD", "OSSAVE", "OSBGET", "OSBPUT", "OSSHUT", "GETEXT", "GETPTR", "PUTPTR"};
    const int calls[] = {2, 2, 0, 1, 3, 4, 6, 6};
    for (unsigned i = 0; i < sizeof(calls) / sizeof(*calls); ++i) {
        reset(entries[i]); cpu.e = 2; cpu.a = 2; fail_call = calls[i]; run();
        CHECK(basic_error == (128 | failure));
    }
    reset("OSLOAD"); fail_call = 0; close_failure = 6; run();
    CHECK(basic_error == (128 | 19)); CHECK(closed == 1);
    reset("OSSAVE"); fail_call = 1; run();
    CHECK(basic_error == (128 | 19)); CHECK(closed == 1);
    reset("OSSAVE"); close_failure = 6; run(); CHECK(basic_error == (128 | 6));
    reset("OSSAVE"); short_limit = 0; run(); CHECK(basic_error == (128 | 1)); CHECK(closed == 1);
    reset("OSBPUT"); cpu.e = 2; short_limit = 0; run(); CHECK(basic_error == (128 | 1));
}
static void test_loads(void) {
    const unsigned lengths[] = {0, 1, 8191, 8192, 8193, 13914, 16384, 16385, 28000};
    for (unsigned i = 0; i < sizeof(lengths) / sizeof(*lengths); ++i) {
        reset("OSLOAD"); file_size = lengths[i]; set_bc(0x7000); run();
        CHECK(!basic_error); CHECK(cpu.cf); CHECK(closed == 1);
        CHECK(file_pos == file_size); CHECK(!invalid_buffer);
        CHECK(!memcmp(memory + 0x8000, file, file_size));
    }
    reset("OSLOAD"); file_size = 17; memory[0x8000] = 0xaa; run();
    CHECK(!cpu.cf); CHECK(!basic_error); CHECK(transfers == 0);
    CHECK(memory[0x8000] == 0xaa); CHECK(closed == 1);
    reset("OSLOAD"); file_size = 65536; set_bc(0x7000); run();
    CHECK(!cpu.cf); CHECK(!basic_error); CHECK(transfers == 0); CHECK(closed == 1);
    reset("OSLOAD"); file_size = 10000; set_de(0xbffd); set_bc(10000); short_limit = 257; run();
    CHECK(!basic_error); CHECK(cpu.cf); CHECK(!invalid_buffer);
    CHECK(!memcmp(memory + 0xbffd, file, file_size));
    reset("OSLOAD"); fail_call = 4; run();
    CHECK(basic_error == (128 | 19)); CHECK(closed == 1); CHECK(transfers == 0);
    reset("OSLOAD"); premature_eof = 1; run();
    CHECK(basic_error == (128 | 1)); CHECK(closed == 1);
    reset("OSLOAD"); file_size = 17000; set_bc(20000); fail_transfer = 2; run();
    CHECK(basic_error == (128 | 19)); CHECK(closed == 1);
}
static void test_saves(void) {
    const unsigned lengths[] = {0, 1, 16383, 16384, 16385, 28000};
    for (unsigned i = 0; i < sizeof(lengths) / sizeof(*lengths); ++i) {
        reset("OSSAVE"); unsigned length = lengths[i]; set_bc(length);
        for (unsigned j = 0; j < length; ++j) memory[0x8000 + j] = (uint8_t)(j * 7);
        run();
        CHECK(!basic_error); CHECK(!invalid_buffer); CHECK(closed == 1);
        CHECK(file_size == length); CHECK(!memcmp(file, memory + 0x8000, length));
    }
    reset("OSSAVE"); set_de(0xbffd); set_bc(10000); short_limit = 257; run();
    CHECK(!basic_error); CHECK(!invalid_buffer); CHECK(closed == 1);
    CHECK(file_size == 10000); CHECK(!memcmp(file, memory + 0xbffd, 10000));
    reset("OSSAVE"); set_bc(17000); fail_transfer = 2; close_failure = 6; run();
    CHECK(basic_error == (128 | 19)); CHECK(closed == 1);
}
static void test_chain_names(void) {
    const char *entries[] = {"CHAIN", "RUN"};
    for (unsigned i = 0; i < 2; ++i) {
        reset(entries[i]);
        unsigned accs = symbol("ACCS"), himem = symbol("HIMEM"), page = symbol("PAGE");
        memset(memory + accs, 'X', 256);
        strcpy((char *)memory + 0x7d00, "\"test.bbc\"\n"); cpu.iy = 0x7d00;
        memory[himem] = 0; memory[himem + 1] = 0xf7;
        memory[page] = 0; memory[page + 1] = 0x80;
        file_size = 3; file[0] = 0; file[1] = file[2] = 0xff;
        stop_pc = symbol("RUN0"); run();
        CHECK(!basic_error); CHECK(!strcmp(opened_name, "test.bbc"));
        CHECK(opened == 1); CHECK(closed == 1); CHECK(file_pos == 3);
        CHECK(cpu.pc == stop_pc);
    }
}
static void test_bundled_loads(void) {
    const char *paths[] = {"examples/hello.bbc", "examples/crystal.bbc", "examples/neptune2.bbc"};
    for (unsigned i = 0; i < 3; ++i) {
        reset("CHAIN"); FILE *fp = fopen(paths[i], "rb"); assert(fp);
        file_size = fread(file, 1, sizeof(file), fp); fclose(fp);
        unsigned page = symbol("PAGE"), himem = symbol("HIMEM");
        memory[page] = 0; memory[page + 1] = 0x80;
        memory[himem] = 0; memory[himem + 1] = 0xf7;
        snprintf((char *)memory + 0x7d00, 128, "\"%s\"\n", paths[i]); cpu.iy = 0x7d00;
        stop_pc = symbol("RUN0"); run();
        CHECK(!basic_error); CHECK(cpu.pc == stop_pc);
        CHECK(!strcmp(opened_name, paths[i])); CHECK(file_pos == file_size);
        CHECK(!memcmp(memory + 0x8000, file, file_size));
    }
}
static void prepare_keyboard(void) {
    memory[symbol("RAW_INPUT")] = 1;
    cpu.a_ = 0x12; cpu.f_ = 0x34; cpu.b_ = 0x56; cpu.c_ = 0x78;
    cpu.d_ = 0x9a; cpu.e_ = 0xbc; cpu.h_ = 0xde; cpu.l_ = 0xf0;
    /* An allowed OS ISR deliberately destroys the entire alternate bank. */
    const uint8_t isr[] = {0xd9, 0x01, 0xaa, 0xbb, 0x11, 0xcc, 0xdd,
                          0x21, 0xee, 0xff, 0xd9, 0x08, 0x3e, 0x55,
                          0xb7, 0x08, 0xfb, 0xed, 0x4d};
    memcpy(memory + 0x2000, isr, sizeof(isr));
    memory[0x38] = 0xc3; memory[0x39] = 0; memory[0x3a] = 0x20;
    cpu.interrupt_mode = 1; inject_interrupt = 1;
}
static void check_alternates(void) {
    CHECK(interrupt_seen == 1); CHECK(!cpu.iff1);
    CHECK(cpu.a_ == 0x12 && cpu.f_ == 0x34);
    CHECK(cpu.b_ == 0x56 && cpu.c_ == 0x78);
    CHECK(cpu.d_ == 0x9a && cpu.e_ == 0xbc);
    CHECK(cpu.h_ == 0xde && cpu.l_ == 0xf0);
}
static void invoke(const char *entry) {
    cpu.pc = symbol(entry); cpu.sp = 0xf700;
    memory[cpu.sp] = 0; memory[cpu.sp + 1] = 0x30;
    run();
}
static void test_escape(void) {
    reset("LTRAP"); prepare_keyboard(); run();
    CHECK(!basic_error); check_alternates();
    reset("LTRAP"); prepare_keyboard(); keys[0] = 0xf0; key_size = 1;
    stop_pc = symbol("ESCAPE"); run();
    CHECK(cpu.pc == stop_pc); check_alternates();
    reset("LTRAP"); prepare_keyboard(); keys[0] = 0xfe; keys[1] = 0xf0; key_size = 2;
    stop_pc = symbol("ESCAPE"); run();
    CHECK(cpu.pc == 0x3000); CHECK(!memory[symbol("ESC_PENDING")]);
    reset("LTRAP"); prepare_keyboard(); partial_release = 1;
    keys[0] = 'a'; keys[1] = 0xfe; key_size = 2; run();
    CHECK(cpu.pc == 0x3000); CHECK(memory[symbol("KEY_COUNT")] == 1);
    keys[key_size++] = 0xf0; stop_pc = symbol("ESCAPE"); invoke("LTRAP");
    CHECK(cpu.pc == stop_pc);
    reset("TRAP"); prepare_keyboard(); keys[0] = 0xf0; key_size = 1;
    stop_pc = symbol("ESCAPE");
    for (int i = 0; i < 19; ++i) { invoke("TRAP"); CHECK(cpu.pc == 0x3000); }
    CHECK(input_reads == 0); invoke("TRAP"); CHECK(cpu.pc == stop_pc);
    reset("LTRAP"); prepare_keyboard(); keys[0] = 'a'; keys[1] = 'b'; keys[2] = 0xf0; key_size = 3;
    stop_pc = symbol("ESCAPE"); run(); CHECK(cpu.pc == 0x3000);
    invoke("LTRAP"); CHECK(cpu.pc == stop_pc);
    reset("LTRAP"); prepare_keyboard(); keys[0] = 'a'; keys[1] = 'b'; key_size = 2; run();
    invoke("OSRDCH"); CHECK(cpu.a == 'a'); invoke("OSRDCH"); CHECK(cpu.a == 'b');
    reset("OSRDCH"); prepare_keyboard(); keys[0] = 0xf0; key_size = 1;
    stop_pc = symbol("ESCAPE"); run(); CHECK(cpu.pc == stop_pc); check_alternates();
    reset("LTRAP"); prepare_keyboard();
    memset(keys, 'x', 32); keys[32] = 0xf0; key_size = 33;
    stop_pc = symbol("ESCAPE");
    for (int i = 0; i < 17; ++i) invoke("LTRAP");
    CHECK(cpu.pc == stop_pc); CHECK(memory[symbol("KEY_COUNT")] == 16);
    invoke("RESET"); CHECK(!memory[symbol("ESC_PENDING")]); CHECK(!memory[symbol("KEY_COUNT")]);
    reset("OSLINE"); prepare_keyboard(); keys[0] = '\n'; key_size = 1; run();
    CHECK(keyboard_mode == 4); check_alternates();
    /* Real BASIC GOTO loop must reach Escape without calling GET/INPUT. */
    reset("RUN0"); prepare_keyboard();
    unsigned page = symbol("PAGE"), himem = symbol("HIMEM");
    memory[page] = 0; memory[page + 1] = 0x80;
    memory[himem] = 0; memory[himem + 1] = 0xf7;
    const uint8_t loop[] = {9, 10, 0, 0xe5, 0x8d, 0x54, 0x4a, 0x40, 10, 0, 0xff, 0xff};
    memcpy(memory + 0x8000, loop, sizeof(loop));
    unsigned top = symbol("TOP"); memory[top] = 12; memory[top + 1] = 0x80;
    escape_after_reads = 3; stop_pc = symbol("ESCAPE"); run();
    CHECK(cpu.pc == stop_pc); CHECK(input_reads == 3);
    /* Continue the real error path back to the prompt, rather than intercept it. */
    stop_pc = symbol("CLOOP"); follow_basic_error = 1; run();
    CHECK(cpu.pc == stop_pc); CHECK(memory[symbol("ERR")] == 17);
    CHECK(!memory[symbol("ESC_PENDING")]); CHECK(!memory[symbol("KEY_COUNT")]);
    reset("INPUT_RAW"); fail_call = 7; run();
    CHECK(!memory[symbol("RAW_INPUT")]); invoke("LTRAP"); CHECK(input_reads == 0);
    fail_call = -1; keys[0] = 'z'; key_size = 1; invoke("OSRDCH"); CHECK(cpu.a == 'z');
    reset("OSINIT"); set_bc(8); set_de(0x7d00);
    strcpy((char *)memory + 0x7d00, "test.bbc"); run();
    CHECK(!cpu.zf); CHECK(memory[symbol("RAW_INPUT")] == 1);
    CHECK(!memcmp(memory + symbol("ACCS"), "test.bbc", 8));
}
int main(int argc, char **argv) {
    assert(argc == 3); map_path = argv[2];
    ram.mem_region.read = read_ram; ram.mem_region.write = write_ram;
    FILE *fp = fopen(argv[1], "rb"); assert(fp);
    size_t length = fread(image + 0x4000, 1, 0xc000, fp); fclose(fp); assert(length > 0);
    test_errors();
    test_loads();
    test_saves();
    test_chain_names();
    test_bundled_loads();
    test_escape();
    printf("PASS: %u adapter regression checks\n", checks);
    return 0;
}
