#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>

#include <chrono>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr uint32_t CSR_CTRL = 0x0000;
constexpr uint32_t CSR_PC = 0x0004;
constexpr uint32_t CSR_STATUS = 0x0008;
constexpr uint32_t CSR_FAULT_CODE = 0x000c;
constexpr uint32_t CSR_FAULT_PC = 0x0010;
constexpr uint32_t CSR_FAULT_META = 0x0014;
constexpr uint32_t CSR_CAP_MAGIC = 0x0020;
constexpr uint32_t CSR_CAP_VERSION = 0x0024;
constexpr uint32_t CSR_CAP_GEOMETRY = 0x0028;
constexpr uint32_t CSR_CAP_FEATURES = 0x002c;
constexpr uint32_t IMEM_WINDOW = 0x1000;

constexpr uint32_t CAP_MAGIC_EXPECTED = 0xaec06001u;
constexpr uint32_t CAP_VERSION_EXPECTED = 0x00010000u;
constexpr uint32_t CAP_GEOMETRY_EXPECTED = 0x04040820u;
constexpr uint32_t CAP_FEATURES_REQUIRED = 0x000007ffu;

std::vector<uint8_t> read_binary(const std::string& path) {
  std::ifstream f(path, std::ios::binary);
  if (!f) {
    throw std::runtime_error("failed to open " + path);
  }
  f.seekg(0, std::ios::end);
  const auto size = f.tellg();
  if (size < 0) {
    throw std::runtime_error("failed to size " + path);
  }
  f.seekg(0, std::ios::beg);
  std::vector<uint8_t> data(static_cast<size_t>(size));
  if (!data.empty()) {
    f.read(reinterpret_cast<char*>(data.data()), static_cast<std::streamsize>(data.size()));
  }
  if (!f && !data.empty()) {
    throw std::runtime_error("failed to read " + path);
  }
  return data;
}

uint32_t load_u32_le(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) |
         (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

void write_reg(xrt::kernel& kernel, uint32_t offset, uint32_t value) {
  kernel.write_register(offset, value);
}

uint32_t read_reg(const xrt::kernel& kernel, uint32_t offset) {
  return kernel.read_register(offset);
}

void require_capability(xrt::kernel& kernel) {
  const uint32_t magic = read_reg(kernel, CSR_CAP_MAGIC);
  const uint32_t version = read_reg(kernel, CSR_CAP_VERSION);
  const uint32_t geometry = read_reg(kernel, CSR_CAP_GEOMETRY);
  const uint32_t features = read_reg(kernel, CSR_CAP_FEATURES);

  if (magic != CAP_MAGIC_EXPECTED) {
    throw std::runtime_error("AEC capability magic mismatch");
  }
  if (version != CAP_VERSION_EXPECTED) {
    throw std::runtime_error("AEC capability version mismatch");
  }
  if (geometry != CAP_GEOMETRY_EXPECTED) {
    throw std::runtime_error("AEC geometry mismatch");
  }
  if ((features & CAP_FEATURES_REQUIRED) != CAP_FEATURES_REQUIRED) {
    throw std::runtime_error("AEC required capability bits are missing");
  }
}

void load_aecbin_to_imem(xrt::kernel& kernel, const std::string& aecbin_path) {
  const auto bin = read_binary(aecbin_path);
  if (bin.empty() || (bin.size() % 16) != 0) {
    throw std::runtime_error(".aecbin must be non-empty and 128-bit aligned");
  }
  if (bin.size() > 4096) {
    throw std::runtime_error(".aecbin exceeds current 0x1000..0x1fff IMEM host window");
  }

  for (size_t word = 0; word < bin.size() / 4; ++word) {
    const uint32_t value = load_u32_le(&bin[word * 4]);
    write_reg(kernel, IMEM_WINDOW + static_cast<uint32_t>(word * 4), value);
  }
}

void poll_done_or_fault(xrt::kernel& kernel, uint32_t timeout_ms) {
  const auto start = std::chrono::steady_clock::now();
  while (true) {
    const uint32_t status = read_reg(kernel, CSR_STATUS);
    if (status & 0x4u) {
      const uint32_t code = read_reg(kernel, CSR_FAULT_CODE);
      const uint32_t pc = read_reg(kernel, CSR_FAULT_PC);
      const uint32_t meta = read_reg(kernel, CSR_FAULT_META);
      std::cerr << "AEC fault: code=0x" << std::hex << code
                << " pc=0x" << pc << " meta=0x" << meta << std::dec << "\n";
      throw std::runtime_error("kernel reported FAULT");
    }
    if (status & 0x2u) {
      return;
    }
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start);
    if (elapsed.count() > timeout_ms) {
      throw std::runtime_error("timeout waiting for DONE");
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}

}  // namespace

int main(int argc, char** argv) {
  try {
    if (argc < 2 || argc > 5) {
      std::cerr << "usage: " << argv[0] << " <xclbin> [device_index] [aecbin] [pc]\n";
      return 2;
    }

    const std::string xclbin_path = argv[1];
    const int device_index = (argc >= 3) ? std::stoi(argv[2]) : 0;
    const std::string aecbin_path = (argc >= 4) ? argv[3] : std::string();
    const uint32_t pc = (argc >= 5) ? static_cast<uint32_t>(std::stoul(argv[4], nullptr, 0)) : 0u;

    xrt::device device(device_index);
    auto uuid = device.load_xclbin(xclbin_path);
    xrt::kernel kernel(device, uuid, "aec_gpgpu:{aec_gpgpu_1}");

    require_capability(kernel);

    constexpr size_t gmem_bytes = 64 * 1024 * 1024;
    xrt::bo gmem0_bo(device, gmem_bytes, kernel.group_id(0));
    xrt::bo gmem1_bo(device, gmem_bytes, kernel.group_id(1));
    xrt::bo gmem2_bo(device, gmem_bytes, kernel.group_id(2));
    xrt::bo gmem3_bo(device, gmem_bytes, kernel.group_id(3));
    std::memset(gmem0_bo.map<void*>(), 0, gmem_bytes);
    std::memset(gmem1_bo.map<void*>(), 0, gmem_bytes);
    std::memset(gmem2_bo.map<void*>(), 0, gmem_bytes);
    std::memset(gmem3_bo.map<void*>(), 0, gmem_bytes);
    gmem0_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    gmem1_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    gmem2_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    gmem3_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    if (!aecbin_path.empty()) {
      load_aecbin_to_imem(kernel, aecbin_path);
    }

    write_reg(kernel, CSR_PC, pc);
    write_reg(kernel, CSR_CTRL, 0x1u);
    poll_done_or_fault(kernel, 60000);

    gmem0_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
    gmem1_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
    gmem2_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
    gmem3_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
    std::cout << "AEC XRT host completed successfully\n";
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "AEC XRT host error: " << e.what() << "\n";
    return 1;
  }
}
