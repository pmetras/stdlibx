use "../stdlibx/pony_testx"

use "../stdlibx"

actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    ArtTreeTests.tests(test)
