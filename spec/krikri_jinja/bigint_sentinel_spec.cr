require "../spec_helper"
require "../../src/krikri_jinja"

# The BIGINT_SENTINEL_PREFIX wire form: krikri stores an integer too wide
# for Int64 (RSA modulus, EC coordinate, big certificate serial) as the
# marked decimal string, because JSON::Any's raw union tops out at Int64.
# The engine must see a real int on the way in and hand the marked string
# back on the way out.
describe "KrikriJinja bigint sentinel round trip" do
  it "from_json_any turns the sentinel string into a BigIntValue" do
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + "17209043716930154488729999570052395225917155184812456045221908594356220999125417"))
    assert_equal(true, value.raw.is_a?(KrikriJinja::BigIntValue))
  end

  it "from_json_any keeps the sign in the sentinel" do
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + "-170141183460469231731687303715884105728"))
    assert_equal(true, value.raw.is_a?(KrikriJinja::BigIntValue))
    assert_equal(true, value.raw.as(KrikriJinja::BigIntValue).negative?)
  end

  it "from_json_any leaves ordinary strings untouched" do
    value = KrikriJinja.from_json_any(JSON::Any.new("17209043716930154488729999570052395225917155184812456045221908594356220999125417"))
    assert_equal("17209043716930154488729999570052395225917155184812456045221908594356220999125417", value.raw)
    value = KrikriJinja.from_json_any(JSON::Any.new("not a number"))
    assert_equal("not a number", value.raw)
  end

  it "to_json_any turns a BigIntValue back into the sentinel string" do
    value = KrikriJinja::AnyValue.new(KrikriJinja::BigIntValue.new("17209043716930154488729999570052395225917155184812456045221908594356220999125417"))
    assert_equal(KrikriJinja::BIGINT_SENTINEL_PREFIX + "17209043716930154488729999570052395225917155184812456045221908594356220999125417",
      KrikriJinja.to_json_any(value).raw)
  end

  it "round-trips through both directions" do
    digits = "23800965703753858131193085529022479458634183690853911634056306445954070220687950718656"
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + digits))
    assert_equal(KrikriJinja::BIGINT_SENTINEL_PREFIX + digits, KrikriJinja.to_json_any(value).raw)
  end

  it "converts a sentinel nested inside containers" do
    json = %({"modulus": ") + KrikriJinja::BIGINT_SENTINEL_PREFIX +
           "23800965703753858131193085529022479458634183690853911634056306445954070220687950718656" + %(", "n": 1})
    value = KrikriJinja.from_json_any(JSON.parse(json))
    hash = value.raw.as(Hash(String, KrikriJinja::AnyValue))
    modulus = hash["modulus"].raw
    assert_equal(true, modulus.is_a?(KrikriJinja::BigIntValue))
    assert_equal(1_i64, hash["n"].raw)
  end
end

describe "KrikriJinja bigint template behavior" do
  it "renders the value unquoted" do
    digits = "23800965703753858131193085529022479458634183690853911634056306445954070220687950718656"
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + digits))
    engine = KrikriJinja::Engine.new
    result = engine.evaluate_parsed(KrikriJinja.parse_expression("m"), variables: {"m" => value})
    assert_equal(digits, KrikriJinja.stringify(result))
  end

  it "answers the integer and number tests" do
    digits = "23800965703753858131193085529022479458634183690853911634056306445954070220687950718656"
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + digits))
    engine = KrikriJinja::Engine.new
    assert_equal(true, engine.evaluate_parsed(KrikriJinja.parse_expression("m is integer"), variables: {"m" => value}).raw)
    assert_equal(true, engine.evaluate_parsed(KrikriJinja.parse_expression("m is number"), variables: {"m" => value}).raw)
    assert_equal(false, engine.evaluate_parsed(KrikriJinja.parse_expression("m is string"), variables: {"m" => value}).raw)
  end

  it "compares against a plain int and an equal big int" do
    digits = "23800965703753858131193085529022479458634183690853911634056306445954070220687950718656"
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + digits))
    engine = KrikriJinja::Engine.new
    assert_equal(true, engine.evaluate_parsed(KrikriJinja.parse_expression("m > 0"), variables: {"m" => value}).raw)
    assert_equal(true, engine.evaluate_parsed(KrikriJinja.parse_expression("m == m2"),
      variables: {"m" => value, "m2" => KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + digits))}).raw)
    assert_equal(false, engine.evaluate_parsed(KrikriJinja.parse_expression("m == 0"), variables: {"m" => value}).raw)
  end

  it "orders against a float exactly, on both operand sides" do
    modulus = "23688257652569231524904892537921609541236628215987918620647196265444254471219156591869830489816504690519050309738252706082906790370102917250013129807758266102036883360127166136832204551631104600018667512152866155447082040452828229084282082666887141431193046290573892051314225817230079732316580520281882349855927157561531766920329152776188412700104203560881623485424031595287444870709234449503813475884970204145019343410169951496067118683377577690877581826204994621521701045839752511443311726408982371278248533694344325362281793968655068114590705165735570867322661989881649035151803040759774533128975731350221690748159"
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + modulus))
    engine = KrikriJinja::Engine.new
    # Converting the digits to Float64 raises "Invalid Float64"; the
    # comparison must answer Python's exact int/float ordering instead
    # (live-verified: `m >= 1.5` True, `1.5 >= m` False).
    assert_equal(true, engine.evaluate_parsed(KrikriJinja.parse_expression("m >= 1.5"), variables: {"m" => value}).raw)
    assert_equal(false, engine.evaluate_parsed(KrikriJinja.parse_expression("1.5 >= m"), variables: {"m" => value}).raw)
    assert_equal(true, engine.evaluate_parsed(KrikriJinja.parse_expression("m > 1e300"), variables: {"m" => value}).raw)
    assert_equal(false, engine.evaluate_parsed(KrikriJinja.parse_expression("1e300 > m"), variables: {"m" => value}).raw)
    # An in-range pair still compares exactly (2^53 + 1 vs float 2^53).
    one_up = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + "9007199254740993"))
    assert_equal(true, engine.evaluate_parsed(KrikriJinja.parse_expression("x > 9007199254740992.0"), variables: {"x" => one_up}).raw)
    assert_equal(false, engine.evaluate_parsed(KrikriJinja.parse_expression("x == 9007199254740992.0"), variables: {"x" => one_up}).raw)
  end

  it "negates the value in unary minus and comparisons" do
    digits = "23800965703753858131193085529022479458634183690853911634056306445954070220687950718656"
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + digits))
    engine = KrikriJinja::Engine.new
    assert_equal("-" + digits, KrikriJinja.stringify(engine.evaluate_parsed(KrikriJinja.parse_expression("-m"), variables: {"m" => value})))
    assert_equal(true, engine.evaluate_parsed(KrikriJinja.parse_expression("-m < 0"), variables: {"m" => value}).raw)
    assert_equal(false, engine.evaluate_parsed(KrikriJinja.parse_expression("-m > 0"), variables: {"m" => value}).raw)
  end

  it "float over a modulus-scale int raises instead of coercing" do
    modulus = "23688257652569231524904892537921609541236628215987918620647196265444254471219156591869830489816504690519050309738252706082906790370102917250013129807758266102036883360127166136832204551631104600018667512152866155447082040452828229084282082666887141431193046290573892051314225817230079732316580520281882349855927157561531766920329152776188412700104203560881623485424031595287444870709234449503813475884970204145019343410169951496067118683377577690877581826204994621521701045839752511443311726408982371278248533694344325362281793968655068114590705165735570867322661989881649035151803040759774533128975731350221690748159"
    value = KrikriJinja.from_json_any(JSON::Any.new(KrikriJinja::BIGINT_SENTINEL_PREFIX + modulus))
    engine = KrikriJinja::Engine.new
    error = assert_raises(KrikriJinja::TemplateError) do
      engine.evaluate_parsed(KrikriJinja.parse_expression("m | float"), variables: {"m" => value})
    end
    assert_equal(true, (error.message || "").includes?("int too large to convert to float"))
  end
end
