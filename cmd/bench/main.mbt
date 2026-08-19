///|
fn print_result(result : @moonbit-modbus.BenchmarkResult) -> Unit {
  println(
    result.summary() + " success_rate=" + result.success_rate().to_string(),
  )
}

///|
fn main {
  let iterations = 1000
  println("moonbit-modbus benchmark")
  println("tool=MoonBit deterministic protocol workload")
  match @moonbit-modbus.benchmark_suite(iterations) {
    Ok(results) =>
      for result in results {
        print_result(result)
      }
    Err(_) => println("benchmark failed")
  }
}
