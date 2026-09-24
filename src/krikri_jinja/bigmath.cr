module KrikriJinja
  # Decimal-string big-int helpers shared by pow and add overflow paths.
# Decimal-string bignum: needed when Int64 pow overflows (Python has
# arbitrary-precision ints).
def self.big_pow(base : Int64, exp : Int64) : String
  r = "1"
  b = base.to_s
  e = exp
  while e > 0
    r = big_mul(r, b) if e & 1 == 1
    b = big_mul(b, b)
    e >>= 1
  end
  r
end

def self.big_add(a : String, b : String) : String
  na = a.starts_with?('-')
  nb = b.starts_with?('-')
  da = a.lstrip('-')
  db = b.lstrip('-')
  if na == nb
    sum = [] of Int32
    i = da.size - 1
    j = db.size - 1
    carry = 0
    while i >= 0 || j >= 0 || carry > 0
      t = carry
      t += da[i].to_i if i >= 0
      t += db[j].to_i if j >= 0
      sum << t % 10
      carry = t // 10
      i -= 1
      j -= 1
    end
    mag = sum.reverse.join
    mag = mag.sub(/\A0+(?=\d)/, "")
    na ? "-#{mag}" : mag
  else
    neg = big_cmp(da, db) < 0
    big = neg ? db : da
    small = neg ? da : db
    diff = [] of Int32
    i = big.size - 1
    j = small.size - 1
    borrow = 0
    while i >= 0
      t = big[i].to_i - borrow
      t -= small[j].to_i if j >= 0
      if t < 0
        t += 10
        borrow = 1
      else
        borrow = 0
      end
      diff << t
      i -= 1
      j -= 1
    end
    mag = diff.reverse.join.sub(/\A0+(?=\d)/, "")
    mag = "0" if mag.empty?
    (neg ^ na) ? "-#{mag}" : mag
  end
end

def self.big_cmp(a : String, b : String) : Int32
  return a.size <=> b.size unless a.size == b.size
  a <=> b
end

def self.big_mul(a : String, b : String) : String
  neg = false
  if a.starts_with?('-')
    neg = !neg
    a = a[1..]
  end
  if b.starts_with?('-')
    neg = !neg
    b = b[1..]
  end
  digits = Array(Int32).new(a.size + b.size, 0)
  a.chars.reverse.each_with_index do |ca, i|
    next if ca == '0'
    da = ca - '0'
    b.chars.reverse.each_with_index do |cb, j|
      digits[i + j] += da * (cb - '0')
    end
  end
  carry = 0
  digits.each_index do |i|
    t = digits[i] + carry
    digits[i] = t % 10
    carry = t // 10
  end
  s = String.build do |io|
    digits.reverse_each do |d|
      io << d
    end
  end
  s = s.lstrip('0')
  s = "1" if s.empty?
  neg ? "-#{s}" : s
end
end
