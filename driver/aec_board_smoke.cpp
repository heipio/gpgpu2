#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>

#include <chrono>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr uint32_t kCsrCtrl = 0x0000;
constexpr uint32_t kCsrPc = 0x0004;
constexpr uint32_t kCsrStatus = 0x0008;
constexpr uint32_t kCsrFaultCode = 0x000c;
constexpr uint32_t kCsrFaultPc = 0x0010;
constexpr uint32_t kCsrFaultMeta = 0x0014;
constexpr uint32_t kCsrCapMagic = 0x0020;
constexpr uint32_t kCsrCapVersion = 0x0024;
constexpr uint32_t kCsrCapGeometry = 0x0028;
constexpr uint32_t kCsrCapFeatures = 0x002c;
constexpr uint32_t kImemWindow = 0x1000;

constexpr uint32_t kCapMagic = 0xaec06001u;
constexpr uint32_t kCapVersion = 0x00010000u;
constexpr uint32_t kCapGeometry = 0x04040820u;
constexpr uint32_t kCapFeatures = 0x000007ffu;
constexpr size_t kBoBytes = 64 * 1024;
constexpr size_t kWordOffset = 0x1000 / sizeof(uint32_t);
constexpr uint32_t kTimeoutMs = 5000;

struct Options {
  std::string xclbin;
  int device_index = -1;
  std::string aecbin;
  uint32_t iterations = 1;
  uint32_t duration_seconds = 0;
  uint32_t timeout_ms = kTimeoutMs;
};

std::vector<uint8_t> read_binary(const std::string& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("cannot open " + path);
  input.seekg(0, std::ios::end);
  const std::streamoff size = input.tellg();
  if (size <= 0 || (size % 16) != 0 || size > 4096) {
    throw std::runtime_error("aecbin must be 16-byte aligned and fit the IMEM window");
  }
  input.seekg(0, std::ios::beg);
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  input.read(reinterpret_cast<char*>(bytes.data()), size);
  if (!input) throw std::runtime_error("cannot read " + path);
  return bytes;
}

uint32_t read_u32_le(const uint8_t* data) {
  return static_cast<uint32_t>(data[0]) |
         (static_cast<uint32_t>(data[1]) << 8) |
         (static_cast<uint32_t>(data[2]) << 16) |
         (static_cast<uint32_t>(data[3]) << 24);
}

void write_reg(xrt::kernel& kernel, uint32_t address, uint32_t value) {
  kernel.write_register(address, value);
}

uint32_t read_reg(const xrt::kernel& kernel, uint32_t address) {
  return kernel.read_register(address);
}

void require_capability(xrt::kernel& kernel) {
  const uint32_t magic = read_reg(kernel, kCsrCapMagic);
  const uint32_t version = read_reg(kernel, kCsrCapVersion);
  const uint32_t geometry = read_reg(kernel, kCsrCapGeometry);
  const uint32_t features = read_reg(kernel, kCsrCapFeatures);
  if (magic != kCapMagic || version != kCapVersion || geometry != kCapGeometry ||
      (features & kCapFeatures) != kCapFeatures) {
    std::cerr << "AEC capability readback magic=0x" << std::hex << magic
              << " version=0x" << version << " geometry=0x" << geometry
              << " features=0x" << features << std::dec << "\n";
    throw std::runtime_error("AEC capability register mismatch");
  }
}

void load_imem(xrt::kernel& kernel, const std::vector<uint8_t>& aecbin) {
  for (size_t word = 0; word < aecbin.size() / 4; ++word) {
    write_reg(kernel, kImemWindow + static_cast<uint32_t>(word * 4),
              read_u32_le(&aecbin[word * 4]));
  }
}

void wait_for_done(xrt::kernel& kernel, uint32_t timeout_ms) {
  const auto started = std::chrono::steady_clock::now();
  while (true) {
    const uint32_t status = read_reg(kernel, kCsrStatus);
    if ((status & 0x4u) != 0) {
      throw std::runtime_error("AEC fault code=" +
          std::to_string(read_reg(kernel, kCsrFaultCode)) + " pc=" +
          std::to_string(read_reg(kernel, kCsrFaultPc)) + " meta=" +
          std::to_string(read_reg(kernel, kCsrFaultMeta)));
    }
    if ((status & 0x2u) != 0) return;
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - started);
    if (elapsed.count() > timeout_ms) throw std::runtime_error("timeout waiting for DONE");
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}

Options parse_options(int argc, char** argv) {
  if (argc < 4) {
    throw std::runtime_error(
        "usage: aec_board_smoke <xclbin> <device-index> <aecbin> "
        "[--iterations N] [--duration-seconds N] [--timeout-ms N]");
  }
  Options options;
  options.xclbin = argv[1];
  options.device_index = std::stoi(argv[2]);
  options.aecbin = argv[3];
  for (int i = 4; i < argc; i += 2) {
    if (i + 1 >= argc) throw std::runtime_error("missing value for option " + std::string(argv[i]));
    const std::string key = argv[i];
    const uint32_t value = static_cast<uint32_t>(std::stoul(argv[i + 1], nullptr, 0));
    if (key == "--iterations") options.iterations = value;
    else if (key == "--duration-seconds") options.duration_seconds = value;
    else if (key == "--timeout-ms") options.timeout_ms = value;
    else throw std::runtime_error("unknown option " + key);
  }
  if (options.iterations == 0 || options.timeout_ms == 0) throw std::runtime_error("zero is not valid here");
  return options;
}

void seed_bo(xrt::bo& bo, uint32_t sentinel, uint32_t value) {
  std::memset(bo.map<void*>(), 0, kBoBytes);
  uint32_t* words = bo.map<uint32_t*>();
  words[0] = sentinel;
  words[kWordOffset] = value;
  bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
}

uint32_t read_bo_word(xrt::bo& bo, size_t word_index) {
  bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
  return bo.map<uint32_t*>()[word_index];
}

void run_iteration(xrt::kernel& kernel, xrt::bo& bank0, xrt::bo& bank1,
                   xrt::bo& bank2, xrt::bo& bank3, uint32_t iteration,
                   uint32_t timeout_ms) {
  const uint32_t input_a = 0xdeadbeefu ^ iteration;
  const uint32_t input_b = 0x10203040u + iteration;
  const uint32_t expected = input_a + input_b;
  const uint32_t sentinels[4] = {0x16000000u ^ iteration, 0x17000000u ^ iteration,
                                 0x18000000u ^ iteration, 0x19000000u ^ iteration};

  seed_bo(bank0, sentinels[0], input_a);
  seed_bo(bank1, sentinels[1], input_b);
  seed_bo(bank2, sentinels[2], 0u);
  seed_bo(bank3, sentinels[3], 0u);

  write_reg(kernel, kCsrPc, 0u);
  write_reg(kernel, kCsrCtrl, 0x1u);
  wait_for_done(kernel, timeout_ms);

  const uint32_t observed[4] = {
      read_bo_word(bank0, 0), read_bo_word(bank1, 0),
      read_bo_word(bank2, 0), read_bo_word(bank3, 0)};
  for (unsigned bank = 0; bank < 4; ++bank) {
    if (observed[bank] != sentinels[bank]) {
      throw std::runtime_error("DMA sentinel mismatch on HBM bank slot " + std::to_string(bank));
    }
  }
  if (read_bo_word(bank0, kWordOffset) != input_a ||
      read_bo_word(bank1, kWordOffset) != input_b ||
      read_bo_word(bank2, kWordOffset) != expected ||
      read_bo_word(bank3, kWordOffset) != expected) {
    throw std::runtime_error("GPU HBM LD/ADD/ST result mismatch at iteration " +
                             std::to_string(iteration));
  }
}
}  // namespace

int main(int argc, char** argv) {
  try {
    const Options options = parse_options(argc, argv);
    const std::vector<uint8_t> aecbin = read_binary(options.aecbin);
    xrt::device device(options.device_index);
    const auto uuid = device.load_xclbin(options.xclbin);
    // Direct CSR/IMEM accesses require exclusive CU ownership in XRT 2022.1.
    xrt::kernel kernel(device, uuid, "aec_gpgpu:{aec_gpgpu_1}",
                       xrt::kernel::cu_access_mode::exclusive);
    require_capability(kernel);

    xrt::bo bank0(device, kBoBytes, kernel.group_id(0));
    xrt::bo bank1(device, kBoBytes, kernel.group_id(1));
    xrt::bo bank2(device, kBoBytes, kernel.group_id(2));
    xrt::bo bank3(device, kBoBytes, kernel.group_id(3));
    std::cout << "AEC board smoke groups: " << kernel.group_id(0) << ","
              << kernel.group_id(1) << "," << kernel.group_id(2) << ","
              << kernel.group_id(3) << "\n";
    load_imem(kernel, aecbin);

    const auto started = std::chrono::steady_clock::now();
    uint32_t completed = 0;
    do {
      run_iteration(kernel, bank0, bank1, bank2, bank3, completed, options.timeout_ms);
      ++completed;
    } while (completed < options.iterations ||
             (options.duration_seconds != 0 &&
              std::chrono::duration_cast<std::chrono::seconds>(
                  std::chrono::steady_clock::now() - started).count() < options.duration_seconds));

    std::cout << "AEC BOARD SMOKE PASSED iterations=" << completed << "\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "AEC BOARD SMOKE FAILED: " << error.what() << "\n";
    return 1;
  }
}
