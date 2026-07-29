# Pony stdlib extensions

This project contains multiple sub-projects that are extensions to the [Pony language](https://www.ponylang.io) standard library. They were written to test and enhance the standard library with missing features, before suggesting them to the community. The work is not complete but I don't have the energy to continue it, and I share it as-is.

## Repositories

Sources are maintained with [Fossil](https://fossil-scm.org) and mirrored to GitHub as 4 separate repositories:

- [bitsx](https://github.com/pmetras/bitsx)
- [formatx](https://github.com/pmetras/formatx)
- [mathx](https://github.com/pmetras/mathx)
- [stdlibx](https://github.com/pmetras/stdlibx)

Because of the symbolic links described below, clone all 4 repositories side by side under the same parent directory, using these exact names, for the build to work:

```
stdlibx/
├── bitsx/
├── formatx/
├── mathx/
└── stdlibx/
```

## Main features

Here is what you can expect to find in this code:

### `bitx`: set of bits

These bit classes inspired by the [Roaring Bitmaps](https://github.com/RoaringBitmap/) are used with sets of bits. They could be used to handle bit indexes in a database.

- The `BitSet` class to handle large sets of bits. Depending on the *density* of the set, the internal structure changes to always provide the best space/performance ratio.
- The `BitMap` class is the non-optimized version you can use with smaller sets of bits.
- A `BitRange` is a bitmap where the bit values are in a range.
- All structures support individual or range bit operations, in-place or by clone.
- Iterators on bits.
- [Roaring Serialization Format](https://github.com/RoaringBitmap/RoaringFormatSpec) support.
- Some methods to ease bit mask operations.

### List of examples

- `eratosthenes`: Finding primes with Eratosthenes sieve algorithm, using `BitSet`.
- `eratosthenes_bitmap`: The same code but using `BitMap` class.
- `eratosthenes_instrumented`: This version of the code is instrumented to show when the `BitSet` dynamic data-structure changes its internal representation.
- `eratosthenes_optimized`: Again the same algorithm, but checking for non-prime and having a sparse set.
- `tcp_packet`: How to decode TCP headers using bit masks.

### `formatx`: the missing string formatting class

[Formatting strings](https://stdlib.ponylang.io/format--index/) in Pony is anemic. It handles basic alignment and number formats. It can't be easily extended with custom formats for other types. It does not support localisation or internationalisation. The `formatx` package provides a replacement similar to what can be found in Rust or Python f-strings.

- A simple formatting language similar to the one of Python.
- Extensible by other classes. They only need to implement the `Formattable` trait.
- Highly optimized code to limit strings allocation.

### List of examples

- `formattable`: How to adapt and extend the format specification to new types.
- `i18n`: Internationalisation of user messages.
- `progress`: A simple progress-bar.
- `table`: Format results in a table.

### `mathx`: can Pony do maths?

Can we combine parallel processing in Pony with maths calculations? Unfortunately, the Pony maths library is quite scarce. After buying a copy of [Numerical Recipes](https://numerical.recipes), I wanted to implement some algorithms to answer this question. The `mathx` package is actually what started this project, when I discovered that FFT was used in arbitrary-precision multiplication (see [22.7 Arithmetic at Arbitrary Precision](https://numerical.recipes/book.html)).

- The `Complex` class is the classical complex numbers class, but trying to prevent some numerical pitfalls.
- The `Primes` primitive has some advanced primality tests.
- Do modular arithmetic with the `Modular` primitive.
- Test the numerical limits of the platform with `Limits` and use correct rounding modes with `RoundingMode`.
- Multiple Fast Fourier Transform algorithms are implemented into `FFT` and `NTT`.
- The `bignum` package implements unlimited-precision integers `MPInt` and real numbers `MPFloat`. These classes are highly optimized. There's even an implementation using the [Gnu MP](https://gmplib.org) library that is used to test the Pony implementation. The quality of the library is quite good, while GMP is excellent.

### List of examples

- `benchmark`: Checking improvement of `MPInt` implementation with benchmarks.
- `benford`: Does the Benford law hold?
- `collatz_modular`: Verifying the Collatz conjecture using modular arithmetic.
- `collatz_mpint`: Verifying the Collatz conjecture using big integers.
- `collatz_parallel`: A parallel version with actors of the Collatz conjecture checker.
- `constants`: Compute well-known mathematical constants at arbitrary precision.
- `factstats`: Analyze the distribution of digits in factorial numbers.
- `fp_pitfalls`: A list of floating-point pitfalls and how to avoid them with `MPFloat`.
- `fractal`: Display the Julia set using complex numbers.
- `platform_limits`: Calculate the numerical limits of the platform.
- `prime_counter`: There is an infinity of prime numbers. But what is their density?

### `stdlibx`: some missing pieces

All the previous packages were developed as standalone projects. Sometimes, small changes to existing stdlib packages were required. For instance, the `Debug` primitive is enhanced to return `true` so that it can be used in [short-circuit evaluations](https://patterns.ponylang.io/performance/boolean-short-circuit). When the changes were limited and did not require a dedicated package, they were collected in the `stdlibx` package.

- An enhanced `Debug` primitive that can be used in boolean expressions.
- `BinarySearch` algorithm.
- Extending the `assert` package with real assertions: stop execution as soon as assertion fails.
- `ArtTree` implementing an [optimized trie data-structure](https://arxiv.org/pdf/1603.06549) has been added to the `collections` package. This is used in the `bitx` bits-management package.
- The `pony_testx` package duplicates the content of `pony_test` and adds an `Approximated` interface that is used to compare floating-point numbers with error ranges. If I had time to implement a new mathematical-types hierarchy, this interface would live there.

### List of examples

All the examples of the sub-packages are linked here and give a complete view of `stdlibx` examples.

## Common features

- `make help` prints the available `make` commands.
- All classes or actors, all fields and all methods have extensive documentation, even private ones.
- Numerous examples on how to use the package features.
- Numerous extensive tests.

## Changes from Pony's standard

Pony does a lot of things right but I disagree with some Pony decisions and I've applied my own conventions in the code. Here are the main differences with Pony's standard and justifications for my choices. They are detailed in the `STYLE_GUIDE.md` that can be used by AI agents.

- All objects, fields and methods must have documentation. Pony implements docstrings and deserves good documentation. Extensive documentation is important for a language's acceptance by new users.
- Open-source code is more frequently read than executed. The layout of source code must look good and ease reading. Pony has a nice syntax. The sources must be readable without effort. Methods are separated by **2** empty lines, and all code lines have only 1 instruction. Spaces are important in source code...
- Correctness is more important than speed. When a bug is detected, it must be reported immediately by stopping execution. The `Assert` methods just stop the program when something seems wrong in debug mode.

## Organisation of the packages

The names of the directories have an `x` suffix so as not to clash with existing modules, and to eventually allow simple replacement in Pony source code. In order to work on packages as independent projects, I've used many symbolic links between directories. Git and GitHub handle symbolic links fine, but this means the 4 repositories must be cloned side by side under the same parent directory, as explained above. Here is the whole directory hierarchy (this only includes directories that are not created by `make`).

```
    stdlibx
    ├── README.md <== The file you are reading presently!
    ├── examples
    │   ├── collatz_parallel -> ../../mathx/examples/collatz_parallel/
    │   ├── eratosthenes -> ../../bitsx/examples/eratosthenes
    │   ├── formattable -> ../../formatx/examples/formattable/
    │   ├── factstats -> ../../mathx/examples/factstats/
    │   ├── benford -> ../../mathx/examples/benford/
    │   ├── fp_pitfalls -> ../../mathx/examples/fp_pitfalls/
    │   ├── prime_counter -> ../../mathx/examples/prime_counter/
    │   ├── table -> ../../formatx/examples/table/
    │   ├── fractal -> ../../mathx/examples/fractal/
    │   ├── constants -> ../../mathx/examples/constants/
    │   ├── eratosthenes_instrumented -> ../../bitsx/examples/eratosthenes_instrumented/
    │   ├── platform_limits -> ../../mathx/examples/platform_limits/
    │   ├── collatz_mpint -> ../../mathx/examples/collatz_mpint/
    │   ├── benchmark -> ../../mathx/examples/benchmark/
    │   ├── tcp_packet -> ../../bitsx/examples/tcp_packet/
    │   ├── progress -> ../../formatx/examples/progress/
    │   ├── eratosthenes_bitmap -> ../../bitsx/examples/eratosthenes_bitmap/
    │   ├── collatz_modular -> ../../mathx/examples/collatz_modular/
    │   ├── i18n -> ../../formatx/examples/i18n/
    │   ├── eratosthenes_optimized -> ../../bitsx/examples/eratosthenes_optimized/
    ├── stdlibx
    │   ├── debugx
    │   ├── formatx -> ../../formatx/formatx/
    │   ├── pony_testx
    │   ├── collectionsx
    │   ├── mathx -> ../../mathx/
    │   ├── assertx
    │   ├── algorithmsx
    │   ├── bitsx -> ../../bitsx/bitsx/
    ├── build
    ├── tests
    formatx
    ├── examples
    │   ├── formattable
    │   ├── table
    │   ├── progress
    │   ├── i18n
    ├── formatx
    ├── pony_testx -> ../stdlibx/stdlibx/pony_testx/
    ├── assertx -> ../stdlibx/stdlibx/assertx/
    ├── AGENTS.md -> ../stdlibx/AGENTS.md
    ├── build
    ├── tests
    ├── STYLE_GUIDE.md -> ../stdlibx/STYLE_GUIDE.md
    mathx
    ├── examples
    │   ├── collatz_parallel
    │   ├── factstats
    │   ├── benford
    │   ├── fp_pitfalls
    │   ├── prime_counter
    │   ├── fractal
    │   ├── constants
    │   ├── platform_limits
    │   ├── collatz_mpint
    │   ├── benchmark
    │   ├── collatz_modular
    ├── formatx -> ../stdlibx/stdlibx/formatx
    ├── pony_testx -> ../stdlibx/stdlibx/pony_testx/
    ├── mathx
    ├── tests_bignum_gmp
    │   ├── _tests_bigreal_suites.pony -> ../tests_bignum/_tests_bigreal_suites.pony
    ├── assertx -> ../stdlibx/stdlibx/assertx/
    ├── drafts
    │   ├── gmp
    ├── docs
    ├── AGENTS.md -> ../stdlibx/AGENTS.md
    ├── build
    ├── tests_bignum
    ├── bitsx -> ../stdlibx/stdlibx/bitsx
    ├── bignum
    │   ├── gmp
    ├── tests
    ├── STYLE_GUIDE.md -> ../stdlibx/STYLE_GUIDE.md
    bitsx
    ├── debugx -> ../stdlibx/stdlibx/debugx/
    ├── examples
    │   ├── eratosthenes
    │   ├── eratosthenes_instrumented
    │   ├── tcp_packet
    │   ├── eratosthenes_bitmap
    │   ├── eratosthenes_optimized
    ├── formatx -> ../stdlibx/stdlibx/formatx
    ├── collectionsx -> ../stdlibx/stdlibx/collectionsx/
    ├── assertx -> ../stdlibx/stdlibx/assertx/
    ├── docs
    ├── algorithmsx -> ../stdlibx/stdlibx/algorithmsx/
    ├── AGENTS.md -> ../stdlibx/AGENTS.md
    ├── build
    ├── bitsx
    ├── tests
    │   ├── testdata
    │   ├── testdata64
```

## What remains to be done

- Frequently, there are lists of TODOs at the end of the `README.md` files. Look at these files: that's where I keep tasks and ideas.
- Better maths types. The Pony maths types are not optimal. They mimic the CPU types but they don't model mathematical objects. As a consequence, it is difficult to extend them. For instance, a builtin `FloatingPoint` is necessarily a fixed-sized floating-point representation. I had planned to redesign the maths types based on century-old mathematical concepts. I must have a draft somewhere.
- Check that the [`Gnu MP`](https://gmplib.org) implementation uses the same Pony API as the classes in the `bignum` package.
- Add more features to the math library, like algorithms for differentiation, matrices, vectors, polynomials, etc.
- If you have a lot of courage, improve the Pony compiler for a synchronization primitive. The compiler being reentrant, I did a theoretical demonstration a few years ago that it would be possible to start a pony sub-process to do parallel calculations while waiting for the result and continue main execution when the sub-process has completed. Many mathematical algorithms can be parallelized. But the mathematical mind is mainly synchronous: when you call a function, you don't care if it is calculated synchronously or not, but you care about getting the result at the same place in the source code where you called it.
- Support for a true character type. Unicode has existed for years and Pony still doesn't support it. I had forked the Pony compiler to implement a `CP` primitive encoding a code-point in 32 bits. This was built upon [RFC-179 Unicode strings](https://github.com/ponylang/ponyc/pull/3679/changes) that was never merged into the main branch of code. My version supported generic strings with an encoding type parameter. I can try to unearth the code if someone is interested in having the compiler support Unicode, but it was based on an old version (~2020?).

## Why stop now?

This has been a long project I started a few years ago. But I don't have the energy to continue it. I decided to stop when I encountered typing bugs in the compiler. In my mind, if I can't trust the compiler to guarantee a program types, everything falls down. And the Pony community is so small that such bugs will stay for years. Pony is also missing important features for my projects that won't appear in the language before many years, like true support for UTF-8 characters or escape analysis to allocate some objects in the stack instead of the heap. Also, the goals of the Pony projects are not aligned to mine.

I hope someone will find this code interesting and will push to have it adopted into the Pony standard library instead of rotting in a GitHub corner. Unfortunately, I won't be that person.

This code is released under the [0BSD license](stdlibx/LICENSE) (BSD Zero Clause License), a public-domain-equivalent license. Use it at your will. Ping me at pierre@alterna.tv if you need help.

The code has been validated with Pony compiler version 0.67.
--
Pierre Métras<br>
2026-07-26<br>
pierre@alterna.tv
