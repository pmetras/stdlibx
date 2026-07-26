iuse "pony_test"

use "../stdlibx"

actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() => None

  fun tag tests(tests: PonyTest) =>
    ArtTreeTests.tests(tests)
