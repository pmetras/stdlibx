use "../assertx"
use "../formatx"


primitive BinarySearch
  """
  Search function into sorted arrays using
  [binary search](https://en.wikipedia.org/wiki/Binary_search_algorithm).
  """

  fun apply[K: Comparable[K] #read, V: Any #read](needle: K,
      haystack: ReadSeq[V] box,
      retrieve: {(box->V): K}
      ): (USize, Bool) =>
    """
    Perform a binary search for `needle` on `haystack` and returns the index in
    `haystack` where it can be found. The `retrieve` parameter gives the way to
    get the `K` from a `V` in `haystack` in order to compare it with `needle`.

    Note that `haystack` *must* be sorted else the result is undefined.

    Returns the result as a 2-tuple of either:
    * the index of the found element and `true` if the search was successful, or
    * the index where to insert the `needle` to maintain a sorted `haystack` and `false`.

    This implementation uses only 2 comparisons per loop iteration, with an
    extra comparison after the loop to check for equality.
    """
    if haystack.size() == 0 then
      return (0, false)
    end
    var left: USize = 0
    var right: USize = haystack.size()
    try
      while left != right do
        // To prevent overflow when calculating index value
        let index = left + ((right - left) / 2)
        let elem = haystack(index)?
        if needle.compare(retrieve(elem)) == Greater then
            left = index + 1
        else
            right = index
        end
      end
      // left == right: check if needle was found at the convergence point
      if left < haystack.size() then
        let elem = haystack(left)?
        if needle.compare(retrieve(elem)) == Equal then
          return (left, true)
        end
      end
      // Not found: left is the correct insert position
      (left, false)
    else
      // Shouldn't happen
      Fail(Format("[BinarySearch.apply] Invalid haystack access at index {}", left))
      (0, false)
    end
