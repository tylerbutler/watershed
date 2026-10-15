//// Decode bounded LZ4 frames.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

const magic = 0x184D2204

const history_bytes = 65_535

const output_chunk_bytes = 4096

const uint32_modulus = 4_294_967_296

const prime1 = 2_654_435_761

const prime2 = 2_246_822_519

const prime3 = 3_266_489_917

const prime4 = 668_265_263

const prime5 = 374_761_393

pub type Error {
  InvalidFrame
  UnsupportedFrameFeature(String)
  InvalidChecksum
  InvalidMatch
  OutputLimitExceeded
}

type Header {
  Header(
    offset: Int,
    block_independent: Bool,
    block_checksum: Bool,
    content_checksum: Bool,
    content_size: Option(Int),
    max_block_bytes: Int,
  )
}

type Output {
  Output(
    total: Int,
    current_reversed: List(Int),
    current_length: Int,
    chunks_reversed: List(BitArray),
    history: Dict(Int, BitArray),
    first_history_chunk: Int,
    block_start: Int,
  )
}

type SequenceStep {
  BlockDone(Output)
  SequenceContinue(offset: Int, output: Output)
}

/// Decode one LZ4 frame and refuse output above the supplied byte limit.
pub fn decompress(
  frame: BitArray,
  max_output_bytes: Int,
) -> Result(BitArray, Error) {
  case max_output_bytes < 0 {
    True -> Error(OutputLimitExceeded)
    False -> {
      use header <- result.try(read_header(frame, max_output_bytes))
      let output =
        Output(
          total: 0,
          current_reversed: [],
          current_length: 0,
          chunks_reversed: [],
          history: dict.new(),
          first_history_chunk: 0,
          block_start: 0,
        )
      use #(output, offset) <- result.try(read_blocks(
        frame,
        header,
        output,
        max_output_bytes,
      ))
      use offset <- result.try(validate_content_checksum(
        frame,
        offset,
        output,
        header.content_checksum,
      ))
      use _ <- result.try(case offset == bit_array.byte_size(frame) {
        True -> Ok(Nil)
        False -> Error(InvalidFrame)
      })
      use _ <- result.try(case header.content_size {
        None -> Ok(Nil)
        Some(size) if size == output.total -> Ok(Nil)
        Some(_) -> Error(InvalidFrame)
      })
      Ok(output_bytes(output))
    }
  }
}

fn read_header(
  frame: BitArray,
  max_output_bytes: Int,
) -> Result(Header, Error) {
  use found_magic <- result.try(read_u32(frame, 0))
  use _ <- result.try(case found_magic == magic {
    True -> Ok(Nil)
    False -> Error(InvalidFrame)
  })
  use flg <- result.try(read_u8(frame, 4))
  use bd <- result.try(read_u8(frame, 5))
  use _ <- result.try(validate_flags(flg, bd))
  let has_content_size = int.bitwise_and(flg, 0x08) != 0
  let has_dictionary = int.bitwise_and(flg, 0x01) != 0
  use #(content_size, offset) <- result.try(case has_content_size {
    False -> Ok(#(None, 6))
    True -> {
      use size <- result.try(read_content_size(frame, 6, max_output_bytes))
      Ok(#(Some(size), 14))
    }
  })
  use _ <- result.try(case has_dictionary {
    True -> Error(UnsupportedFrameFeature("dictionary id"))
    False -> Ok(Nil)
  })
  use checksum <- result.try(read_u8(frame, offset))
  use descriptor <- result.try(slice(frame, 4, offset - 4))
  use _ <- result.try(
    case logical_right(xxhash32(descriptor), 8) % 256 == checksum {
      True -> Ok(Nil)
      False -> Error(InvalidChecksum)
    },
  )
  let block_code = logical_right(bd, 4) % 8
  let max_block_bytes = case block_code {
    4 -> 64 * 1024
    5 -> 256 * 1024
    6 -> 1024 * 1024
    _ -> 4 * 1024 * 1024
  }
  Ok(Header(
    offset: offset + 1,
    block_independent: int.bitwise_and(flg, 0x20) != 0,
    block_checksum: int.bitwise_and(flg, 0x10) != 0,
    content_checksum: int.bitwise_and(flg, 0x04) != 0,
    content_size: content_size,
    max_block_bytes: max_block_bytes,
  ))
}

fn validate_flags(flg: Int, bd: Int) -> Result(Nil, Error) {
  let version = logical_right(flg, 6) % 4
  let block_code = logical_right(bd, 4) % 8
  case
    version == 1,
    int.bitwise_and(flg, 0x02) == 0,
    int.bitwise_and(bd, 0x8F) == 0,
    block_code >= 4 && block_code <= 7
  {
    True, True, True, True -> Ok(Nil)
    _, _, _, _ -> Error(InvalidFrame)
  }
}

fn read_content_size(
  frame: BitArray,
  offset: Int,
  max_output_bytes: Int,
) -> Result(Int, Error) {
  use low <- result.try(read_u32(frame, offset))
  use high <- result.try(read_u32(frame, offset + 4))
  case high > 0 || low > max_output_bytes {
    True -> Error(OutputLimitExceeded)
    False -> Ok(low)
  }
}

fn read_blocks(
  frame: BitArray,
  header: Header,
  output: Output,
  max_output_bytes: Int,
) -> Result(#(Output, Int), Error) {
  case read_u32(frame, header.offset) {
    Error(error) -> Error(error)
    Ok(0) -> Ok(#(output, header.offset + 4))
    Ok(raw_size) ->
      case read_block(frame, header, output, raw_size, max_output_bytes) {
        Error(error) -> Error(error)
        Ok(#(decoded, next_offset)) ->
          read_blocks(
            frame,
            Header(..header, offset: next_offset),
            decoded,
            max_output_bytes,
          )
      }
  }
}

fn read_block(
  frame: BitArray,
  header: Header,
  output: Output,
  raw_size: Int,
  max_output_bytes: Int,
) -> Result(#(Output, Int), Error) {
  let uncompressed = int.bitwise_and(raw_size, 0x80000000) != 0
  let block_size = int.bitwise_and(raw_size, 0x7FFFFFFF)
  use _ <- result.try(
    case block_size > 0 && block_size <= header.max_block_bytes {
      True -> Ok(Nil)
      False -> Error(InvalidFrame)
    },
  )
  use _ <- result.try(case uncompressed {
    True -> check_output_limit(output.total, block_size, max_output_bytes)
    False -> Ok(Nil)
  })
  let block_offset = header.offset + 4
  use block <- result.try(slice(frame, block_offset, block_size))
  use next_offset <- result.try(validate_block_checksum(
    frame,
    block_offset + block_size,
    block,
    header.block_checksum,
  ))
  let output = case header.block_independent {
    True -> Output(..output, block_start: output.total)
    False -> output
  }
  let block_output_limit =
    int.min(max_output_bytes, output.total + header.max_block_bytes)
  use decoded <- result.try(case uncompressed {
    True -> append_literal_bytes(output, block, max_output_bytes)
    False ->
      case decode_block(block, output, block_output_limit) {
        Error(OutputLimitExceeded)
          if output.total + header.max_block_bytes < max_output_bytes
        -> Error(InvalidFrame)
        result -> result
      }
  })
  use _ <- result.try(
    case decoded.total - output.total <= header.max_block_bytes {
      True -> Ok(Nil)
      False -> Error(InvalidFrame)
    },
  )
  Ok(#(decoded, next_offset))
}

fn validate_block_checksum(
  frame: BitArray,
  offset: Int,
  block: BitArray,
  enabled: Bool,
) -> Result(Int, Error) {
  case enabled {
    False -> Ok(offset)
    True -> {
      use expected <- result.try(read_u32(frame, offset))
      case expected == xxhash32(block) {
        True -> Ok(offset + 4)
        False -> Error(InvalidChecksum)
      }
    }
  }
}

fn validate_content_checksum(
  frame: BitArray,
  offset: Int,
  output: Output,
  enabled: Bool,
) -> Result(Int, Error) {
  case enabled {
    False -> Ok(offset)
    True -> {
      use expected <- result.try(read_u32(frame, offset))
      case expected == xxhash32(output_bytes(output)) {
        True -> Ok(offset + 4)
        False -> Error(InvalidChecksum)
      }
    }
  }
}

fn decode_block(
  block: BitArray,
  output: Output,
  max_output_bytes: Int,
) -> Result(Output, Error) {
  decode_sequences(block, 0, output, max_output_bytes)
}

fn decode_sequences(
  block: BitArray,
  offset: Int,
  output: Output,
  max_output_bytes: Int,
) -> Result(Output, Error) {
  case offset == bit_array.byte_size(block) {
    True -> Ok(output)
    False ->
      case decode_sequence(block, offset, output, max_output_bytes) {
        Error(error) -> Error(error)
        Ok(BlockDone(output)) -> Ok(output)
        Ok(SequenceContinue(offset, output)) ->
          decode_sequences(block, offset, output, max_output_bytes)
      }
  }
}

fn decode_sequence(
  block: BitArray,
  initial_offset: Int,
  initial_output: Output,
  max_output_bytes: Int,
) -> Result(SequenceStep, Error) {
  use token <- result.try(read_u8(block, initial_offset))
  use #(literal_length, literal_offset) <- result.try(extended_length(
    block,
    initial_offset + 1,
    logical_right(token, 4),
  ))
  use _ <- result.try(check_output_limit(
    initial_output.total,
    literal_length,
    max_output_bytes,
  ))
  use literals <- result.try(slice(block, literal_offset, literal_length))
  use output <- result.try(append_literal_bytes(
    initial_output,
    literals,
    max_output_bytes,
  ))
  let offset = literal_offset + literal_length
  case offset == bit_array.byte_size(block) {
    True -> Ok(BlockDone(output))
    False -> {
      use match_offset <- result.try(read_u16(block, offset))
      use _ <- result.try(case match_offset > 0 {
        True -> Ok(Nil)
        False -> Error(InvalidMatch)
      })
      use #(match_extra, offset) <- result.try(extended_length(
        block,
        offset + 2,
        int.bitwise_and(token, 0x0F),
      ))
      use output <- result.try(append_match(
        output,
        match_offset,
        match_extra + 4,
        max_output_bytes,
      ))
      Ok(SequenceContinue(offset, output))
    }
  }
}

fn extended_length(
  bytes: BitArray,
  offset: Int,
  base: Int,
) -> Result(#(Int, Int), Error) {
  case base == 15 {
    False -> Ok(#(base, offset))
    True -> extend_length(bytes, offset, 15)
  }
}

fn extend_length(
  bytes: BitArray,
  offset: Int,
  length: Int,
) -> Result(#(Int, Int), Error) {
  case read_u8(bytes, offset) {
    Error(error) -> Error(error)
    Ok(next) -> {
      let length = length + next
      case next == 255 {
        True -> extend_length(bytes, offset + 1, length)
        False -> Ok(#(length, offset + 1))
      }
    }
  }
}

fn append_literal_bytes(
  output: Output,
  bytes: BitArray,
  max_output_bytes: Int,
) -> Result(Output, Error) {
  let count = bit_array.byte_size(bytes)
  use _ <- result.try(check_output_limit(output.total, count, max_output_bytes))
  append_literal_loop(output, bytes, 0)
}

fn append_literal_loop(
  output: Output,
  bytes: BitArray,
  offset: Int,
) -> Result(Output, Error) {
  case offset == bit_array.byte_size(bytes) {
    True -> Ok(output)
    False ->
      case read_u8(bytes, offset) {
        Error(error) -> Error(error)
        Ok(byte) ->
          append_literal_loop(append_byte(output, byte), bytes, offset + 1)
      }
  }
}

fn append_match(
  output: Output,
  offset: Int,
  length: Int,
  max_output_bytes: Int,
) -> Result(Output, Error) {
  use _ <- result.try(check_output_limit(output.total, length, max_output_bytes))
  case offset > output.total - output.block_start || offset > history_bytes {
    True -> Error(InvalidMatch)
    False -> append_match_loop(output, offset, length)
  }
}

fn append_match_loop(
  output: Output,
  offset: Int,
  remaining: Int,
) -> Result(Output, Error) {
  case remaining {
    0 -> Ok(output)
    _ ->
      case output_byte(output, output.total - offset) {
        Error(error) -> Error(error)
        Ok(byte) ->
          append_match_loop(append_byte(output, byte), offset, remaining - 1)
      }
  }
}

fn check_output_limit(
  current: Int,
  additional: Int,
  max_output_bytes: Int,
) -> Result(Nil, Error) {
  case additional > max_output_bytes - current {
    True -> Error(OutputLimitExceeded)
    False -> Ok(Nil)
  }
}

fn append_byte(output: Output, byte: Int) -> Output {
  let output = case output.current_length == output_chunk_bytes {
    True -> seal_current(output)
    False -> output
  }
  Output(
    ..output,
    total: output.total + 1,
    current_reversed: [byte, ..output.current_reversed],
    current_length: output.current_length + 1,
  )
}

fn seal_current(output: Output) -> Output {
  let chunk = reversed_bytes(output.current_reversed)
  let chunk_index = output.total / output_chunk_bytes - 1
  let history = dict.insert(output.history, chunk_index, chunk)
  let retained_chunks =
    { history_bytes + output_chunk_bytes - 1 } / output_chunk_bytes
  let first_history_chunk = chunk_index - retained_chunks + 1
  let history = case first_history_chunk > output.first_history_chunk {
    True -> dict.delete(history, output.first_history_chunk)
    False -> history
  }
  Output(
    ..output,
    current_reversed: [],
    current_length: 0,
    chunks_reversed: [chunk, ..output.chunks_reversed],
    history: history,
    first_history_chunk: int.max(first_history_chunk, 0),
  )
}

fn output_byte(output: Output, position: Int) -> Result(Int, Error) {
  let current_start = output.total - output.current_length
  case position >= current_start {
    True ->
      output.current_reversed
      |> list_byte(output.total - position - 1)
    False -> {
      let chunk_index = position / output_chunk_bytes
      let in_chunk = position % output_chunk_bytes
      use chunk <- result.try(
        dict.get(output.history, chunk_index)
        |> result.map_error(fn(_) { InvalidMatch }),
      )
      read_u8(chunk, in_chunk)
      |> result.map_error(fn(_) { InvalidMatch })
    }
  }
}

fn list_byte(bytes: List(Int), index: Int) -> Result(Int, Error) {
  case bytes, index {
    [byte, ..], 0 -> Ok(byte)
    [_, ..rest], index if index > 0 -> list_byte(rest, index - 1)
    _, _ -> Error(InvalidMatch)
  }
}

fn output_bytes(output: Output) -> BitArray {
  let current = reversed_bytes(output.current_reversed)
  [current, ..output.chunks_reversed]
  |> list.reverse()
  |> bit_array.concat()
}

fn reversed_bytes(bytes: List(Int)) -> BitArray {
  bytes
  |> list.reverse()
  |> list.map(fn(byte) { <<byte>> })
  |> bit_array.concat()
}

fn read_u8(bytes: BitArray, offset: Int) -> Result(Int, Error) {
  use value <- result.try(slice(bytes, offset, 1))
  case value {
    <<byte>> -> Ok(byte)
    _ -> Error(InvalidFrame)
  }
}

fn read_u16(bytes: BitArray, offset: Int) -> Result(Int, Error) {
  use low <- result.try(read_u8(bytes, offset))
  use high <- result.try(read_u8(bytes, offset + 1))
  Ok(low + high * 256)
}

fn read_u32(bytes: BitArray, offset: Int) -> Result(Int, Error) {
  use low <- result.try(read_u16(bytes, offset))
  use high <- result.try(read_u16(bytes, offset + 2))
  Ok(low + high * 65_536)
}

fn slice(bytes: BitArray, offset: Int, length: Int) -> Result(BitArray, Error) {
  bit_array.slice(bytes, offset, length)
  |> result.map_error(fn(_) { InvalidFrame })
}

fn xxhash32(bytes: BitArray) -> Int {
  let length = bit_array.byte_size(bytes)
  let #(hash, offset) = case length >= 16 {
    True -> {
      let #(v1, v2, v3, v4, offset) =
        xxhash_stripes(
          bytes,
          0,
          add32(prime1, prime2),
          prime2,
          0,
          u32(0 - prime1),
        )
      #(
        add32(
          add32(rotate_left(v1, 1), rotate_left(v2, 7)),
          add32(rotate_left(v3, 12), rotate_left(v4, 18)),
        ),
        offset,
      )
    }
    False -> #(prime5, 0)
  }
  let hash = add32(hash, length)
  let #(hash, offset) = xxhash_words(bytes, offset, hash)
  let hash = xxhash_bytes(bytes, offset, hash)
  hash
  |> xor32(logical_right(hash, 15))
  |> multiply32(prime2)
  |> fn(value) { xor32(value, logical_right(value, 13)) }
  |> multiply32(prime3)
  |> fn(value) { xor32(value, logical_right(value, 16)) }
}

fn xxhash_stripes(
  bytes: BitArray,
  offset: Int,
  v1: Int,
  v2: Int,
  v3: Int,
  v4: Int,
) -> #(Int, Int, Int, Int, Int) {
  case offset + 16 <= bit_array.byte_size(bytes) {
    False -> #(v1, v2, v3, v4, offset)
    True -> {
      let assert Ok(word1) = read_u32(bytes, offset)
      let assert Ok(word2) = read_u32(bytes, offset + 4)
      let assert Ok(word3) = read_u32(bytes, offset + 8)
      let assert Ok(word4) = read_u32(bytes, offset + 12)
      xxhash_stripes(
        bytes,
        offset + 16,
        xxhash_round(v1, word1),
        xxhash_round(v2, word2),
        xxhash_round(v3, word3),
        xxhash_round(v4, word4),
      )
    }
  }
}

fn xxhash_round(accumulator: Int, word: Int) -> Int {
  accumulator
  |> add32(multiply32(word, prime2))
  |> rotate_left(13)
  |> multiply32(prime1)
}

fn xxhash_words(bytes: BitArray, offset: Int, hash: Int) -> #(Int, Int) {
  case offset + 4 <= bit_array.byte_size(bytes) {
    False -> #(hash, offset)
    True -> {
      let assert Ok(word) = read_u32(bytes, offset)
      let hash =
        hash
        |> add32(multiply32(word, prime3))
        |> rotate_left(17)
        |> multiply32(prime4)
      xxhash_words(bytes, offset + 4, hash)
    }
  }
}

fn xxhash_bytes(bytes: BitArray, offset: Int, hash: Int) -> Int {
  case offset == bit_array.byte_size(bytes) {
    True -> hash
    False -> {
      let assert Ok(byte) = read_u8(bytes, offset)
      let hash =
        hash
        |> add32(multiply32(byte, prime5))
        |> rotate_left(11)
        |> multiply32(prime1)
      xxhash_bytes(bytes, offset + 1, hash)
    }
  }
}

fn multiply32(left: Int, right: Int) -> Int {
  let left_low = left % 65_536
  let right_low = right % 65_536
  let left_high = logical_right(left, 16)
  let right_high = logical_right(right, 16)
  u32(
    left_low
    * right_low
    + { left_high * right_low + left_low * right_high }
    * 65_536,
  )
}

fn rotate_left(value: Int, count: Int) -> Int {
  int.bitwise_or(
    u32(int.bitwise_shift_left(value, count)),
    logical_right(value, 32 - count),
  )
  |> u32()
}

fn logical_right(value: Int, count: Int) -> Int {
  int.bitwise_shift_right(u32(value), count)
}

fn xor32(left: Int, right: Int) -> Int {
  int.bitwise_exclusive_or(left, right)
  |> u32()
}

fn add32(left: Int, right: Int) -> Int {
  u32(left + right)
}

fn u32(value: Int) -> Int {
  let value = value % uint32_modulus
  case value < 0 {
    True -> value + uint32_modulus
    False -> value
  }
}
