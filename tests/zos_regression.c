/* Run real assembled routines; model only Zeal syscalls and flat user RAM.
 * CPU implementation is supplied by an unmodified Zeal-NativeEmulator checkout.
 */
#include "hw/z80.h"
#include "hw/zvb/default_font.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static z80 cpu;
static device_t ram, video_io;
static uint8_t video[0x20000], video_ports[256];
static unsigned video_accesses;
static uint8_t memory[65536], image[65536], file[65536];
static const char *map_path;
static uint32_t file_size, file_pos;
static int fail_call, failure, close_failure, short_limit, opened, closed, transfers;
static int fail_transfer, premature_eof;
static int basic_error, invalid_buffer;
static unsigned last_flags;
static char opened_name[256];
static unsigned checks;
static char output[8192];
static unsigned output_size, cursor_x, cursor_y, cursor_sets;
static unsigned stop_pc;
static int follow_basic_error;
static uint8_t keys[1024];
static unsigned key_size, key_pos, keyboard_mode;
static int inject_interrupt, interrupt_seen, escape_after_reads, input_reads, interrupt_during_video;
static int partial_release;
static int file_exists;
static uint8_t native_open[128], close_errors[128];
static unsigned close_attempts[128], first_descriptor, exited;
static int mode_failure, stdin_limit, clobber_syscall_alternates;
static void invoke(const char *entry);

static uint8_t read_ram(device_t *dev, uint32_t address) {
    (void)dev;
    if (address >= 0x100000 && address < 0x120000) { video_accesses++; return video[address - 0x100000]; }
    return memory[address & 65535];
}
static void write_ram(device_t *dev, uint32_t address, uint8_t value) {
    (void)dev;
    if (address >= 0x100000 && address < 0x120000) { video_accesses++; video[address - 0x100000] = value; return; }
    memory[address & 65535] = value;
}
static uint8_t read_io(device_t *dev, uint32_t port) {
    if ((port & 0xf0) == 0xf0) return cpu.mmu.pages[dev->io_region.upper_addr >> 6];
    return video_ports[port];
}
static void write_io(device_t *dev, uint32_t port, uint8_t value) {
    (void)dev;
    if ((port & 0xf0) == 0xf0) { cpu.mmu.pages[port & 3] = value; }
    else video_ports[port] = value;
}
int mmu_init(mmu_t *mmu) {
    memset(mmu, 0, sizeof(*mmu));
    for (int i = 0; i < 4; ++i) { mmu->pages[i] = i; mmu->vpages[i].dev = &ram; }
    for (int i = 0; i < 256; ++i) mmu->io_mapping[i].dev = &video_io;
    return 0;
}
void vtimer_tick(uint64_t elapsed) { (void)elapsed; }
uint64_t vtimer_stall_bus(uint64_t maximum, const bool *requested) { (void)requested; return maximum; }

static uint16_t symbol(const char *name) {
    char module[128] = "";
    const char *separator = strchr(name, ':');
    if (separator) {
        snprintf(module, sizeof(module), ", %.*s,", (int)(separator - name), name);
        name = separator + 1;
    }
    FILE *fp = fopen(map_path, "r"); assert(fp);
    char line[512], found[128]; unsigned address, fallback = 0; int matched = 0;
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "%127s = $%x", found, &address) == 2 && !strcmp(name, found)) {
            if (*module && !strstr(line, module)) continue;
            if (strstr(line, ", public,")) { fclose(fp); return address; }
            if (!matched) { fallback = address; matched = 1; }
        }
    }
    fclose(fp);
    if (matched) return fallback;
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
    cpu.pc = symbol(entry); cpu.sp = 0xf600;
    memory[cpu.sp] = 0; memory[cpu.sp + 1] = 0x30;
    memset(video, 0, sizeof(video)); memset(video_ports, 0, sizeof(video_ports));
    memcpy(video + 0x3000, default_font, DEFAULT_FONT_SIZE);
    video_ports[0x82] = 1; video_accesses = 0;
    fail_call = -1; failure = 19; close_failure = 0; short_limit = -1;
    opened = closed = transfers = basic_error = invalid_buffer = 0;
    fail_transfer = premature_eof = 0;
    file_pos = 0; file_size = 16; opened_name[0] = 0;
    output_size = cursor_x = cursor_y = cursor_sets = 0;
    stop_pc = 0;
    follow_basic_error = 0;
    key_size = key_pos = keyboard_mode = 0;
    inject_interrupt = interrupt_seen = escape_after_reads = input_reads = 0;
    partial_release = 0; interrupt_during_video = 0;
    file_exists = 1; last_flags = 2;
    memset(native_open, 0, sizeof(native_open)); native_open[0] = native_open[1] = 1;
    memset(close_errors, 0, sizeof(close_errors)); memset(close_attempts, 0, sizeof(close_attempts));
    first_descriptor = 2; exited = 0;
    mode_failure = 0; stdin_limit = -1; clobber_syscall_alternates = 0;
    for (unsigned i = 0; i < sizeof(file); ++i) file[i] = (uint8_t)(i * 17 + 3);
    strcpy((char *)memory + 0xf100, "test.bbc");
    memory[symbol("PAGE")] = symbol("USER"); memory[symbol("PAGE") + 1] = symbol("USER") >> 8;
    memory[symbol("TOP")] = symbol("USER") + 3; memory[symbol("TOP") + 1] = (symbol("USER") + 3) >> 8;
    set_hl(0xf100); set_de(symbol("USER")); set_bc(16);
}
static void syscall(void) {
    unsigned call = cpu.l, address = cpu.d << 8 | cpu.e, count = cpu.b << 8 | cpu.c;
    unsigned whence = cpu.a;
    cpu.a = 0;
    if ((int)call == fail_call) { cpu.a = call == 2 ? (uint8_t)-failure : failure; }
    else switch (call) {
    case 2: {
        if (!file_exists && !(cpu.h & 16)) { cpu.a = (uint8_t)-4; break; }
        unsigned descriptor = first_descriptor;
        while (descriptor < 128 && native_open[descriptor]) descriptor++;
        if (descriptor == 128) { cpu.a = (uint8_t)-20; break; }
        opened++; last_flags = cpu.h; file_exists = 1; file_pos = 0;
        for (unsigned i = 0; i < sizeof(opened_name) - 1; ++i) {
            opened_name[i] = memory[(uint16_t)(count + i)];
            if (!opened_name[i]) break;
        }
        if (last_flags & 4) file_size = 0;
        native_open[descriptor] = 1; cpu.a = descriptor; break;
    }
    case 3:
        assert(cpu.h < 128); closed++; close_attempts[cpu.h]++;
        cpu.a = !native_open[cpu.h] ? 13 : close_errors[cpu.h] ? close_errors[cpu.h] : close_failure;
        if (!cpu.a) native_open[cpu.h] = 0;
        break;
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
            if (stdin_limit >= 0 && count > (unsigned)stdin_limit) count = stdin_limit;
            if (keyboard_mode == 1) {
                for (unsigned i = 0; i < count; ++i) if (keys[key_pos + i] == '\n') { count = i + 1; break; }
            }
            /* A raw read may never end with a release marker. */
            if (!partial_release && count && keys[key_pos + count - 1] == 0xfe) count--;
            memcpy(memory + address, keys + key_pos, count); key_pos += count;
            set_bc(count); break;
        }
        if (call == 1 && cpu.h == 0) {
            assert(output_size + count < sizeof(output));
            memcpy(output + output_size, memory + address, count);
            output_size += count; output[output_size] = 0; break;
        }
        if ((call == 0 && (last_flags & 3) == 1) || (call == 1 && (last_flags & 3) == 0)) {
            cpu.a = 19; break;
        }
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
            if (last_flags & 8) file_pos = file_size;
            assert(file_pos + count <= sizeof(file));
            memcpy(file + file_pos, memory + address, count);
            if (file_pos + count > file_size) file_size = file_pos + count;
        }
        file_pos += count; set_bc(count); break;
    case 6: {
        uint32_t offset = (uint32_t)cpu.b << 24 | (uint32_t)cpu.c << 16 | address;
        uint32_t base = whence == 1 ? file_pos : whence == 2 ? file_size : 0;
        uint32_t next = base + offset;
        file_pos = next > file_size ? file_size : next;
        set_bc(file_pos >> 16); set_de(file_pos & 65535); break;
    }
    case 7:
        if (cpu.h == 0 && cpu.c == 2) {
            memory[address] = cursor_x; memory[address + 1] = cursor_y; break;
        }
        if (cpu.h == 0 && cpu.c == 4) {
            cursor_x = cpu.d; cursor_y = cpu.e; cursor_sets++;
            set_bc(0xdead); /* Driver scratch registers must not alter PRINT. */
            break;
        }
        if (mode_failure) cpu.a = mode_failure; else keyboard_mode = cpu.e; break;
    case 15: exited = 1; cpu.pc = 0x3000; return;
    default: fprintf(stderr, "Unexpected syscall: %u\n", call); exit(1);
    }
    if (clobber_syscall_alternates) {
        /* A real ISR may use the alternate bank while kernel pages are mapped. */
        assert(cpu.i == 0x21);
        cpu.a_ = cpu.f_ = cpu.b_ = cpu.c_ = cpu.d_ = cpu.e_ = cpu.h_ = cpu.l_ = 0xaa;
    }
    /* Zeal returns status in A. Deliberately do not promise meaningful flags. */
    cpu.zf = false; cpu.cf = true;
    return_to_caller();
}
static void run(void) {
    unsigned error_entry = symbol("EXTERR");
    for (unsigned step = 0; step < 30000000; ++step) {
        if (cpu.pc == 0x3000 || (stop_pc && cpu.pc == stop_pc)) return;
        if (cpu.pc == error_entry && !follow_basic_error) { basic_error = cpu.a; return; }
        if (interrupt_during_video && cpu.mmu.pages[2] >= 0x40 && cpu.iff1) {
            interrupt_during_video = 0; inject_interrupt = 1;
        }
        if (inject_interrupt && cpu.iff1) {
            inject_interrupt = 0; z80_gen_int(&cpu, cpu.interrupt_mode == 2 ? 2 : 0xff);
        }
        if (cpu.pc == 0x2000) interrupt_seen++;
        if (cpu.pc == 8) syscall(); else z80_step(&cpu);
    }
    fprintf(stderr, "Instruction limit at %04x stop=%04x sp=%04x input=%u/%u\n", cpu.pc,stop_pc,cpu.sp,key_pos,key_size); exit(1);
}
#define CHECK(condition) do { checks++; if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); } } while (0)

static void test_errors(void) {
    const char *entries[] = {"OSLOAD", "OSSAVE", "OSBGET", "OSBPUT", "OSSHUT", "GETEXT", "GETPTR", "PUTPTR"};
    const int calls[] = {2, 2, 0, 1, 3, 4, 6, 6};
    for (unsigned i = 0; i < sizeof(calls) / sizeof(*calls); ++i) {
        reset(entries[i]); cpu.e = 2; cpu.a = 2; fail_call = calls[i];
        if (!strcmp(entries[i], "OSSHUT")) { memory[symbol("FILE_CHANNELS") + 2] = 1; native_open[2] = 1; }
        run();
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
    const unsigned lengths[] = {0, 1, 8191, 8192, 8193, 13914, 16384, 16385, 18000};
    for (unsigned i = 0; i < sizeof(lengths) / sizeof(*lengths); ++i) {
        reset("OSLOAD"); file_size = lengths[i]; set_bc(0x7000); run();
        CHECK(!basic_error); CHECK(cpu.cf); CHECK(closed == 1);
        CHECK(file_pos == file_size); CHECK(!invalid_buffer);
        CHECK(!memcmp(memory + symbol("USER"), file, file_size));
    }
    reset("OSLOAD"); file_size = 17; memory[symbol("USER")] = 0xaa; run();
    CHECK(!cpu.cf); CHECK(!basic_error); CHECK(transfers == 0);
    CHECK(memory[symbol("USER")] == 0xaa); CHECK(closed == 1);
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
static void test_validation(void) {
    const uint8_t cases[][8] = {
        {0}, {0,255}, {0,255,0}, {1,0,0}, {2,0,0}, {3,0,10},
        {5,0,0,10}, {4,0,0,0,0,255,255}, {4,0,0,10},
        {4,0,0,10,0,255,255}, {0,255,255,99}
    };
    const unsigned sizes[] = {0,2,3,3,3,3,4,7,4,7,4};
    for (unsigned i = 0; i < 11; ++i) {
        reset("LOAD0"); memcpy(file, cases[i], 8); file_size = sizes[i];
        strcpy((char *)memory + symbol("ACCS"), "test.bbc");
        stop_pc = i < 9 ? symbol("NEW") : 0x3000; run();
        CHECK(!basic_error); CHECK(cpu.pc == stop_pc);
        if (i < 9) CHECK(memory[symbol("USER")] == 0);
        else CHECK(memory[symbol("TOP")] == (i == 9 ? 7 : 3));
    }
    reset("LOAD0"); strcpy((char *)memory + symbol("ACCS"), "test.bbc");
    file_size = 100; fail_transfer = 2; short_limit = 4;
    memory[symbol("ERRTRP")] = 123; run();
    CHECK(basic_error == (128 | 19)); CHECK(memory[symbol("USER")] == 0);
    CHECK(memory[symbol("ERRTRP")] == 0); CHECK(memory[symbol("TOP")] == 3);
}
static void test_saves(void) {
    const unsigned lengths[] = {0, 1, 16383, 16384, 16385, 18000};
    for (unsigned i = 0; i < sizeof(lengths) / sizeof(*lengths); ++i) {
        reset("OSSAVE"); unsigned length = lengths[i]; set_bc(length);
        for (unsigned j = 0; j < length; ++j) memory[symbol("USER") + j] = (uint8_t)(j * 7);
        run();
        CHECK(!basic_error); CHECK(!invalid_buffer); CHECK(closed == 1);
        CHECK(file_size == length); CHECK(!memcmp(file, memory + symbol("USER"), length));
    }
    reset("OSSAVE"); set_de(0xbffd); set_bc(10000); short_limit = 257; run();
    CHECK(!basic_error); CHECK(!invalid_buffer); CHECK(closed == 1);
    CHECK(file_size == 10000); CHECK(!memcmp(file, memory + 0xbffd, 10000));
    reset("OSSAVE"); set_bc(17000); fail_transfer = 2; close_failure = 6; run();
    CHECK(basic_error == (128 | 19)); CHECK(closed == 1);
}
static void open_basic(void) {
    strcpy((char *)memory + 0xf200, "\"test.bbc\"\n"); cpu.iy = 0xf200;
    run();
}
static void test_openout(void) {
    reset("OPENOT"); open_basic();
    CHECK(!basic_error); CHECK(cpu.l_ == 2); CHECK(last_flags == 21);
    CHECK(file_size == 0); CHECK(file_pos == 0);
    cpu.e = 2; cpu.a = 'x'; invoke("OSBPUT");
    CHECK(!basic_error); CHECK(file_size == 1 && file[0] == 'x');
    set_de(0); set_hl(0); cpu.a = 2; invoke("PUTPTR");
    cpu.e = 2; cpu.a = 'y'; invoke("OSBPUT");
    CHECK(!basic_error); CHECK(file_size == 1 && file[0] == 'y');
    reset("OPENOT"); file_exists = 0; open_basic();
    CHECK(cpu.l_ == 2); CHECK(file_exists); CHECK(file_size == 0);
    reset("OPENOT"); fail_call = 2; open_basic();
    CHECK(!basic_error); CHECK(cpu.l_ == 0);
}
static void test_openup(void) {
    reset("OPENUP"); uint8_t original[16]; memcpy(original, file, sizeof(original));
    open_basic();
    CHECK(!basic_error); CHECK(cpu.l_ == 2); CHECK(last_flags == 2);
    CHECK(file_size == 16); CHECK(!memcmp(file, original, 16));
    cpu.e = 2; invoke("OSBGET"); CHECK(cpu.a == original[0]);
    set_de(0); set_hl(0); cpu.a = 2; invoke("PUTPTR");
    cpu.e = 2; cpu.a = 'x'; invoke("OSBPUT");
    CHECK(!basic_error); CHECK(file_size == 16 && file[0] == 'x');
    CHECK(!memcmp(file + 1, original + 1, 15));
    set_de(0); set_hl(0); cpu.a = 2; invoke("PUTPTR");
    cpu.e = 2; invoke("OSBGET"); CHECK(cpu.a == 'x');
    reset("OPENUP"); file_exists = 0; open_basic();
    CHECK(!basic_error); CHECK(cpu.l_ == 0); CHECK(!file_exists);
    reset("OPENIN"); open_basic(); CHECK(last_flags == 0); CHECK(file_size == 16);
    cpu.e = 2; invoke("OSBGET"); CHECK(cpu.a == 3);
    cpu.e = 2; cpu.a = 'x'; invoke("OSBPUT"); CHECK(basic_error == (128 | 19));
    reset("OPENUP"); fail_call = 2; open_basic(); CHECK(cpu.l_ == 0); CHECK(!basic_error);
}
static void test_eof(void) {
    const uint32_t sizes[] = {0, 3, 3, 3, 65537, 65537, 0x12345678, 0x12345678};
    const uint32_t positions[] = {0, 0, 2, 3, 65536, 65537, 0x12345677, 0x12345678};
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(*sizes); ++i) {
        reset("OSSTAT"); cpu.e = 2; file_size = sizes[i]; file_pos = positions[i];
        set_bc(0xabcd); cpu.zf = i & 1; run();
        CHECK(!basic_error); CHECK(cpu.zf == (positions[i] == sizes[i]));
        CHECK(!cpu.zf || cpu.a == 0); CHECK(file_pos == positions[i]);
        CHECK(cpu.b == 0xab && cpu.c == 0xcd); CHECK(transfers == 0);
    }
    reset("OSSTAT"); cpu.e = 2; file_size = 1; run(); CHECK(!cpu.zf);
    cpu.e = 2; invoke("OSSTAT"); CHECK(!cpu.zf); CHECK(file_pos == 0);
    cpu.e = 2; invoke("OSBGET"); CHECK(cpu.a == 3);
    cpu.e = 2; invoke("OSSTAT"); CHECK(cpu.zf); CHECK(file_pos == 1);
    reset("OSSTAT"); cpu.e = 2; fail_call = 6; failure = 13; run(); CHECK(basic_error == (128 | 13));
    reset("OSSTAT"); cpu.e = 2; fail_call = 4; run(); CHECK(basic_error == (128 | 19));
    /* The evaluator must translate the adapter's Z flag to BASIC TRUE/FALSE. */
    for (int eof = 0; eof < 2; ++eof) {
        reset("EOF"); file_size = 1; file_pos = eof;
        strcpy((char *)memory + 0xf200, "#2\n"); cpu.iy = 0xf200; run();
        uint32_t value = (uint32_t)cpu.h << 24 | (uint32_t)cpu.l << 16 | cpu.h_ << 8 | cpu.l_;
        CHECK(!basic_error); CHECK(value == (eof ? UINT32_MAX : 0));
    }
}
static void test_ext(void) {
    const uint32_t sizes[] = {0, 3, 255, 256, 65535, 65536, 0x12345678};
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(*sizes); ++i) {
        reset("GETEXT"); cpu.e = 2; file_size = sizes[i]; file_pos = 1; run();
        uint32_t value = (uint32_t)cpu.d << 24 | (uint32_t)cpu.e << 16 | cpu.h << 8 | cpu.l;
        CHECK(!basic_error); CHECK(value == sizes[i]); CHECK(file_pos == 1);
        reset("eval:EXT"); file_size = sizes[i];
        strcpy((char *)memory + 0xf200, "#2\n"); cpu.iy = 0xf200; run();
        value = (uint32_t)cpu.h << 24 | (uint32_t)cpu.l << 16 | cpu.h_ << 8 | cpu.l_;
        CHECK(!basic_error); CHECK(value == sizes[i]);
    }
    reset("GETEXT"); cpu.e = 2; fail_call = 4; run(); CHECK(basic_error == (128 | 19));
}
static void open_more(unsigned descriptor) {
    first_descriptor = descriptor;
    strcpy((char *)memory + 0xf200, "\"test.bbc\"\n"); cpu.iy = 0xf200;
    invoke("OPENIN"); CHECK(cpu.l_ == descriptor); CHECK(!basic_error);
}
static void program_error_location(void) {
    unsigned page = symbol("PAGE"), himem = symbol("HIMEM"), errlin = symbol("ERRLIN");
    memory[page] = symbol("USER"); memory[page + 1] = symbol("USER") >> 8;
    memory[himem] = 0; memory[himem + 1] = 0xf7;
    memory[errlin] = symbol("USER") + 3; memory[errlin + 1] = (symbol("USER") + 3) >> 8;
    const uint8_t program[] = {5, 10, 0, 0xe0, 10, 0, 0xff, 0xff};
    memcpy(memory + symbol("USER"), program, sizeof(program));
}
static void test_close_all(void) {
    reset("OPENIN"); native_open[7] = 1; open_basic(); open_more(5); open_more(127);
    unsigned owned = symbol("FILE_CHANNELS");
    CHECK(memory[owned + 2] && memory[owned + 5] && memory[owned + 127]);
    cpu.e = 2; invoke("OSSHUT"); CHECK(!memory[owned + 2]); CHECK(!native_open[2]);
    cpu.e = 0; invoke("OSSHUT"); CHECK(!basic_error); CHECK(closed == 3);
    CHECK(!native_open[5] && !native_open[127]); CHECK(native_open[0] && native_open[1] && native_open[7]);
    CHECK(!close_attempts[0] && !close_attempts[1] && !close_attempts[7]);
    cpu.e = 0; invoke("OSSHUT"); CHECK(closed == 3);
    reset("OSSHUT"); native_open[7] = 1; cpu.e = 7; run();
    CHECK(basic_error == (128 | 13)); CHECK(!closed); CHECK(native_open[7]);
    reset("OSSHUT"); cpu.e = 128; run(); CHECK(basic_error == (128 | 13)); CHECK(!closed);
    reset("OPENIN"); open_basic(); open_more(5); open_more(127);
    close_errors[2] = 6; close_errors[5] = 19; cpu.e = 0; invoke("OSSHUT");
    CHECK(basic_error == (128 | 6)); CHECK(closed == 3);
    CHECK(memory[owned + 2] && memory[owned + 5] && !memory[owned + 127]);
    CHECK(!native_open[127]); close_errors[2] = close_errors[5] = 0; basic_error = 0;
    cpu.e = 0; invoke("OSSHUT"); CHECK(!basic_error); CHECK(closed == 5);
    CHECK(!memory[owned + 2] && !memory[owned + 5]); CHECK(close_attempts[127] == 1);
    reset("OPENIN"); fail_call = 2; open_basic();
    fail_call = -1; cpu.e = 0; invoke("OSSHUT"); CHECK(!closed);
    reset("OSLOAD"); run(); CHECK(!memory[owned + 2]); CHECK(!native_open[2]);
    reset("OSSAVE"); close_failure = 6; run(); CHECK(memory[owned + 2]);
    close_failure = 0; basic_error = 0; cpu.e = 0; invoke("OSSHUT");
    CHECK(!basic_error); CHECK(!memory[owned + 2]); CHECK(closed == 2);
    reset("OPENIN"); first_descriptor = 0; native_open[0] = 0; open_basic();
    CHECK(cpu.l_ == 0); CHECK(!native_open[0]); CHECK(!memory[owned]);
    reset("OPENIN"); open_basic(); program_error_location(); stop_pc = symbol("WARM");
    invoke("END"); CHECK(cpu.pc == stop_pc); CHECK(!native_open[2]); CHECK(!memory[owned + 2]);
    reset("OPENIN"); open_basic(); open_more(5); program_error_location(); close_errors[2] = 6;
    follow_basic_error = 1; stop_pc = symbol("CLOOP"); cpu.a = 18; invoke("ERROR");
    CHECK(cpu.pc == stop_pc); CHECK(memory[symbol("ERR")] == 18);
    CHECK(memory[owned + 2]); CHECK(!memory[owned + 5]); CHECK(!native_open[5]);
    reset("OPENIN"); open_basic(); invoke("BYE"); CHECK(exited); CHECK(!native_open[2]);
    CHECK(native_open[0] && native_open[1]); CHECK(keyboard_mode == 1);
}
static void test_chain_names(void) {
    const char *entries[] = {"CHAIN", "RUN"};
    for (unsigned i = 0; i < 2; ++i) {
        reset(entries[i]);
        unsigned accs = symbol("ACCS"), himem = symbol("HIMEM"), page = symbol("PAGE");
        memset(memory + accs, 'X', 256);
        strcpy((char *)memory + 0xf200, "\"test.bbc\"\n"); cpu.iy = 0xf200;
        memory[himem] = 0; memory[himem + 1] = 0xf7;
        memory[page] = symbol("USER"); memory[page + 1] = symbol("USER") >> 8;
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
        memory[page] = symbol("USER"); memory[page + 1] = symbol("USER") >> 8;
        memory[himem] = 0; memory[himem + 1] = 0xf7;
        snprintf((char *)memory + 0xf200, 128, "\"%s\"\n", paths[i]); cpu.iy = 0xf200;
        stop_pc = symbol("RUN0"); run();
        CHECK(!basic_error); CHECK(cpu.pc == stop_pc);
        CHECK(!strcmp(opened_name, paths[i])); CHECK(file_pos == file_size);
        CHECK(!memcmp(memory + symbol("USER"), file, file_size));
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
    memory[0x2100] = memory[0x2102] = 0;
    memory[0x2101] = memory[0x2103] = 0x20;
    cpu.i = 0x21; cpu.interrupt_mode = 2;
    z80 entry = cpu;
    invoke("IRQ_INIT");
    cpu = entry; cpu.i = 0xf7; cpu.iff1 = cpu.iff2 = 1;
    memory[cpu.sp] = 0; memory[cpu.sp + 1] = 0x30;
    inject_interrupt = 1;
}
static void check_alternates(void) {
    CHECK(interrupt_seen == 1); CHECK(cpu.iff1);
    CHECK(cpu.a_ == 0x12 && cpu.f_ == 0x34);
    CHECK(cpu.b_ == 0x56 && cpu.c_ == 0x78);
    CHECK(cpu.d_ == 0x9a && cpu.e_ == 0xbc);
    CHECK(cpu.h_ == 0xde && cpu.l_ == 0xf0);
}
static void invoke(const char *entry) {
    cpu.pc = symbol(entry); cpu.sp = 0xf600;
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
    memory[page] = symbol("USER"); memory[page + 1] = symbol("USER") >> 8;
    memory[himem] = 0; memory[himem + 1] = 0xf7;
    const uint8_t loop[] = {9, 10, 0, 0xe5, 0x8d, 0x54, 0x4a, 0x40, 10, 0, 0xff, 0xff};
    memcpy(memory + symbol("USER"), loop, sizeof(loop));
    unsigned top = symbol("TOP"); memory[top] = symbol("USER") + 12; memory[top + 1] = (symbol("USER") + 12) >> 8;
    escape_after_reads = 3; stop_pc = symbol("ESCAPE"); run();
    CHECK(cpu.pc == stop_pc); CHECK(input_reads == 3);
    /* Continue the real error path back to the prompt, rather than intercept it. */
    stop_pc = symbol("CLOOP"); follow_basic_error = 1; run();
    CHECK(cpu.pc == stop_pc); CHECK(memory[symbol("ERR")] == 17);
    CHECK(!memory[symbol("ESC_PENDING")]); CHECK(!memory[symbol("KEY_COUNT")]);
    reset("INPUT_RAW"); fail_call = 7; run();
    CHECK(!memory[symbol("RAW_INPUT")]); invoke("LTRAP"); CHECK(input_reads == 0);
    fail_call = -1; keys[0] = 'z'; key_size = 1; invoke("OSRDCH"); CHECK(cpu.a == 'z');
    reset("OSINIT"); set_bc(8); set_de(0xf200);
    strcpy((char *)memory + 0xf200, "test.bbc"); run();
    CHECK(!cpu.zf); CHECK(memory[symbol("RAW_INPUT")] == 1);
    CHECK(!memcmp(memory + symbol("ACCS"), "test.bbc", 8));
}
static void test_characters(void) {
    const uint8_t events[] = {0x93, 'a', 0x96, 0xfe, 0x93, 'b', 0xfe, 0x96, 'c',
                             0x92, 0x92, 'd', 0xfe, 0x92, 0x93, 'e', 0xfe, 0x93, 0x92, 0xfe, 0x92, 0x95, 'f',
                             0xfe, 0x95, 0x93, '1', '/', 0xfe, 0x93, 0x80, 0x8b,
                             0x94, 0xa0, 'z'};
    const uint8_t expected[] = {'A', 'B', 'c', 'D', 'e', 6, '!', '?', '0', 10, 'z'};
    reset("LTRAP"); prepare_keyboard(); memcpy(keys, events, sizeof(events)); key_size = sizeof(events);
    while (key_pos < key_size) invoke("LTRAP");
    CHECK(!basic_error); CHECK(memory[symbol("KEY_COUNT")] == sizeof(expected));
    for (unsigned i = 0; i < sizeof(expected); ++i) {
        invoke("OSRDCH"); CHECK(cpu.a == expected[i]);
    }
    reset("OSRDCH"); prepare_keyboard();
    const uint8_t control[] = {0x98, 0x95, 0xfe, 0x98, '[', 0xfe, 0x95, 'x'};
    memcpy(keys, control, sizeof(control)); key_size = sizeof(control);
    run(); CHECK(cpu.a == 27); CHECK(!memory[symbol("ESC_PENDING")]);
    invoke("OSRDCH"); CHECK(cpu.a == 'x');
    reset("INPUT_COOKED"); memory[symbol("KEY_MODIFIERS")] = 31; run();
    CHECK(!memory[symbol("KEY_MODIFIERS")]);
}
static void test_lines(void) {
    const unsigned lengths[] = {0, 1, 254, 255};
    for (unsigned i = 0; i < 4; ++i) {
        reset("OSLINE"); memset(keys, 'a', lengths[i]); keys[lengths[i]] = '\n'; key_size = lengths[i] + 1;
        memset(memory + 0xf100, 0xaa, 257); run();
        CHECK(!basic_error); CHECK(memory[0xf100 + lengths[i]] == '\n');
        CHECK(memory[0xf200] == 0xaa); CHECK(keyboard_mode == 4);
    }
    reset("OSLINE"); memcpy(keys, "abc", 3); key_size = 3; run();
    CHECK(!basic_error); CHECK(!memcmp(memory + 0xf100, "abc\n", 4));
    reset("OSLINE"); fail_call = 0; run();
    CHECK(basic_error == (128 | 19)); CHECK(memory[0xf100] == '\n'); CHECK(keyboard_mode == 4);
    reset("OSLINE"); run(); CHECK(basic_error == (128 | 21)); CHECK(memory[0xf100] == '\n');
    reset("OSLINE"); mode_failure = 3; stdin_limit = 1;
    memcpy(keys, "one\r\ntwo\nlast", 13); key_size = 13; run();
    CHECK(!basic_error); CHECK(!memcmp(memory + 0xf100, "one\n", 4)); CHECK(key_pos == 5);
    set_hl(0xf100); invoke("OSLINE"); CHECK(!memcmp(memory + 0xf100, "two\n", 4)); CHECK(key_pos == 9);
    set_hl(0xf100); invoke("OSLINE"); CHECK(!memcmp(memory + 0xf100, "last\n", 5));
    set_hl(0xf100); invoke("OSLINE"); CHECK(basic_error == (128 | 21)); CHECK(memory[0xf100] == '\n');
    reset("OSLINE"); mode_failure = 3; memset(keys, 'x', 256);
    memcpy(keys + 256, "\nok\n", 4); key_size = 260; memory[0xf200] = 0xaa; run();
    CHECK(basic_error == (128 | 6)); CHECK(key_pos == 257); CHECK(memory[0xf200] == 0xaa);
    basic_error = 0; set_hl(0xf100); invoke("OSLINE");
    CHECK(!basic_error); CHECK(!memcmp(memory + 0xf100, "ok\n", 3));
    reset("OSLINE"); mode_failure = 1; run(); CHECK(basic_error == (128 | 1)); CHECK(input_reads == 0);
}
static void test_arguments(void) {
    const unsigned lengths[] = {0,1,127,255,256,257,65535};
    for (unsigned i = 0; i < 7; ++i) {
        reset("OSINIT"); unsigned length = lengths[i], acc = symbol("ACCS");
        memset(memory + 0xe000, 'a', 256); memset(memory + acc, 0xaa, 257);
        set_bc(length); set_de(0xe000); run();
        CHECK(!basic_error); CHECK(!exited); CHECK(cpu.zf == (length == 0 || length > 255));
        CHECK(memory[acc + 256] == 0xaa);
        CHECK((cpu.h << 8 | cpu.l) == symbol("USER")); CHECK((cpu.d << 8 | cpu.e) == 0xf700);
        if (length <= 255) {
            CHECK(memory[acc + length] == 0);
            for (unsigned j = 0; j < length; ++j) CHECK(memory[acc + j] == 'a');
        } else { CHECK(memory[acc] == 0); CHECK(memory[acc + 1] == 0xaa); }
    }
}
static void test_commands(void) {
    const char *commands[] = {"", "\n", " \t\n", " | comment\n", "|BYE",
        "BYE", "bye\n", " \tbYe \t\n", "cPm\n", "CPM\r",
        "DIR\n", "BYEX\n", "BYE arg\n", "BY\n", "anything", "CPM.\n"};
    for (unsigned i = 0; i < sizeof(commands)/sizeof(*commands); ++i) {
        reset("OPENIN"); open_basic();
        strcpy((char *)memory + 0xf200, commands[i]); set_hl(0xf200); cpu.iy = 0xf345;
        invoke("OSCLI");
        CHECK(cpu.iy == 0xf345);
        if (i >= 5 && i <= 9) {
            CHECK(exited); CHECK(!basic_error); CHECK(closed == 1); CHECK(!native_open[2]);
        } else {
            CHECK(!exited); CHECK(closed == 0); CHECK(native_open[2]);
            CHECK(basic_error == (i >= 10 ? 254 : 0));
        }
    }
    /* The two interpreter entry paths must share the same dispatch. */
    reset("CLI"); strcpy((char *)memory + 0xf200, "\"DIR\"\n"); cpu.iy = 0xf200; run();
    CHECK(basic_error == 254); CHECK(!exited);
    reset("exec:EXT"); strcpy((char *)memory + 0xf200, "DIR\n"); cpu.iy = 0xf200; run();
    CHECK(basic_error == 254); CHECK(!exited);
    reset("CLI"); strcpy((char *)memory + 0xf200, "\"bye\"\n"); cpu.iy = 0xf200; run();
    CHECK(exited); CHECK(!basic_error);
    reset("exec:EXT"); strcpy((char *)memory + 0xf200, "bye\n"); cpu.iy = 0xf200; run();
    CHECK(exited); CHECK(!basic_error);
    reset("RUN0"); program_error_location();
    const uint8_t commented[] = {12,10,0,'*','|','c','o','m','m','e','n',10,
        5,20,0,0xe0,10,0,255,255};
    memcpy(memory + symbol("USER"), commented, sizeof(commented));
    stop_pc = symbol("WARM"); run();
    CHECK(!basic_error); CHECK(!exited); CHECK(cpu.pc == stop_pc);
    reset("CLI"); strcpy((char *)memory + 0xf200, "\"\":\340\n"); cpu.iy = 0xf200;
    program_error_location(); stop_pc = symbol("CLOOP"); run();
    CHECK(!basic_error); CHECK(!exited); CHECK(cpu.pc == stop_pc);

}
static void test_cursor_width(void) {
    reset("PUTCSR"); set_bc(0x1234); set_de(5); set_hl(10); run();
    CHECK(!basic_error); CHECK((cpu.b << 8 | cpu.c) == 0x1234);
    CHECK(cursor_sets == 1 && cursor_x == 5 && cursor_y == 10);
    for (unsigned tab = 0; tab < 2; ++tab) {
        reset("PRINT"); program_error_location();
        memory[symbol("STAVAR")] = 10;
        const uint8_t plain[] = {'1',':',0xe0,10,0};
        const uint8_t positioned[] = {0x8a,'5',',','1','0',')','1',':',0xe0,10,0};
        memcpy(memory + 0xf200, tab ? positioned : plain, tab ? sizeof(positioned) : sizeof(plain));
        cpu.iy = 0xf200; cpu.a = memory[cpu.iy]; stop_pc = symbol("CLOOP"); run();
        CHECK(!basic_error); CHECK(output_size == 11); CHECK(!memcmp(output, "         1\n",11));
        CHECK(cursor_sets == tab);
        if (tab) CHECK(cursor_x == 5 && cursor_y == 10);
    }
}
static unsigned tokenize_text(const char *text, uint8_t *dest) {
    assert(strlen(text) < 255);
    reset("LEXAN2"); strcpy((char *)memory + 0xf200, text);
    memory[0xf200 + strlen(text)] = 10;
    cpu.iy = 0xf200; set_de(0xf000); cpu.c = 1; run();
    assert(!basic_error && cpu.a == 10 && cpu.d == 0xf0);
    unsigned size = cpu.e; memcpy(dest, memory + 0xf000, size);
    return size;
}
/* Regenerate records with BASIC's own lexer, so example checks use exactly
 * the token and encoded-line-number format accepted by this interpreter. */
static unsigned tokenize_source(const char *path, uint8_t *dest) {
    FILE *fp = fopen(path, "r"); assert(fp);
    char line[1024]; unsigned length = 0, previous = 0;
    while (fgets(line, sizeof(line), fp)) {
        char *text; unsigned number = strtoul(line, &text, 10);
        if (text == line || !number) continue; /* unnumbered attribution */
        assert(number > previous && number < 65536); previous = number;
        while (*text == ' ' || *text == '\t') text++;
        text[strcspn(text, "\r\n")] = 0;
        uint8_t body[256]; unsigned size = tokenize_text(text, body);
        assert(size <= 251 && length + size + 7 < 65536);
        dest[length++] = size + 4;
        dest[length++] = number; dest[length++] = number >> 8;
        memcpy(dest + length, body, size); length += size;
        dest[length++] = 10;
    }
    fclose(fp); dest[length++] = 0; dest[length++] = 255; dest[length++] = 255;
    return length;
}
static unsigned example_line(const uint8_t *program, unsigned number) {
    for (unsigned pos = 0; program[pos]; pos += program[pos]) {
        if ((program[pos+1] | program[pos+2] << 8) == number) return pos;
    }
    fprintf(stderr, "Missing example line %u\n", number); exit(1);
}
static void test_hamurabi_source(void) {
    uint8_t expected[65536], actual[65536];
    unsigned size = tokenize_source("examples/hamurabi.bas", expected);
    FILE *fp = fopen("examples/hamurabi.bbc", "rb"); assert(fp);
    unsigned actual_size = fread(actual, 1, sizeof(actual), fp); fclose(fp);
    CHECK(actual_size == size); CHECK(!memcmp(actual, expected, size));
    unsigned purchase = example_line(actual, 331), retry = example_line(actual, 470);
    reset("XEQ"); program_error_location();
    memory[symbol("TOP")] = 8; invoke("CLEAR");
    unsigned pos = 0xf200;
    const char *init = "A=1000:S=2800:Y=20:Q=5:C=9:";
    memcpy(memory + pos, init, strlen(init)); pos += strlen(init);
    memcpy(memory + pos, actual + purchase + 3, actual[purchase] - 4); pos += actual[purchase] - 4;
    const char *result = ":A%=A:S%=S:C%=C:";
    memcpy(memory + pos, result, strlen(result)); pos += strlen(result);
    memory[pos++] = 0xe0; memory[pos] = 10;
    cpu.iy = 0xf200; stop_pc = symbol("CLOOP"); invoke("XEQ");
    CHECK(!basic_error);
    unsigned vars = symbol("STAVAR");
    CHECK((memory[vars+4] | memory[vars+5] << 8) == 1005);
    CHECK((memory[vars+76] | memory[vars+77] << 8) == 2700);
    CHECK(memory[vars+12] == 0 && memory[vars+13] == 0);
    reset("XEQ"); memcpy(memory + symbol("USER"), actual, size);
    stop_pc = symbol("exec:XEQ0"); unsigned stack = cpu.sp;
    for (unsigned attempt = 0; attempt < 20; ++attempt) {
        cpu.pc = symbol("XEQ"); cpu.iy = symbol("USER") + retry + 3; run();
        CHECK(!basic_error); CHECK(cpu.sp == stack);
        CHECK(cpu.iy == symbol("USER") + example_line(actual, 440));
    }

}
static void test_blackjack_procedure(void) {
    uint8_t program[65536], init[256];
    unsigned size = tokenize_source("examples/blackjack.bas", program);
    /* Run the source-defined score procedure with a populated one-player hand. */
    unsigned init_size = tokenize_text(
        "DIM playname$(1),score%(1),numofcards%(1):numplayer%=1:"
        "playname$(1)=\"Ada\":score%(1)=21:numofcards%(1)=2:PROCwhoone:END", init);
    unsigned definition = example_line(program, 1940), call = example_line(program, 1060);
    CHECK(program[call + 3] == 0xf2); /* PROC */
    CHECK(!memcmp(program + call + 4, "whoone", 6));
    CHECK(program[definition + 3] == 0xdd && program[definition + 4] == 0xf2); /* DEF PROC */
    CHECK(!memcmp(program + definition + 5, "whoone\n", 7));
    reset("XEQ"); program_error_location();
    memcpy(memory + symbol("USER"), program, size);
    unsigned top = symbol("USER") + size;
    memory[symbol("TOP")] = top; memory[symbol("TOP") + 1] = top >> 8;
    invoke("CLEAR");
    memcpy(memory + 0xf200, init, init_size); memory[0xf200 + init_size] = 10;
    keys[0] = 'x'; key_size = 1; cpu.iy = 0xf200; stop_pc = symbol("CLOOP"); invoke("XEQ");
    CHECK(!basic_error); CHECK(!exited); CHECK(cpu.pc == stop_pc);
    CHECK(strstr(output, "Ada got a total score of 21") != NULL);
    CHECK(strstr(output, "using 2 press enter too continue...") != NULL);
    CHECK(key_pos == 1);
}
static void test_irq_vectors(void) {
    for (unsigned vector = 0; vector <= 2; vector += 2) {
        reset("LTRAP"); prepare_keyboard(); inject_interrupt = 0;
        CHECK(cpu.i == 0xf7); CHECK(memory[0x2101] == 0x20 && memory[0x2103] == 0x20);
        set_bc(0x1234); set_de(0x5678); set_hl(0x9abc);
        memory[0x3100] = 0; memory[0x3101] = 0xc3;
        memory[0x3102] = 0; memory[0x3103] = 0x30; cpu.pc = 0x3100;
        z80_gen_int(&cpu, vector); run(); check_alternates();
        CHECK((cpu.b << 8 | cpu.c) == 0x1234);
        CHECK((cpu.d << 8 | cpu.e) == 0x5678);
        CHECK((cpu.h << 8 | cpu.l) == 0x9abc);
        clobber_syscall_alternates = 1;
        cpu.a = 'x'; invoke("OSWRCH"); CHECK(cpu.i == 0xf7); check_alternates();
        clobber_syscall_alternates = 0;
        invoke("BYE"); CHECK(exited); CHECK(cpu.i == 0x21);
    }
}
static void display_byte(unsigned byte) {
    cpu.a = byte; invoke("OSWRCH"); CHECK(!basic_error);
    CHECK(cpu.mmu.pages[0] == 0 && cpu.mmu.pages[2] == 2);
}
static void plot(unsigned op, int x, int y) {
    cpu.a = op; set_de((uint16_t)x); set_hl((uint16_t)y); invoke("G_PLOT"); CHECK(!basic_error);
    CHECK(cpu.mmu.pages[0] == 0 && cpu.mmu.pages[2] == 2);
}
static int point(int x, int y) {
    set_de((uint16_t)x); set_hl((uint16_t)y); invoke("G_POINT"); CHECK(!basic_error);
    return (int16_t)(cpu.h << 8 | cpu.l);
}
static void vdu(const uint8_t *bytes, unsigned count) {
    for (unsigned i=0;i<count;i++) display_byte(bytes[i]);
}
/* Compare visible pixels with a wide-integer reference, including lines
 * whose off-screen error terms exceed a signed Z80 word when doubled. */
static void test_line_raster(void) {
    static const int endpoints[][4] = {
        {-32768,100,32767,104}, {100,-32768,104,32767},
        {0,0,1276,1020}, {1276,0,0,1020}, {0,512,1276,512},
        {640,0,640,1020}, {80,80,80,80}, {0,0,80,40}, {0,0,40,80}
    };
    uint8_t expected[64000];
    for (unsigned i=0;i<sizeof(endpoints)/sizeof(*endpoints);i++) {
        for (unsigned reverse=0;reverse<2;reverse++) {
            for (unsigned family=0;family<64;family+=8) {
                reset("D_MODE"); cpu.a=1; run(); CHECK(!basic_error);
                const int *p=endpoints[i]; unsigned a=reverse ? 2 : 0, b=reverse ? 0 : 2;
                plot(4,p[a],p[a+1]); plot(family+5,p[b],p[b+1]);
                memset(expected,0,sizeof(expected));
                int x=p[a]>>2, y=199-(((p[a+1]>>2)*25)>>5);
                int tx=p[b]>>2, ty=199-(((p[b+1]>>2)*25)>>5);
                int dx=abs(tx-x), dy=-abs(ty-y), sx=x<tx ? 1 : -1, sy=y<ty ? 1 : -1;
                int error=dx+dy; unsigned step=0;
                for (;;) {
                    int last=x==tx && y==ty;
                    if (!(family&8 && last) && !(family&32 && !step) && !(family&16 && (step&1))
                        && x>=0 && x<320 && y>=0 && y<200) expected[y*320+x]=3;
                    if (last) break;
                    int twice=error*2;
                    if (twice>=dy) { error+=dy; x+=sx; }
                    if (twice<=dx) { error+=dx; y+=sy; }
                    step++;
                }
                CHECK(!memcmp(video+0x10000,expected,sizeof(expected)));
            }
        }
    }
}
static void test_fill_boundary(void) {
    reset("D_MODE"); cpu.a=1; run(); CHECK(!basic_error);
    cpu.a=0; cpu.e=2; invoke("G_COLOUR");
    plot(4,80,80); plot(5,80,200); plot(4,200,80); plot(5,200,200);
    cpu.a=0; cpu.e=1; invoke("G_COLOUR"); plot(77,120,120);
    CHECK(point(40,120)==0 && point(80,120)==2);
    CHECK(point(120,120)==1 && point(200,120)==2 && point(240,120)==0);
    /* A seed on an existing non-background pixel must not fill or erase it. */
    plot(77,80,120); CHECK(point(80,120)==2 && point(40,120)==0);
}
static void test_video_spans(void) {
    const unsigned starts[]={0x3ff7,0x7ff7,0xbff7,0xfff7};
    for (unsigned action=0;action<4;action++) {
        for (unsigned i=0;i<4;i++) {
            unsigned start=starts[i], count=i==3 ? 9 : 73;
            reset("V_PAINT");
            for (unsigned x=0;x<65536;x++) video[0x10000+x]=x&3;
            prepare_keyboard(); inject_interrupt=0; interrupt_during_video=1;
            cpu.a=2; cpu.l=action; set_de(start); set_bc(count); run();
            check_alternates(); CHECK(interrupt_seen && cpu.mmu.pages[2]==2);
            for (unsigned x=start-1;x<start+count+(i==3 ? 0 : 1);x++) {
                unsigned old=x&3, want=old;
                if (x>=start && x<start+count)
                    want=action==0 ? 2 : action==1 ? old|2 : action==2 ? old&2 : old^2;
                CHECK(video[0x10000+x]==want);
            }
        }
    }
    reset("V_PAINT"); cpu.a=2; cpu.l=3; set_de(0xffff); set_bc(0); run();
    CHECK(!video_accesses && cpu.mmu.pages[2]==2);
}
static void test_glyph_raster(void) {
    const unsigned modes[]={0,1,2,4,5}, widths[]={4,8,16,8,16};
    const uint8_t glyph[]={0x81,0x42,0x24,0x18,0x81,0xff,0x55,0xaa};
    const unsigned sampled[]={0,2,3,4,5,6};
    for (unsigned i=0;i<5;i++) {
        reset("D_MODE"); cpu.a=modes[i]; run(); CHECK(!basic_error);
        display_byte(23); display_byte(224); vdu(glyph,8);
        const uint8_t cursor[]={31,1,3}; vdu(cursor,sizeof(cursor)); display_byte(224);
        unsigned width=widths[i], ink=memory[symbol("D_MASK")];
        for (unsigned y=18;y<25;y++) {
            for (unsigned x=width-1;x<=width*2;x++) {
                unsigned want=0;
                if (x>=width && x<width*2 && y<24) {
                    unsigned bit=(x-width)*8/width;
                    if (glyph[sampled[y-18]] & (0x80>>bit)) want=ink;
                }
                CHECK(video[0x10000+y*320+x]==want);
            }
        }
    }
    reset("D_MODE"); cpu.a=1; run();
    display_byte(23); display_byte(224); vdu(glyph,8);
    for (unsigned y=121;y<127;y++) memset(video+0x10000+y*320+40,1,8);
    cpu.a=3; cpu.e=2; invoke("G_COLOUR"); display_byte(5);
    for (unsigned pass=0;pass<2;pass++) {
        plot(4,160,400); display_byte(224);
        for (unsigned y=0;y<6;y++) for (unsigned x=0;x<8;x++) {
            unsigned want=pass==0 && (glyph[sampled[y]] & (0x80>>x)) ? 3 : 1;
            CHECK(video[0x10000+(121+y)*320+40+x]==want);
        }
        CHECK((memory[symbol("G_X")]|memory[symbol("G_X")+1]<<8)==192);
    }
}
static void test_runtime_video_state(void) {
    reset("OSINIT");
    memset(memory+symbol("DISPLAY_SCRATCH"),0xa5,symbol("DISPLAY_SCRATCH_SIZE"));
    set_bc(0); run(); CHECK(!basic_error);
    CHECK(memory[symbol("G_ACTION")]==0 && memory[symbol("G_BG")]==0);
    for (unsigned i=0;i<16;i++) CHECK(memory[symbol("G_X")+i]==0);
    CHECK((memory[symbol("G_RIGHT")]|memory[symbol("G_RIGHT")+1]<<8)==1279);
    CHECK((memory[symbol("G_TOP")]|memory[symbol("G_TOP")+1]<<8)==1023);
}
static void test_scaled_coordinates(void) {
    reset("G_SCALE_Y");
    for (int y=-32768;y<=32767;y+=37) {
        int row=y>=0 ? y/4 : (y-3)/4;
        int product=row*25;
        int expected=199-(product>=0 ? product/32 : (product-31)/32);
        set_hl((uint16_t)y); invoke("G_SCALE_Y");
        CHECK((int16_t)(cpu.h<<8|cpu.l)==expected);
    }
    set_hl(32767); invoke("G_SCALE_Y"); CHECK((int16_t)(cpu.h<<8|cpu.l)==-6200);
}
static void test_text_window_rectangles(void) {
    const unsigned widths[]={4,8,16,1,8,16,1};
    for (unsigned mode=0;mode<7;mode++) {
        reset("D_MODE"); cpu.a=mode; run(); CHECK(!basic_error);
        const uint8_t window[]={28,3,6,5,2}, cursor[]={31,1,1};
        vdu(window,sizeof(window)); vdu(cursor,sizeof(cursor));
        invoke("D_WINDOW_RECT"); CHECK(!basic_error);
        CHECK(memory[symbol("D_X")]==4 && memory[symbol("D_Y")]==3);
        unsigned bitmap=mode!=3 && mode!=6, width=widths[mode];
        unsigned left=3*width, right=6*width-1;
        unsigned top=bitmap ? 12 : 2, bottom=bitmap ? 42 : 6;
        CHECK((memory[symbol("D_L")]|memory[symbol("D_L")+1]<<8)==left);
        CHECK((memory[symbol("D_R")]|memory[symbol("D_R")+1]<<8)==right);
        CHECK((memory[symbol("D_T")]|memory[symbol("D_T")+1]<<8)==top);
        CHECK((memory[symbol("D_B")]|memory[symbol("D_B")+1]<<8)==bottom);
        unsigned base=bitmap ? 0x10000 : 0, stride=bitmap ? 320 : 80;
        memset(video+base,7,bitmap ? 64000 : 3200);
        invoke("D_CLEAR"); CHECK(!basic_error);
        for (unsigned y=top-1;y<=bottom+1;y++) {
            for (unsigned x=left-1;x<=right+1;x++) {
                unsigned want=(x>=left && x<=right && y>=top && y<=bottom) ? (bitmap ? 0 : 32) : 7;
                CHECK(video[base+y*stride+x]==want);
            }
        }
        invoke("GETCSR"); CHECK(cpu.e==0 && cpu.l==0);
    }
}
static void test_default_palettes(void) {
    const unsigned rgb[]={0,0xf800,0x07e0,0xffe0,0x001f,0xf81f,0x07ff,0xffff};
    for (unsigned mode=0;mode<7;mode++) {
        reset("D_MODE"); cpu.a=mode; run(); CHECK(!basic_error);
        unsigned mask=memory[symbol("D_MASK")];
        CHECK(memory[symbol("G_ACTION")]==0 && memory[symbol("G_BG")]==0);
        CHECK(memory[symbol("G_FG")]==mask && memory[symbol("D_FG")]==mask);
        for (unsigned i=0;i<16;i++) {
            unsigned want=rgb[i&7];
            if (mask==1 && i==1) want=0xffff;
            if (mask==3 && i==2) want=0xffe0;
            if (mask==3 && i==3) want=0xffff;
            CHECK((video[0xe00+i*2]|video[0xe01+i*2]<<8)==want);
        }
    }
    reset("D_MODE"); cpu.a=2; run();
    for (unsigned i=0;i<8;i++) {
        const uint8_t colour[]={19,15,i,0,0,0}; vdu(colour,sizeof(colour));
        CHECK((video[0xe1e]|video[0xe1f]<<8)==rgb[i]);
    }
}
static void test_graphics_semantics(void) {
    uint8_t statement[256];
    unsigned size = tokenize_text("GCOL 0,2:MOVE 0,0:DRAW 80,80:A%=POINT(80,80):B%=POINT(-4,0):END", statement);
    reset("D_MODE"); program_error_location(); cpu.a = 1; run(); CHECK(!basic_error);
    memcpy(memory + 0xf200, statement, size); memory[0xf200+size] = 10;
    cpu.iy = 0xf200; stop_pc = symbol("CLOOP"); invoke("XEQ");
    CHECK(!basic_error);
    CHECK(memory[symbol("STAVAR")+4] == 2);
    CHECK(memory[symbol("STAVAR")+8] == 255 && memory[symbol("STAVAR")+11] == 255);
    stop_pc = 0;
    invoke("G_CLEAR"); CHECK(!basic_error);
    cpu.a = 3; cpu.e = 1; invoke("G_COLOUR");
    for (int i=0;i<2;i++) {
        plot(4,40,40); plot(4,200,40); plot(85,120,200);
        CHECK(point(120,80) == (i == 0 ? 1 : 0));
        CHECK(point(120,240) == 0);
    }
    cpu.a = 0; cpu.e = 2; invoke("G_COLOUR");
    const uint8_t window[] = {24,40,0,40,0,200,0,200,0}; vdu(window,sizeof(window));
    plot(4,-32768,-32768); plot(101,32767,32767);
    CHECK(point(120,120) == 2); CHECK(point(0,0) == -1);
    CHECK(point(32767,32767) == -1); CHECK(point(-32768,-32768) == -1);
    const uint8_t origin[] = {29,40,0,40,0}; vdu(origin,sizeof(origin));
    CHECK(point(80,80) == 2);
    display_byte(26);
    const uint8_t wide_window[]={24,255,255,255,255,255,127,255,127};
    vdu(wide_window,sizeof(wide_window)); CHECK(point(120,120)==2);
    display_byte(26);
    const uint8_t palette[] = {19,2,16,255,128,0}; vdu(palette,sizeof(palette));
    CHECK(video[0xe04] == 0 && video[0xe05] == 0xfc);
    CHECK(point(120,120) == 2);
    /* POINT and stream plotting preserve the alternate arithmetic bank. */
    prepare_keyboard();
    const uint8_t vp[] = {25,69,160,0,160,0}; vdu(vp,sizeof(vp)); check_alternates();
    CHECK(point(160,160) == 2); check_alternates();
    cpu.iff1 = cpu.iff2 = true;
    set_de(0); cpu.a=1; invoke("V_WRITE"); CHECK(cpu.iff1 && cpu.mmu.pages[0] == 0);
    cpu.iff1 = cpu.iff2 = false;
    set_de(0); invoke("V_READ"); CHECK(!cpu.iff1 && cpu.mmu.pages[0] == 0);
    /* Every GCOL action reads the same stored logical pixel. */
    const int expected[] = {1,3,0,3,1};
    for (unsigned action=0;action<5;action++) {
        cpu.a=0; cpu.e=2; invoke("G_COLOUR"); plot(69,400,400);
        cpu.a=action; cpu.e=1; invoke("G_COLOUR"); plot(69,400,400);
        CHECK(point(400,400) == expected[action]);
    }
    invoke("G_CLEAR"); cpu.a=0; cpu.e=1; invoke("G_COLOUR");
    plot(4,80,80); plot(5,80,200); plot(4,200,80); plot(5,200,200);
    plot(77,120,120); CHECK(point(120,120)==1); CHECK(point(40,120)==0);
    invoke("G_CLEAR"); cpu.a=0; cpu.e=1; invoke("G_COLOUR");
    plot(4,0,0); plot(5,80,80);
    vdu(origin,sizeof(origin)); cpu.a=0; cpu.e=2; invoke("G_COLOUR");
    plot(5,120,120); CHECK(point(40,40)==2);
    display_byte(26); cpu.a=0; cpu.e=1; invoke("G_COLOUR");
    plot(5,200,200); CHECK(point(120,120)==2);
    /* Bitmap rows alternate in height. Scroll each row into its own cell
     * rather than applying one fixed pixel offset to the whole window. */
    const uint8_t bw[]={28,0,5,1,2}; vdu(bw,sizeof(bw));
    for (unsigned x=0;x<16;x++) {
        for (unsigned y=12;y<37;y++) video[0x10000+y*320+x]=(y<18 ? 1 : y<25 ? 2 : y<31 ? 3 : 0);
    }
    invoke("D_SCROLL"); CHECK(!basic_error);
    CHECK(video[0x10000+12*320]==2);
    CHECK(video[0x10000+18*320]==3);
    CHECK(video[0x10000+24*320]==3);
    CHECK(video[0x10000+25*320]==0);
    reset("D_MODE"); cpu.a=3; run(); CHECK(!basic_error);
    const uint8_t tw[] = {28,2,2,4,1}; vdu(tw,sizeof(tw));
    display_byte('A'); display_byte('B'); display_byte('C'); display_byte('D');
    CHECK(video[82] == 'A' && video[83] == 'B' && video[84] == 'C' && video[162] == 'D');
    display_byte(10); CHECK(video[82] == 'D' && video[162] == ' ');
    invoke("GETCSR"); CHECK(cpu.e == 0 && cpu.l == 1);
    const uint8_t disabled[] = {21,'X',12,6,'Z'}; vdu(disabled,sizeof(disabled));
    CHECK(video[162] == 'Z' && video[82] == 'D');
    /* Software line input edits and echoes through this display. */
    keys[0]='a'; keys[1]='b'; keys[2]=127; keys[3]='c'; keys[4]=10;
    key_size=5; key_pos=0; set_hl(0xf100); invoke("OSLINE");
    CHECK(!basic_error && !memcmp(memory+0xf100,"ac\n",3));
    CHECK(keyboard_mode == 4);
    reset("V_WRITE"); prepare_keyboard(); inject_interrupt = 0; interrupt_during_video = 1;
    set_de(0); cpu.a=2; invoke("V_WRITE"); check_alternates();
    CHECK(video[0x10000] == 2 && cpu.mmu.pages[2] == 2);
}
static void test_display(void) {
    reset("D_MODE"); cpu.a = 1; run(); CHECK(!basic_error);
    CHECK(video_ports[0x9c] == 3); CHECK(cpu.mmu.pages[0] == 0 && cpu.mmu.pages[2] == 2);
    CHECK(memory[symbol("D_COLS")] == 40); CHECK(memory[symbol("D_ROWS")] == 32);
    CHECK(video[0xe02] == 0 && video[0xe03] == 0xf8);
    CHECK(point(0,0) == 0); CHECK(point(-1,0) == -1);
    plot(69,40,40); CHECK(point(40,40) == 3);
    plot(70,40,40); CHECK(point(40,40) == 0);
    cpu.a = 3; cpu.e = 2; invoke("G_COLOUR"); CHECK(!basic_error);
    plot(69,40,40); CHECK(point(40,40) == 2);
    plot(69,40,40); CHECK(point(40,40) == 0);
    cpu.a = 0; cpu.e = 1; invoke("G_COLOUR");
    plot(4,0,0); plot(5,80,80);
    CHECK(point(0,0) == 1); CHECK(point(80,80) == 1);
    plot(0,4,4); CHECK((memory[symbol("G_X")] | memory[symbol("G_X")+1] << 8) == 84);
    plot(4,0,0); plot(101,20,20); CHECK(point(8,8) == 1);
    display_byte(31); display_byte(5); CHECK(memory[symbol("D_PENDING")] == 1);
    display_byte(10); invoke("GETCSR"); CHECK(cpu.e == 5 && cpu.l == 10);
    display_byte(17); display_byte(2); CHECK(memory[symbol("D_FG")] == 2);
    display_byte(23); display_byte(224);
    for (int i=0;i<8;i++) display_byte(255);
    display_byte(224); CHECK(video[0x10000 + 62*320 + 40] == 2);
    CHECK(memory[symbol("D_GH")] == 6);
    CHECK(video[0x10000 + 68*320 + 40] == 0);
    for (unsigned row=0;row<32;row++) {
        const uint8_t cursor[]={31,0,row}; vdu(cursor,sizeof(cursor));
        invoke("D_CELL"); CHECK(memory[symbol("D_GH")] == 6 || memory[symbol("D_GH")] == 7);
    }
    display_byte(25); display_byte(69); display_byte(160); display_byte(0); display_byte(160); display_byte(0);
    CHECK(point(160,160) == 1);
    display_byte(31); invoke("RESET"); CHECK(memory[symbol("D_PENDING")] == 0);
    invoke("D_EXIT"); CHECK(!basic_error); CHECK(memory[symbol("D_ACTIVE")] == 0);
    CHECK(!memcmp(video+0x3000,default_font,DEFAULT_FONT_SIZE));
    const char *invalid_modes[]={"256\n","65536\n","-1\n"};
    for (unsigned i=0;i<3;i++) {
        reset("MODE"); strcpy((char*)memory+0xf200,invalid_modes[i]); cpu.iy=0xf200;
        run(); CHECK(basic_error==255); CHECK(!video_accesses);
    }
    reset("D_MODE"); cpu.a = 7; run(); CHECK(basic_error == 255); CHECK(!video_accesses);
    reset("D_MODE"); video_ports[0x82] = 0xff; cpu.a = 1; run();
    CHECK(basic_error == 255); CHECK(!video_accesses);
}
static void test_graphics_examples(void) {
    uint8_t program[8192];
    unsigned size=tokenize_source("examples/graphics.bas",program);
    reset("RUN0"); program_error_location();
    /* Runtime workspace is not supplied by the loader and may contain junk. */
    unsigned workspace=symbol("D_ORIGINAL_FONT"), end=symbol("FILE_CHANNELS");
    memset(memory+workspace,0xa5,end-workspace);
    program_error_location();
    memcpy(memory+symbol("USER"),program,size);
    unsigned top=symbol("USER")+size;
    memory[symbol("TOP")]=top; memory[symbol("TOP")+1]=top>>8;
    stop_pc=symbol("OSRDCH"); run(); CHECK(!basic_error); CHECK(cpu.pc==stop_pc);
    CHECK(memory[symbol("D_MODE_NO")]==1); CHECK(point(100,700)==1);
    const char *preview=getenv("BBC_GRAPHICS_PREVIEW");
    if (preview) {
        FILE *fp=fopen(preview,"wb"); assert(fp); fprintf(fp,"P6\n320 200\n255\n");
        for (unsigned i=0;i<64000;i++) {
            unsigned pal=video[0x10000+i]*2+0xe00;
            unsigned colour=video[pal] | video[pal+1]<<8;
            fputc(((colour>>11)&31)*255/31,fp);
            fputc(((colour>>5)&63)*255/63,fp);
            fputc((colour&31)*255/31,fp);
        }
        fclose(fp);
    }
    size=tokenize_source("examples/graphics-modes.bas",program);
    reset("RUN0"); program_error_location(); memcpy(memory+symbol("USER"),program,size);
    top=symbol("USER")+size; memory[symbol("TOP")]=top; memory[symbol("TOP")+1]=top>>8;
    stop_pc=symbol("OSRDCH");
    for (unsigned mode=0;mode<7;mode++) {
        run(); CHECK(!basic_error); CHECK(cpu.pc==stop_pc);
        CHECK(memory[symbol("D_MODE_NO")]==mode);
        keys[key_size++]='x'; z80_step(&cpu);
    }
    stop_pc=symbol("WARM"); run(); CHECK(!basic_error);
}
int main(int argc, char **argv) {
    assert(argc == 3); map_path = argv[2];
    video_io.io_region.read = read_io; video_io.io_region.write = write_io;
    ram.mem_region.read = read_ram; ram.mem_region.write = write_ram;
    FILE *fp = fopen(argv[1], "rb"); assert(fp);
    size_t length = fread(image + 0x4000, 1, 0xc000, fp); fclose(fp); assert(length > 0);
    CHECK(symbol("__tail") <= symbol("USER"));
    CHECK((symbol("USER") & 255) == 0); CHECK((symbol("ACCS") & 255) == 0);
    test_display();
    test_graphics_semantics();
    test_line_raster();
    test_fill_boundary();
    test_video_spans();
    test_glyph_raster();
    test_runtime_video_state();
    test_scaled_coordinates();
    test_text_window_rectangles();
    test_default_palettes();
    test_graphics_examples();
    test_errors();
    test_loads();
    test_validation();
    test_saves();
    test_openout();
    test_openup();
    test_eof();
    test_ext();
    test_close_all();
    test_chain_names();
    test_bundled_loads();
    test_escape();
    test_characters();
    test_lines();
    test_arguments();
    test_commands();
    test_cursor_width();
    test_hamurabi_source();
    test_blackjack_procedure();
    test_irq_vectors();
    printf("PASS: %u adapter regression checks\n", checks);
    return 0;
}
