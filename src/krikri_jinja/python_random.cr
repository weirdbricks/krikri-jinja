module KrikriJinja
  class PythonRandom
    @state : Array(UInt32)
    @index : Int32

    def initialize(seed : Int64)
      value = seed < 0 ? (-(seed.to_i128 + 1)).to_u64 + 1_u64 : seed.to_u64
      key = value == 0 ? [0_u64] : split_words(value)
      @state = Array(UInt32).new(624, 0_u32)
      @state[0] = 19650218_u32
      1.upto(623) do |position|
        @state[position] = 1812433253_u32 &* (@state[position - 1] ^ (@state[position - 1] >> 30)) &+ position.to_u32
      end
      state_index = 1
      key_index = 0
      624.times do
        @state[state_index] = (@state[state_index] ^ ((@state[state_index - 1] ^ (@state[state_index - 1] >> 30)) &* 1664525_u32)) &+
          key[key_index].to_u32 &+ key_index.to_u32
        state_index += 1
        key_index += 1
        if state_index >= 624
          @state[0] = @state[623]
          state_index = 1
        end
        if key_index >= key.size
          key_index = 0
        end
      end
      623.times do
        @state[state_index] = (@state[state_index] ^ ((@state[state_index - 1] ^ (@state[state_index - 1] >> 30)) &* 1566083941_u32)) &-
          state_index.to_u32
        state_index += 1
        if state_index >= 624
          @state[0] = @state[623]
          state_index = 1
        end
      end
      @state[0] = 0x80000000_u32
      @index = 624
    end

    def rand(max : UInt64) : UInt64
      bits = max.bit_length
      loop do
        value = getrandbits(bits)
        return value if value < max
      end
    end

    private def split_words(value : UInt64) : Array(UInt64)
      words = [] of UInt64
      while value > 0
        words << (value & 0xffffffff_u64)
        value >>= 32
      end
      words
    end

    private def getrandbits(count : Int32) : UInt64
      return 0_u64 if count == 0
      first = next_word
      return (first >> (32 - count)).to_u64 if count <= 32
      second = next_word
      (first.to_u64 | (second.to_u64 << 32)) & ((1_u64 << count) - 1_u64)
    end

    private def next_word : UInt32
      generate_state if @index >= 624
      value = @state[@index]
      @index += 1
      value ^= value >> 11
      value ^= (value << 7) & 0x9d2c5680_u32
      value ^= (value << 15) & 0xefc60000_u32
      value ^= value >> 18
      value
    end

    private def generate_state
      0.upto(623) do |position|
        value = (@state[position] & 0x80000000_u32) | (@state[(position + 1) % 624] & 0x7fffffff_u32)
        shifted = value >> 1
        shifted ^= 0x9908b0df_u32 if (value & 1) == 1
        @state[position] = @state[(position + 397) % 624] ^ shifted
      end
      @index = 0
    end
  end
end
