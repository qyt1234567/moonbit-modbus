///|
/// Contract check result for a request/response pair.
pub(all) enum ContractResult {
  ContractPass
  ContractUnitMismatch
  ContractFunctionMismatch
  ContractLengthMismatch
  ContractDataMismatch
  ContractException
} derive(Debug, Eq)

///|
/// Expected shape of one application data unit.
pub(all) struct FrameContract {
  id : String
  function : Byte
  request_min : Int
  request_max : Int
  response_min : Int
  response_max : Int
  require_echo : Bool
}

///|
pub fn FrameContract::new(
  id : String,
  function : Byte,
  request_min : Int,
  request_max : Int,
  response_min : Int,
  response_max : Int,
  require_echo? : Bool = false,
) -> Result[FrameContract, ModbusError] {
  if id == "" ||
    function == 0 ||
    request_min < 0 ||
    response_min < 0 ||
    request_max < request_min ||
    response_max < response_min {
    return Err(InvalidData)
  }
  Ok({
    id,
    function,
    request_min,
    request_max,
    response_min,
    response_max,
    require_echo,
  })
}

///|
pub fn FrameContract::id(self : FrameContract) -> String {
  self.id
}

///|
pub fn FrameContract::function(self : FrameContract) -> Byte {
  self.function
}

///|
pub fn FrameContract::request_min(self : FrameContract) -> Int {
  self.request_min
}

///|
pub fn FrameContract::request_max(self : FrameContract) -> Int {
  self.request_max
}

///|
pub fn FrameContract::response_min(self : FrameContract) -> Int {
  self.response_min
}

///|
pub fn FrameContract::response_max(self : FrameContract) -> Int {
  self.response_max
}

///|
pub fn FrameContract::require_echo(self : FrameContract) -> Bool {
  self.require_echo
}

///|
/// Validate a response against this function-level contract.
pub fn FrameContract::check(
  self : FrameContract,
  request : Frame,
  response : Frame,
) -> ContractResult {
  if response.is_exception() {
    return ContractException
  }
  if request.unit_id != response.unit_id {
    return ContractUnitMismatch
  }
  if response.pdu.function != self.function {
    return ContractFunctionMismatch
  }
  if request.pdu.data.length() < self.request_min ||
    request.pdu.data.length() > self.request_max {
    return ContractLengthMismatch
  }
  if response.pdu.data.length() < self.response_min ||
    response.pdu.data.length() > self.response_max {
    return ContractLengthMismatch
  }
  if self.require_echo {
    let overlap = if request.pdu.data.length() < response.pdu.data.length() {
      request.pdu.data.length()
    } else {
      response.pdu.data.length()
    }
    for i in 0..<overlap {
      if request.pdu.data[i] != response.pdu.data[i] {
        return ContractDataMismatch
      }
    }
  }
  ContractPass
}

///|
pub fn contract_result_name(result : ContractResult) -> String {
  match result {
    ContractPass => "pass"
    ContractUnitMismatch => "unit-mismatch"
    ContractFunctionMismatch => "function-mismatch"
    ContractLengthMismatch => "length-mismatch"
    ContractDataMismatch => "data-mismatch"
    ContractException => "exception"
  }
}

///|
/// A catalog of frame contracts used by server and gateway adapters.
pub(all) struct FrameContractCatalog {
  contracts : Array[FrameContract]
  max_contracts : Int
}

///|
pub fn FrameContractCatalog::new(
  max_contracts? : Int = 64,
) -> Result[FrameContractCatalog, ModbusError] {
  if max_contracts < 1 {
    Err(InvalidData)
  } else {
    Ok({ contracts: [], max_contracts })
  }
}

///|
pub fn FrameContractCatalog::count(self : FrameContractCatalog) -> Int {
  self.contracts.length()
}

///|
pub fn FrameContractCatalog::add(
  self : FrameContractCatalog,
  contract : FrameContract,
) -> Result[Unit, ModbusError] {
  if self.contracts.length() >= self.max_contracts {
    return Err(CapacityExceeded)
  }
  for existing in self.contracts {
    if existing.id() == contract.id() ||
      existing.function() == contract.function() {
      return Err(InvalidData)
    }
  }
  self.contracts.push(contract)
  Ok(())
}

///|
pub fn FrameContractCatalog::find(
  self : FrameContractCatalog,
  function : Byte,
) -> FrameContract? {
  for contract in self.contracts {
    if contract.function() == function {
      return Some(contract)
    }
  }
  None
}

///|
pub fn FrameContractCatalog::check(
  self : FrameContractCatalog,
  request : Frame,
  response : Frame,
) -> Result[ContractResult, ModbusError] {
  match self.find(request.pdu.function) {
    Some(contract) => Ok(contract.check(request, response))
    None => Err(Unsupported)
  }
}

///|
/// Check all known standard functions and return the first failure.
pub fn FrameContractCatalog::check_all(
  self : FrameContractCatalog,
  pairs : Array[(Frame, Frame)],
) -> Array[ContractResult] {
  let result : Array[ContractResult] = []
  for pair in pairs {
    match self.check(pair.0, pair.1) {
      Ok(value) => result.push(value)
      Err(_) => result.push(ContractFunctionMismatch)
    }
  }
  result
}

///|
/// Build a conservative catalog for the common Modbus function codes.
pub fn standard_frame_contracts() -> FrameContractCatalog {
  let catalog = match FrameContractCatalog::new() {
    Ok(value) => value
    Err(_) => panic()
  }
  let definitions : Array[FrameContract] = [
    frame_contract_or_panic(FrameContract::new("read-coils", 1, 4, 4, 1, 250)),
    frame_contract_or_panic(
      FrameContract::new("read-discrete-inputs", 2, 4, 4, 1, 250),
    ),
    frame_contract_or_panic(FrameContract::new("read-holding", 3, 4, 4, 1, 250)),
    frame_contract_or_panic(FrameContract::new("read-input", 4, 4, 4, 1, 250)),
    frame_contract_or_panic(
      FrameContract::new("write-coil", 5, 4, 4, 4, 4, require_echo=true),
    ),
    frame_contract_or_panic(
      FrameContract::new("write-register", 6, 4, 4, 4, 4, require_echo=true),
    ),
    frame_contract_or_panic(FrameContract::new("write-coils", 15, 5, 255, 4, 4)),
    frame_contract_or_panic(
      FrameContract::new("write-registers", 16, 6, 251, 4, 4),
    ),
  ]
  for contract in definitions {
    ignore(catalog.add(contract))
  }
  catalog
}

///|
fn frame_contract_or_panic(
  result : Result[FrameContract, ModbusError],
) -> FrameContract {
  match result {
    Ok(value) => value
    Err(_) => panic()
  }
}
