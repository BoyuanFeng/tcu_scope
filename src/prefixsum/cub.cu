#define CUB_HALF_OPTIMIZATION 1

#include <benchmark/benchmark.h>

#include "init/init.hpp"
#include "prefixsum/args.hpp"
#include "utils/utils.hpp"

#include <cub/cub.cuh>

using namespace cub;

static void CUB_FULL_PREFIXSUM(benchmark::State &state) {
  const size_t num_elements = state.range(0);

  half *d_in_fp16 = nullptr;
  half *d_out     = nullptr;
  cudaEvent_t start, stop;

  void *d_temp_storage      = NULL;
  size_t temp_storage_bytes = 0;

  try {
    PRINT_IF_ERROR(cudaMalloc(&d_in_fp16, num_elements * sizeof(half)));
    PRINT_IF_ERROR(cudaMalloc(&d_out, 1 * sizeof(half)));

    cuda_memory_set(d_in_fp16, 0.001f, num_elements);

    PRINT_IF_ERROR(cudaDeviceSynchronize());

    PRINT_IF_ERROR(DeviceScan::ExclusiveSum(d_temp_storage, temp_storage_bytes, d_in_fp16,
                                            d_out, num_elements));
    PRINT_IF_ERROR(cudaMalloc(&d_temp_storage, temp_storage_bytes));

    PRINT_IF_ERROR(cudaEventCreate(&start));
    PRINT_IF_ERROR(cudaEventCreate(&stop));

    defer(cudaEventDestroy(start));
    defer(cudaEventDestroy(stop));

    for (auto _ : state) {
      PRINT_IF_ERROR(cudaEventRecord(start));

      PRINT_IF_ERROR(DeviceScan::InclusiveSum(d_temp_storage, temp_storage_bytes,
                                              d_in_fp16, d_out, num_elements));

      PRINT_IF_ERROR(cudaEventRecord(stop));
      PRINT_IF_ERROR(cudaEventSynchronize(stop));

      state.PauseTiming();

      float msecTotal = 0.0f;
      PRINT_IF_ERROR(cudaEventElapsedTime(&msecTotal, start, stop));
      state.SetIterationTime(msecTotal / 1000);
      state.ResumeTiming();
    }

    state.counters.insert({{"num_elements", num_elements},
                           {"flops",
                            {state.iterations() * 1.0 * num_elements,
                             benchmark::Counter::kAvgThreadsRate}}});

#if 0
  half *h_out = new half[num_elements];
  PRINT_IF_ERROR(cudaMemcpy(h_out, d_out, num_elements * sizeof(half), cudaMemcpyDeviceToHost));

  int errors        = 0;
  float correct_sum = 0;
  for (int i = 0; i < num_elements; i++) {
    correct_sum += h_in[i];
    if (fabs(half_to_float((h_out[i])) - correct_sum) > 0.01) {
      errors++;
      printf("Expected %f, get h_out[%d] = %f\n", correct_sum, i, half_to_float(h_out[i]));
    }
  }

  if (errors > 0) {
    printf("CUB_FULL_PREFIXSUM does not agree with SEQUENTIAL! %d errors!\n", errors);
  } else {
    printf("Results verified: they agree.\n\n");
  }

  delete h_out;
#endif
    cudaFree(d_in_fp16);
    cudaFree(d_out);
    cudaFree(d_temp_storage);
  } catch (...) {
    cudaFree(d_in_fp16);
    cudaFree(d_out);
    cudaFree(d_temp_storage);

    cudaDeviceReset();
    const auto p = std::current_exception();
    std::rethrow_exception(p);
  }
}

BENCHMARK(CUB_FULL_PREFIXSUM)->ARGS()->UseManualTime();
