// The trait for comparison of approximated real numbers

interface val Approximated[HI: Any #read, LO: (Float & FloatingPoint[LO])]
  """
  A trait for types that can be compared for approximate equality.
  """
  fun box almost_eq(that: box->HI, rel_tol: LO = LO.epsilon().sqrt(), abs_tol: LO = LO.epsilon().sqrt()): Bool
