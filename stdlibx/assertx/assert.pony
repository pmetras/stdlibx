"""
# Assert package

Contains runtime assertions. If you are looking for assertion that only run
when your code was compiled with the `debug` flag, check out `Assert`. For
assertions that are always enabled, check out `Fact`.

|                      | Assert | Fact | Fail | Require |
| -------------------- + :----: + :--: + :--: + :-----: |
| Partial apply        |    ✓   |   ✓  |      |         |
| Debug mode           |    ✓   |      |  ✓   |    ✓    |
| Stop execution       |    ✓   |      |  ✓   |    ✓    |

## When to use assertions

Use assertions (primitives in that package) to assess correctness of the code.
As a consequence, they are debugging tools that are enabled in debug mode by
default. They have minimal or no impact on performance in release mode (unfortunately
that's not always the case presently).

Errors are used for checking expected and unexpected errors while assertions are used
for debugging at the run time to see whether the assumptions are validated or not.

An assertion would stop the program from running, while an error would let the
program continue running. To remain compatible with legacy Pony code, this rule
does not always hold and some assertion primitive have partial methods.

Use assertions when you want to test your assumptions about your program:

* To check pre-conditions, post-conditions and invariants.
* To provide feedback to yourself or your developer team.
* To state things that you expect to be true.
* To check for something that should never happen otherwise it means that
there is a serious ﬂaw in your code.

Use debug methods from the `debug` package for temporary debug output. Remove
the calls from the sources when the bug is fixed.

Use logging methods when you want to trace the run-time status of the program
permanently. Usually, loggers have different levels of reporting depending
on what you want to trace (errors, warning, information, etc.)

## Selecting the righ assertion

Using assertions in Pony can be tricky. You have to answer the following questions:

1. Do you want to be able to resume the violation?

Use `Assert` or `Fact` that have partial `apply` methods.

2. Is it only enabled in debug mode?

Use `Assert`, `Fail` or `Require` that are enabled in debug mode. You can
also use `Fact` but you must include it into a `ifdef debug then ... end` block.

`Fact` is always enabled in release mode, while `Fail` is enabled in release
mode only if `abort` is set to `true`.

3. Does the violation stops program execution?

`Assert` and `Fail` stop program execution when `abort` is set to `true`. `Require`
always stops execution when the condition is violated.

## Impact on performance and memory use

Usually an assertion tries to be a void operations in release mode, but evaluation
of its parameters is not. Particularly, if you build a `msg` string from the
context of the call, this operation will always occur, even in release mode.
To prevent this and avoid creating new `String` and other objects, you should
guard the assertion call into an `ifdef debug then ... end` block.

All assertions' `apply` methods return a boolean value, generally the value of `test`.
If you want to stop execution when the condition fails, with no performance impact
in release mode and no object allocations when the condition is false (Simulating
`#assert` in C/C++). Use the
[following pattern](https://patterns.ponylang.io/performance/boolean-short-circuit):

```pony
ifdef debug then
  (condition) or Fail(["Condition ("; condition; ") is false"])
end
```

Note: We don't use `Format` in the assert package to limit memory allocation and
because messages are debug messages that don't require formatting usually. 
"""

use @pony_os_stderr[Pointer[U8]]()
use @fprintf[I32](stream: Pointer[U8] tag, fmt: Pointer[U8] tag, ...)
use @exit[None](exit_code: I32)


primitive Assert
  """
  This is a debug only assertion. If the test is false, it will print any
  supplied error message to stderr and raise an error. If `abort` is
  true, then program execution will stop in debug mode, printing
  location where the condition was violated. This fail-fast version can help
  find bugs when the `test` condition does not hold instead of propagating
  an unrecoverable error.
  """

  fun apply(test: Bool,
            msg: (Stringable | ReadSeq[Stringable]) = "",
	          abort: Bool = false,
	          loc: SourceLoc = __loc): Bool ? =>
    """
    When the program is compiled in debug mode (`ponyc -d`) and when `test` is
    `false`, it prints an error message to the standard error stream with
    current execution location in source code (can be changed by supplying
    `loc` parameter). If `abort` is `true`, it stops execution of the program.
    
    When the program is not compiled in debug mode, this function does nothing
    and has no impact on performance.

    If the `msg` is given as a list of `Stringable`, elements are concatenated.

    This method returns the value of `test` and can be used with
    [boolean short-circuit](https://patterns.ponylang.io/performance/boolean-short-circuit)
    pattern
    """
    ifdef debug then
      try
        Fact(test, msg)?
      else
        if abort then
          @fprintf(@pony_os_stderr(),
            "ABORT: Unreachable condition at %s:%zu (in %s method)\n".cstring(),
            loc.file().cstring(),
            loc.line(),
            loc.method_name().cstring())
          @exit(1)
        end
        error
      end
    end
    test


primitive Fact
  """
  This is an assertion that is always enabled. If the test is false, it will
  print any supplied error message to stderr and raise an error.

  In debug mode, it is equivalent to:

  ```pony
  if not test then
    Debug(msg, "", DebugErr)
  end
  """

  fun apply(test: Bool, msg: (Stringable | ReadSeq[Stringable]) = ""): Bool ? =>
    """
    When `test` is `false`, it prints the message `msg` to the standard error
    stream and raises an error.

    If the `msg` is given as a list of `Stringable`, elements are all concatenated.

    This method returns the value of `test` and can be used with
    [boolean short-circuit](https://patterns.ponylang.io/performance/boolean-short-circuit)
    pattern
    """
    if not test then
      let msg' = match \exhaustive\ msg
      | let m: Stringable => m.string()
      | let m: ReadSeq[Stringable] => "".join(m.values())
      end

      if msg'.size() > 0 then
        @fprintf(@pony_os_stderr(), "%s\n".cstring(), msg'.cstring())
      end
      error
    end
    test


primitive Fail
  """
  The `Fail` primitive contains functions to stop execution of the program
  immediately, usually because a bug has been detected in the code.
  """

  fun apply(msg: (Stringable | ReadSeq[Stringable]) = "",
            abort: Bool = false,
            loc: SourceLoc = __loc): Bool =>
    """
    Make the program abort and print on stderr the current location. This can be
    used for algorithmic bug in code. By default, it's only enabled in debug
    mode; it can be changed by setting the `abort` parameter to `true`.

    As this function never returns, it is not partial and can be used without
    being enclosed in `try` ... `end` block. This function is not equivalent to
    `try Assert(false, msg, abort)? end` as it will stop execution even when
    code is not compiled in `debug` mode.

    If the `msg` is given as a list of `Stringable`, elements are concatenated.

    The `Fail` function can be used in situations where you must limit allocation
    or objects, for instance in a loop where you want to validate an invariant,
    by using [boolean short-circuit](https://patterns.ponylang.io/performance/boolean-short-circuit)
    pattern:

    ```pony
    (invariant > 0) or Fail(["Invariant ("; invariant; ") must be positive"])
    ```

    The strings allocation of the message and the array construction will only
    occur if the test fails. If allocations are not a problem and you want to
    enable it only in debug mode, use the [`Require`](Require#) assertion instead.

    The method always returns `true`.
    """
    if _debug_or_abort(abort) then
      let msg' = match \exhaustive\ msg
      | let m: Stringable => m.string()
      | let m: ReadSeq[Stringable] => "".join(m.values())
      end

      @fprintf(@pony_os_stderr(),
               "FAIL: at %s:%zu (in %s method)\n%s\n".cstring(),
               loc.file().cstring(),
               loc.line(),
               loc.method_name().cstring(),
	       msg'.cstring())
      @exit(1)
    end
    true


  fun _debug_or_abort(abort: Bool): Bool =>
    """
    Return `true` when the code is compiled in debug mode or when `abort` is
    `true`.
    """
    ifdef debug then
      true
    else
      abort
    end


primitive Require
  """
  This is a debug-only assertion similar to preconditions in
  [Design by Contract](https://en.wikipedia.org/wiki/Design_by_contract).
  If the test is false, it prints any supplied error message to stderr and
  program execution stops when in debug mode, printing location where the
  condition was violated. This fail-fast assertion must be used to prevent
  bugs propagation, when error recovery is impossible.
  """

  fun apply(test: Bool,
            msg: (Stringable | ReadSeq[Stringable]) = "",
	          loc: SourceLoc = __loc): Bool =>
    """
    When the program is compiled in debug mode (`ponyc -d`) and when `test` is
    `false`, print an error message to the standard error stream with
    current execution location in source code (can be changed by supplying
    `loc` parameter) and stop execution of the program.
    
    When the program is not compiled in debug mode, this function does nothing.

    As this function never returns in case of failure, it is not partial and can
    be used without being enclosed in `try` ... `end` block. This function is
    equivalent to `try Assert(test, msg, true)? end`.

    If the `msg` is given as a list of `Stringable`, elements are all concatenated.

    This method returns the value of `test` and can be used with
    [boolean short-circuit](https://patterns.ponylang.io/performance/boolean-short-circuit)
    pattern
    """
    ifdef debug then
      test or Fail(msg, true, loc)
    end
    test
